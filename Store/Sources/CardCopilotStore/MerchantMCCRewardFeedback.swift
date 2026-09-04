import Foundation
import CardCopilotEngine

/// A statement-level reward outcome that is useful as MCC evidence without pretending the owner
/// saw the literal processor code. Each option carries every common MCC compatible with the claim,
/// and the learning store splits one weak vote across them.
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

/// Bridge between the statement-reconcile UX and the runtime MCC posterior.
///
/// This is deliberately narrower than PickMe's full purchase taxonomy. Categories such as
/// recurring bills, streaming, delivery, and retailer families are often identified by issuer
/// rules or transaction flags in addition to MCC, so a reward outcome there is not clean MCC
/// evidence. These options are the high-signal cases where the category maps to a bounded MCC set.
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

    /// Category projection used only for learned/derived graph evidence. This is intentionally
    /// broader than `observedMCCCategory`: an owner saying "my issuer treated this as grocery"
    /// does not establish which grocery MCC was used, but every candidate still projects to the
    /// same scoreable grocery category.
    public static func inferredCategory(for mcc: Int) -> String? {
        if let exact = observedMCCCategory(mcc) { return exact }
        return options.first { $0.candidateMCCs.contains(mcc) }?.category
    }

    public static func fingerprint(for purchase: StoredPurchase) -> String {
        "purchase:\(purchase.id.uuidString):rewardOutcome"
    }

    /// Ask only when the merchant belongs to the 500-row seed, a real observed MCC has not already
    /// settled the question, this purchase has not answered it before, and the graph itself has
    /// not already reached the strong-learned state.
    public static func shouldPrompt(for purchase: StoredPurchase,
                                    learningStore: MerchantMCCLearningStore = .shared) -> Bool {
        guard purchase.categoryConfidenceRaw != ConfidenceSource.observedMcc.rawValue,
              learningStore.seedMerchant(matching: purchase.displayMerchant) != nil else { return false }

        let fingerprint = fingerprint(for: purchase)
        guard !learningStore.hasRewardOutcome(merchantName: purchase.displayMerchant,
                                              sourceFingerprint: fingerprint) else { return false }

        let posterior = learningStore.posterior(
            merchantName: purchase.displayMerchant,
            locationKey: locationKey(for: purchase))
        return posterior?.state != .strongLearned
    }

    /// Records one statement-level category outcome. Returns zero when the selected category is
    /// not safe MCC evidence or the merchant is outside the seed graph.
    @discardableResult
    public static func record(category: String,
                              for purchase: StoredPurchase,
                              learningStore: MerchantMCCLearningStore = .shared,
                              observedAt: Date = Date()) -> Int {
        guard let option = option(for: category) else { return 0 }
        return learningStore.recordRewardOutcome(
            merchantName: purchase.displayMerchant,
            candidateMCCs: option.candidateMCCs,
            locationKey: locationKey(for: purchase),
            sourceFingerprint: fingerprint(for: purchase),
            observedAt: observedAt)
    }

    private static func locationKey(for purchase: StoredPurchase) -> String? {
        guard let latitude = purchase.merchantLatitude,
              let longitude = purchase.merchantLongitude,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              latitude != 0 || longitude != 0 else { return nil }
        let merchant = NearbyPlace(
            id: purchase.merchantIdentifier ?? purchase.id.uuidString,
            name: purchase.displayMerchant,
            poiCategoryRaw: nil,
            latitude: latitude,
            longitude: longitude,
            distanceMeters: nil)
        return MerchantMCCLearningStore.locationKey(for: merchant)
    }
}
