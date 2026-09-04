import Foundation

/// Returns recent, explicit owner MCC observations eligible for anonymous community upload.
/// Category-only feedback, reward inference, purchases without a physical fix, and unrecognised
/// merchants are excluded by `CommunityMerchantMCCWire.report`.
public func communityMerchantMCCReports(
    from purchases: [StoredPurchase],
    now: Date = Date(),
    maximumAgeDays: Int = 30,
    limit: Int = 20
) -> [CommunityMerchantMCCReport] {
    let cutoff = now.addingTimeInterval(-Double(max(0, maximumAgeDays)) * 86_400)
    var seen = Set<UUID>()
    return purchases
        .compactMap { CommunityMerchantMCCWire.report(from: $0, network: nil) }
        .filter { $0.observedAt >= cutoff && $0.observedAt <= now.addingTimeInterval(600) }
        .sorted { $0.observedAt > $1.observedAt }
        .filter { seen.insert($0.observationID).inserted }
        .prefix(max(0, limit))
        .map { $0 }
}
