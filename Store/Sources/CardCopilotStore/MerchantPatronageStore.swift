import Foundation

/// Stable identity used by purchase history, patronage, and arrival-alert preferences.
/// Recognised retailers use their chain id so another branch can match; an unrecognised local
/// merchant uses a normalized-name namespace and therefore only supports an exact-location
/// alert. The preference itself retains the POI id and coordinates for precise matching.
public let localMerchantKeyPrefix = "local:"

/// Divides the name token from the place token in a local key: `local:momskitchen#4365_-7938`.
/// `#` cannot occur in either half — the name is folded to alphanumerics and the cell is two
/// integers — so splitting on it is unambiguous.
public let localMerchantCellSeparator: Character = "#"

/// The activity key for a merchant, optionally pinned to where it stands.
///
/// A recognised chain answers with its chain id, unchanged and on purpose: that is what lets a
/// Metro you have never entered inherit standing from the Metro you shop at weekly, and what
/// `ArrivalAlertScope.chain` exists to let the owner opt into.
///
/// The unrecognised case is the one that was wrong. It answered `local:` plus the normalized name
/// and nothing else, so every independent shop in Canada sharing a name shared one key — and the
/// three things that key addresses are not counters, they are the owner's decisions. Blocking one
/// "Rose Cafe" wiped the visits of every namesake and suppressed them all permanently; saving an
/// alert preference for the second one silently overwrote the first; the learned-merchants list
/// showed a single pooled row under whichever display name was written last.
///
/// (Worth being precise about what this did *not* break, because it is easy to assume it did:
/// `.frequented` promotion is unaffected. Every promotion path — `resolveDiscoveredMerchant` and
/// `AmbientLocationService.rotateRegions` — tests `frequentedKeys.contains(indexed.id)` against a
/// `MerchantRecognizer` chain id. A `local:` key is never the subject of that test, so pooled
/// local visits could not promote anything. This is a consent defect, not a ladder defect.)
///
/// Passing coordinates yields a *qualified* key, pinned to the ~1 km discovery cell. Omitting them
/// yields the *provisional* key — byte-identical to what this function has always returned, which
/// is what lets every stored key, preference and block survive this change untouched and lets any
/// call site that has no coordinates keep working without an edit. Promotion is one-way and
/// happens on real evidence: see `MerchantPatronageStore.promote(from:to:)`.
///
/// The cell comes from `cellKey`, the discovery grid's own quantizer, rather than a second one.
/// One spatial vocabulary; and it is quantized rather than exact precisely so that the coordinate
/// drift which broke `syntheticId` cannot break this too.
public func merchantActivityKey(name: String, locationIdentifier: String?,
                                latitude: Double? = nil, longitude: Double? = nil) -> String? {
    if let chain = MerchantRecognizer.recognise(name)?.id { return chain }
    guard let provisional = provisionalLocalMerchantKey(name: name,
                                                        locationIdentifier: locationIdentifier)
    else { return nil }
    guard let token = merchantCellToken(latitude: latitude, longitude: longitude) else {
        return provisional
    }
    return provisional + String(localMerchantCellSeparator) + token
}

/// The name-only form of a local key: what `merchantActivityKey` returned before it could be
/// given coordinates, and still returns when it is not.
private func provisionalLocalMerchantKey(name: String, locationIdentifier: String?) -> String? {
    let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let normalized = folded.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .joined()
    if !normalized.isEmpty { return localMerchantKeyPrefix + normalized }
    guard let locationIdentifier, !locationIdentifier.isEmpty else { return nil }
    return localMerchantKeyPrefix + locationIdentifier
}

private func merchantCellToken(latitude: Double?, longitude: Double?) -> String? {
    guard let latitude, let longitude,
          latitude.isFinite, longitude.isFinite,
          (-90...90).contains(latitude), (-180...180).contains(longitude),
          latitude != 0 || longitude != 0 else { return nil }
    return cellKey(latitude: latitude, longitude: longitude)
}

/// Strips the place token from a qualified local key, giving the key the same merchant would have
/// had before its location was known. Nil for a chain key or an already-provisional one — there is
/// nothing weaker to fall back to.
public func provisionalMerchantKey(for merchantKey: String) -> String? {
    guard merchantKey.hasPrefix(localMerchantKeyPrefix),
          let separator = merchantKey.firstIndex(of: localMerchantCellSeparator) else { return nil }
    return String(merchantKey[..<separator])
}

/// A qualified key plus the eight keys it would have had in the surrounding cells.
///
/// A cell edge is an arbitrary line through the world, and a storefront can sit a few metres from
/// one; a pin revision that crosses it changes the key for a shop that did not move. Consent reads
/// widen to the neighbourhood so that cannot silently lift a block the owner set, at the cost of
/// also covering a namesake within about a kilometre — a trade taken deliberately and only here.
/// Counters do not widen: over-suppressing is a safe failure for a block, while over-counting is
/// not a safe failure for patronage.
func neighbouringMerchantKeys(for merchantKey: String) -> [String] {
    guard let provisional = provisionalMerchantKey(for: merchantKey),
          let separator = merchantKey.firstIndex(of: localMerchantCellSeparator) else { return [] }
    let token = merchantKey[merchantKey.index(after: separator)...]
    let parts = token.split(separator: "_", omittingEmptySubsequences: false)
    guard parts.count == 2, let latIndex = Int(parts[0]), let lonIndex = Int(parts[1]) else {
        return []
    }
    var keys: [String] = []
    for dLat in -1...1 {
        for dLon in -1...1 where !(dLat == 0 && dLon == 0) {
            keys.append(provisional + String(localMerchantCellSeparator)
                + "\(latIndex + dLat)_\(lonIndex + dLon)")
        }
    }
    return keys
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

    /// Every day this merchant was paid at, including days recorded before its location was
    /// known.
    ///
    /// The union is what makes location-qualifying the local keyspace free of a migration. A shop
    /// the owner has visited for months holds its days under the provisional `local:momskitchen`
    /// key; the first visit recorded with a fix opens `local:momskitchen#4365_-7938`, and without
    /// this union that shop would appear to have been discovered today.
    ///
    /// Reading rather than moving is deliberate. The provisional key is exactly the one that
    /// pooled namesakes together, so a promotion that emptied it would take a different shop's
    /// history with it. Read-time union carries the old days forward for everyone who was pooled,
    /// splits every new day correctly, and needs no write path at all — and because patronage is
    /// pruned to its window on every write, the pooled tail ages out on its own.
    public func visitDayKeys(for merchantKey: String) -> Set<String> {
        let all = load()
        return Self.unionedDays(for: merchantKey, in: all)
    }

    private static func unionedDays(for merchantKey: String,
                                    in all: [String: Set<String>]) -> Set<String> {
        let own = all[merchantKey] ?? []
        guard let provisional = provisionalMerchantKey(for: merchantKey),
              let inherited = all[provisional] else { return own }
        return own.union(inherited)
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
        let all = load()
        return Set(all.keys.filter { key in
            !blocked.contains(key)
                && CardCopilotStore.isFrequented(visitDayKeys: Self.unionedDays(for: key, in: all),
                                                 asOf: date, calendar: calendar)
        })
    }

    /// Drops one merchant's visit history.
    ///
    /// Takes the provisional ancestor with it. Since `visitDayKeys` unions that key in, leaving it
    /// behind would mean a delete the owner asked for did not happen — the merchant would still
    /// report every day it had accrued before its location was known. The cost is that a namesake
    /// which was pooled under the same provisional key loses those shared days too; they were
    /// never attributable to it in the first place, and a delete that silently does nothing is the
    /// worse of the two failures.
    public func forget(merchantKey: String) {
        var all = load()
        all.removeValue(forKey: merchantKey)
        var names = loadDisplayNames()
        names.removeValue(forKey: merchantKey)
        if let provisional = provisionalMerchantKey(for: merchantKey) {
            all.removeValue(forKey: provisional)
            names.removeValue(forKey: provisional)
        }
        save(all)
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

    /// Whether the owner has said "never learn this place".
    ///
    /// Widened past exact equality on purpose. A block is stored against the key the merchant had
    /// when the owner set it, and a cell edge is an arbitrary line: a pin revision that crosses one
    /// changes the key for a shop that did not move, and a block that silently lifts is a broken
    /// promise rather than a stale counter. So this also answers yes for the provisional ancestor
    /// and for the eight surrounding cells.
    ///
    /// Only this read widens. `recordVisit` and `frequentedKeys` stay exact, because the safe
    /// failure for a block is suppressing one shop too many and the safe failure for patronage is
    /// counting one visit too few.
    public func isBlocked(merchantKey: String) -> Bool {
        let blocked = loadBlocked()
        if blocked.contains(merchantKey) { return true }
        if let provisional = provisionalMerchantKey(for: merchantKey),
           blocked.contains(provisional) { return true }
        return neighbouringMerchantKeys(for: merchantKey).contains { blocked.contains($0) }
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

    /// One row per merchant the owner would recognise.
    ///
    /// A provisional key whose days are already being shown by a qualified sibling is folded away
    /// rather than listed. `visitDayKeys` unions those days into every real location, so listing
    /// the provisional row as well would show the same history twice under two headings — one of
    /// which names a place rather than a shop.
    public func learnedMerchants(asOf date: Date = Date(), calendar: Calendar = .current) -> [LearnedMerchant] {
        let names = loadDisplayNames()
        let all = load()
        let supersededProvisionals = Set(all.keys.compactMap(provisionalMerchantKey(for:)))
        return all.compactMap { key, _ in
            guard !supersededProvisionals.contains(key) else { return nil }
            let days = Self.unionedDays(for: key, in: all)
            let live = patronageDaysWithinWindow(days, asOf: date, calendar: calendar)
            guard let earliest = live.min(), let latest = live.max() else { return nil }
            // The provisional ancestor is consulted before the raw key, so a shop whose only
            // labelled visit predates its location still shows its name rather than
            // "local:momskitchen#4365_-7938".
            let displayName = names[key]
                ?? CanadianMerchantPreIndex.all.first { $0.id == key }?.name
                ?? provisionalMerchantKey(for: key).flatMap { names[$0] }
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
