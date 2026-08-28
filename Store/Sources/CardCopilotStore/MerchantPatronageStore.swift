import Foundation

/// Stable identity used by purchase history, patronage, and arrival-alert preferences.
/// Recognised retailers use their chain id so another branch can match; an unrecognised local
/// merchant uses a normalized-name namespace and therefore only supports an exact-location
/// alert. The preference itself retains the POI id and coordinates for precise matching.
public let localMerchantKeyPrefix = "local:"

public func merchantActivityKey(name: String, locationIdentifier: String?) -> String? {
    if let chain = MerchantRecognizer.recognise(name)?.id { return chain }
    let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let normalized = folded.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .joined()
    if !normalized.isEmpty { return localMerchantKeyPrefix + normalized }
    guard let locationIdentifier, !locationIdentifier.isEmpty else { return nil }
    return localMerchantKeyPrefix + locationIdentifier
}

public func supportsChainArrivalAlerts(merchantKey: String) -> Bool {
    !merchantKey.hasPrefix(localMerchantKeyPrefix)
}

/// Which merchants the owner keeps paying at, and on how many separate days.
///
/// Deliberately holds only day keys plus the display label needed by the owner-facing list. Not
/// the amount, not the card, not the coordinate — those already live with the purchase, and a
/// second copy here would be a retention liability serving no decision this file makes. Both the
/// visits and their labels are pruned to the patronage window on every write.
///
/// Lives in the shared App Group suite because the writer and the reader are not reliably the
/// same process: visits are recorded from the Wallet Capture App Intent, and standing is read on
/// a geofence wake.
public final class MerchantPatronageStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults,
                key: String = "ca.pickme.merchant-patronage.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Notes that the owner paid at this merchant on this day.
    ///
    /// Idempotent within a day by construction: the unit stored is the day, so a second capture
    /// at the same shop the same afternoon changes nothing. A blocked merchant refuses the write
    /// outright — blocking stops collection, not just display, so a capture that slips through
    /// before the block list is consulted elsewhere still cannot accrue standing here.
    public func recordVisit(merchantKey: String, displayName: String? = nil,
                            at date: Date = Date(),
                            calendar: Calendar = .current) {
        guard !isBlocked(merchantKey: merchantKey) else { return }
        var all = load()
        all[merchantKey, default: []].insert(patronageDayKey(for: date, calendar: calendar))
        let retained = pruned(all, asOf: date, calendar: calendar)
        save(retained)
        var names = loadDisplayNames().filter { retained[$0.key] != nil }
        if let displayName, !displayName.isEmpty {
            names[merchantKey] = displayName
        }
        saveDisplayNames(names)
    }

    public func visitDayKeys(for merchantKey: String) -> Set<String> {
        load()[merchantKey] ?? []
    }

    public func isFrequented(merchantKey: String, asOf date: Date = Date(),
                             calendar: Calendar = .current) -> Bool {
        CardCopilotStore.isFrequented(visitDayKeys: visitDayKeys(for: merchantKey),
                                      asOf: date, calendar: calendar)
    }

    /// Every merchant standing today. Read once per arrival rather than per candidate POI, since
    /// an area resolution asks about several names in a row on a background wake.
    ///
    /// Filters blocked keys defensively even though `block` already wipes their data: a merchant
    /// blocked between load and filter (there is no transaction here) should never show standing.
    public func frequentedKeys(asOf date: Date = Date(), calendar: Calendar = .current) -> Set<String> {
        let blocked = loadBlocked()
        return Set(load().filter {
            !blocked.contains($0.key)
                && CardCopilotStore.isFrequented(visitDayKeys: $0.value, asOf: date, calendar: calendar)
        }.keys)
    }

    /// Drops one merchant's visit history without touching any other.
    public func forget(merchantKey: String) {
        var all = load()
        all.removeValue(forKey: merchantKey)
        save(all)
        var names = loadDisplayNames()
        names.removeValue(forKey: merchantKey)
        saveDisplayNames(names)
    }

    // MARK: - Block list

    /// Stops a merchant from ever earning patronage standing again. Wipes any visits already
    /// accrued — "never learn this place" is a promise about the future, and leaving stale
    /// visit-days behind would let an `unblock` silently resurrect standing the owner asked to
    /// forget.
    public func block(merchantKey: String) {
        forget(merchantKey: merchantKey)
        var blocked = loadBlocked()
        blocked.insert(merchantKey)
        saveBlocked(blocked)
    }

    public func unblock(merchantKey: String) {
        var blocked = loadBlocked()
        blocked.remove(merchantKey)
        saveBlocked(blocked)
    }

    public func isBlocked(merchantKey: String) -> Bool {
        loadBlocked().contains(merchantKey)
    }

    public func blockedKeys() -> Set<String> {
        loadBlocked()
    }

    /// A read model for the owner-facing list: display name, standing, and the window's edges,
    /// resolved once per merchant rather than re-derived per row by the view.
    public struct LearnedMerchant: Identifiable, Equatable, Sendable {
        public var id: String { merchantKey }
        public let merchantKey: String
        public let displayName: String
        public let visitCount: Int
        public let earliestDayKey: String
        public let latestDayKey: String
        public let qualifies: Bool
    }

    public func learnedMerchants(asOf date: Date = Date(), calendar: Calendar = .current) -> [LearnedMerchant] {
        let names = loadDisplayNames()
        return load().compactMap { key, days in
            let live = patronageDaysWithinWindow(days, asOf: date, calendar: calendar)
            guard let earliest = live.min(), let latest = live.max() else { return nil }
            let displayName = names[key]
                ?? CanadianMerchantPreIndex.all.first { $0.id == key }?.name
                ?? key
            return LearnedMerchant(merchantKey: key, displayName: displayName, visitCount: live.count,
                                   earliestDayKey: earliest, latestDayKey: latest,
                                   qualifies: live.count >= patronageVisitDaysRequired)
        }
    }

    /// Called when the owner erases this iPhone's history. Clears the block list too: this is a
    /// full wipe, and a block silently surviving it would keep suppressing a merchant for a
    /// reason the owner no longer has any way to see or reverse.
    public func forgetAll() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: blockedKeysKey)
        defaults.removeObject(forKey: displayNamesKey)
    }

    // MARK: - Storage

    /// Pruning runs across every merchant, not only the one just written. A shop the owner
    /// stopped going to would otherwise keep its rows forever, because nothing would ever write
    /// to it again — the exact case the retention promise is about.
    private func pruned(_ all: [String: Set<String>], asOf date: Date,
                        calendar: Calendar) -> [String: Set<String>] {
        var kept: [String: Set<String>] = [:]
        for (merchant, days) in all {
            let live = patronageDaysWithinWindow(days, asOf: date, calendar: calendar)
            if !live.isEmpty { kept[merchant] = live }
        }
        return kept
    }

    private func load() -> [String: Set<String>] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save(_ value: [String: Set<String>]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private var blockedKeysKey: String { key + ".blocked" }
    private var displayNamesKey: String { key + ".names" }

    private func loadDisplayNames() -> [String: String] {
        defaults.dictionary(forKey: displayNamesKey) as? [String: String] ?? [:]
    }

    private func saveDisplayNames(_ value: [String: String]) {
        defaults.set(value, forKey: displayNamesKey)
    }

    private func loadBlocked() -> Set<String> {
        Set(defaults.stringArray(forKey: blockedKeysKey) ?? [])
    }

    private func saveBlocked(_ value: Set<String>) {
        defaults.set(Array(value), forKey: blockedKeysKey)
    }
}
