import Foundation

/// Retry-safe local queue for anonymous community MCC uploads. It stores only the same privacy-
/// minimal fields the wire accepts and exists only while the owner has sharing enabled.
public final class CommunityMerchantMCCPendingStore: @unchecked Sendable {
    public static let shared = CommunityMerchantMCCPendingStore()

    private struct Pending: Codable {
        let observationID: UUID
        let merchantID: String
        let latitude: Double
        let longitude: Double
        let mcc: Int
        let observedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private var rows: [Pending]

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.ca.inunity.pickme") ?? .standard,
                key: String = "pickme.communityMerchantMCC.pending.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Pending].self, from: data) {
            rows = decoded
        } else {
            rows = []
        }
    }

    @discardableResult
    public func enqueue(purchase: StoredPurchase) -> Bool {
        guard CommunityMerchantMCCSettingsStore().isEnabled,
              let report = CommunityMerchantMCCWire.report(from: purchase, network: nil)
        else { return false }
        lock.lock(); defer { lock.unlock() }
        guard !rows.contains(where: { $0.observationID == report.observationID }) else { return false }
        rows.append(Pending(observationID: report.observationID,
                            merchantID: report.merchantID,
                            latitude: report.latitude,
                            longitude: report.longitude,
                            mcc: report.mcc,
                            observedAt: report.observedAt))
        rows.sort { $0.observedAt > $1.observedAt }
        if rows.count > 100 { rows.removeLast(rows.count - 100) }
        persistLocked()
        return true
    }

    public func reports(now: Date = Date(), maximumAgeDays: Int = 30,
                        limit: Int = 20) -> [CommunityMerchantMCCReport] {
        guard CommunityMerchantMCCSettingsStore().isEnabled else { return [] }
        let cutoff = now.addingTimeInterval(-Double(max(0, maximumAgeDays)) * 86_400)
        lock.lock(); defer { lock.unlock() }
        return rows.filter { $0.observedAt >= cutoff && $0.observedAt <= now.addingTimeInterval(600) }
            .prefix(max(0, limit))
            .map { row in
                CommunityMerchantMCCReport(observationID: row.observationID,
                                           merchantID: row.merchantID,
                                           latitude: row.latitude,
                                           longitude: row.longitude,
                                           network: nil,
                                           mcc: row.mcc,
                                           observedAt: row.observedAt)
            }
    }

    public func markSubmitted(_ observationID: UUID) {
        lock.lock(); defer { lock.unlock() }
        let before = rows.count
        rows.removeAll { $0.observationID == observationID }
        if rows.count != before { persistLocked() }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        rows.removeAll()
        defaults.removeObject(forKey: key)
    }

    private func persistLocked() {
        guard !rows.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(rows) { defaults.set(data, forKey: key) }
    }
}
