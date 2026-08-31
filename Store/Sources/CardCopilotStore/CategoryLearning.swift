import Foundation
import CardCopilotEngine

/// A reversible suggestion for a row currently classified as `other`.
public struct CategoryRecoverySuggestion: Equatable, Sendable {
    public enum Basis: String, Sendable {
        case preservedRawCategory
        case repeatedMerchantConfirmation
        case observedMerchantCategoryCode
        case insufficientEvidence
    }

    public let purchaseID: UUID
    public let suggestedCategory: String?
    public let confidenceScore: Double
    public let basis: Basis
    public let explanation: String

    public var isSafeToApply: Bool {
        suggestedCategory != nil && confidenceScore >= 0.85
    }
}

public struct OtherCategoryAuditReport: Equatable, Sendable {
    public let suggestions: [CategoryRecoverySuggestion]

    public var safelyRecoverable: [CategoryRecoverySuggestion] {
        suggestions.filter(\.isSafeToApply)
    }

    public var ambiguous: [CategoryRecoverySuggestion] {
        suggestions.filter { !$0.isSafeToApply }
    }
}

/// Read-only by default. It reports why a row can or cannot be recovered; applying a suggestion
/// is a separate explicit call that uses `PredictionLog`, preserving the correction trail.
public enum OtherCategoryAuditor {
    public static func audit(purchases: [StoredPurchase], merchants: [StoredMerchant])
        -> OtherCategoryAuditReport {
        OtherCategoryAuditReport(suggestions: purchases.compactMap {
            suggestion(for: $0, merchants: merchants)
        })
    }

    public static func suggestion(for purchase: StoredPurchase,
                                  merchants: [StoredMerchant]) -> CategoryRecoverySuggestion? {
        let current = purchase.observation?.observedCategory
            ?? purchase.categoryAtPurchase
            ?? purchase.prediction?.predictedCategory
        guard current == "other" else { return nil }

        if let raw = purchase.rawCategoryAtPurchase,
           let category = CategoryTaxonomy.canonicalPurchaseID(raw), category != "other" {
            return .init(purchaseID: purchase.id, suggestedCategory: category,
                         confidenceScore: 1, basis: .preservedRawCategory,
                         explanation: "The original pre-normalization category is still present.")
        }

        if let identifier = purchase.merchantIdentifier,
           let merchant = merchants.first(where: { $0.identifier == identifier }),
           let category = merchant.confirmedCategory, category != "other",
           merchant.confirmationCount >= 2 {
            return .init(purchaseID: purchase.id, suggestedCategory: category,
                         confidenceScore: merchant.categoryConfidenceScore
                            ?? ConfidenceSource.repeatedTerminal.defaultScore,
                         basis: .repeatedMerchantConfirmation,
                         explanation: "The same terminal has repeated owner-confirmed evidence.")
        }

        if let mcc = purchase.merchantCategoryCode,
           let category = observedMCCCategory(mcc), category != "other" {
            return .init(purchaseID: purchase.id, suggestedCategory: category,
                         confidenceScore: ConfidenceSource.observedMcc.defaultScore,
                         basis: .observedMerchantCategoryCode,
                         explanation: "The preserved MCC has one high-confidence category mapping.")
        }

        return .init(purchaseID: purchase.id, suggestedCategory: nil, confidenceScore: 0,
                     basis: .insufficientEvidence,
                     explanation: "No preserved raw value, repeated terminal evidence, or decisive MCC exists.")
    }

    public static func apply(_ suggestion: CategoryRecoverySuggestion,
                             to purchase: StoredPurchase, using log: PredictionLog,
                             correctedAt: Date = Date()) throws {
        guard suggestion.purchaseID == purchase.id,
              suggestion.isSafeToApply,
              let category = suggestion.suggestedCategory else { return }
        try log.updateCategory(for: purchase, to: category, correctedAt: correctedAt)
    }
}

/// Aggregate learning is deliberately disabled by default. This store is only a consent gate;
/// PickMe has no uploader. A future hub integration can request a de-identified signal only after
/// the owner opts in, and never receives merchant name, location, amount, or purchase time.
public struct CategoryLearningConsentStore {
    private let defaults: UserDefaults
    private let key = "categoryLearning.aggregateContributionEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var aggregateContributionEnabled: Bool {
        get { defaults.bool(forKey: key) }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}

public struct AggregateCategorySignal: Equatable, Sendable, Codable {
    public let taxonomyVersion: String
    public let category: String
    public let merchantCategoryCode: Int?
    public let merchantGroupID: String?
    public let confirmationCount: Int
}

public enum AggregateCategorySignalError: Error, Equatable {
    case consentRequired
    case repeatedConfirmationRequired
}

public enum AggregateCategorySignalBuilder {
    public static func build(from merchant: StoredMerchant,
                             consent: CategoryLearningConsentStore) throws
        -> AggregateCategorySignal {
        guard consent.aggregateContributionEnabled else {
            throw AggregateCategorySignalError.consentRequired
        }
        guard let category = merchant.confirmedCategory,
              merchant.confirmationCount >= 2 else {
            throw AggregateCategorySignalError.repeatedConfirmationRequired
        }
        return AggregateCategorySignal(
            taxonomyVersion: merchant.categoryTaxonomyVersion ?? CategoryTaxonomy.taxonomyVersion,
            category: category,
            merchantCategoryCode: merchant.merchantCategoryCode,
            merchantGroupID: merchant.merchantGroupID,
            confirmationCount: merchant.confirmationCount)
    }
}
