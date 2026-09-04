import Foundation
import CardCopilotEngine

/// A statement-level reward outcome that is useful as MCC evidence without pretending the owner
/// saw the literal processor code. Each option carries every common MCC compatible with the claim,
/// and the feedback store splits one weak vote across them.
public struct MerchantMCCRewardFeedbackOption: Identifiable, Equatable, Sendable {
    public let category: String
    public let candidateMCCs: [Int]

    public var id: String { category }
    public var displayName: String { categoryDisplayName(category) }

    public init(category: String, candidateMCCs: [Int]) {
        self.category = CategoryTaxonomy.canonicalID(category)
        self.candidateMCCs = candidateMCCs
    }
}

/// Bridge between statement reconciliation and the canonical Store-side MerchantMCCGraph.
///
/// This is deliberately narrower than PickMe's full purchase taxonomy. Categories such as
/// recurring bills, streaming, delivery, and retailer families can depend on issuer rules or
/// transaction flags in addition to MCC, so a reward outcome there is not clean MCC evidence.
public enum MerchantMCCRewardFeedback {
    public static let options: [MerchantMCCRewardFeedbackOption] = [
        .init(category: "grocery", candidateMCCs: [5411, 5422, 5441, 5451, 5462, 5499]),
        .init(category: "dining", candidateMCCs: [5812, 5814]),
        .init(category: "gasStation", candidateMCCs: [5541, 5542]),
        .init(category: "evCharging", candidateMCCs: [5552]),
        .init(category: "transit", candidateMCCs: [4111, 4121]),
        .init(category: "drugStore", candidateMCCs: [5912]),
        .init(category: "lodging", candidateMCCs: [7011]),
        .init(category: "carRental", candidateMCCs: [7512]),
    ]

    public static func option(for category: String) -> MerchantMCCRewardFeedbackOption? {
        let canonical = CategoryTaxonomy.canonicalID(category)
        return options.first { $0.category == canonical }
    }

    /// Broader than `observedMCCCategory` only for derived evidence. A reward outcome can tell us
    /// "grocery" while leaving several grocery MCCs possible; it never upgrades one to observed.
    public static func inferredCategory(for mcc: Int) -> String? {
        if let exact = observedMCCCategory(mcc) { return exact }
        return options.first { $0.candidateMCCs.contains(mcc) }?.category
    }

    public static func fingerprint(for purchase: StoredPurchase) -> String {
        "purchase:\(purchase.id.uuidString):rewardOutcome"
    }

    /// Ask only when the merchant belongs to the canonical 500-row seed, a literal observed MCC
    /// has not already settled the question, and this purchase has not contributed feedback yet.
    public static func shouldPrompt(for purchase: StoredPurchase,
                                    feedbackStore: MerchantMCCRewardFeedbackStore = .shared) -> Bool {
        guard purchase.categoryConfidenceRaw != ConfidenceSource.observedMcc.rawValue,
              MerchantMCCSeedCatalogue.match(merchantName: purchase.displayMerchant) != nil else {
            return false
        }
        return !feedbackStore.hasRewardOutcome(
            merchantName: purchase.displayMerchant,
            sourceFingerprint: fingerprint(for: purchase))
    }

    /// Records one statement-level category outcome. Returns zero when the selected category is
    /// not defensible MCC evidence or the merchant is outside the canonical seed graph.
    @discardableResult
    public static func record(category: String,
                              for purchase: StoredPurchase,
                              feedbackStore: MerchantMCCRewardFeedbackStore = .shared,
                              observedAt: Date = Date()) -> Int {
        guard let option = option(for: category) else { return 0 }
        return feedbackStore.recordRewardOutcome(
            merchantName: purchase.displayMerchant,
            candidateMCCs: option.candidateMCCs,
            latitude: purchase.merchantLatitude,
            longitude: purchase.merchantLongitude,
            sourceFingerprint: fingerprint(for: purchase),
            observedAt: observedAt)
    }
}
