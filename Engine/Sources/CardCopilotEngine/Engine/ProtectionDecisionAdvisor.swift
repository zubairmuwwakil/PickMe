import Foundation

/// Protection is a separate decision attribute from earn value. We intentionally do not convert
/// insurance limits into a fabricated CAD expected value: PickMe has coverage facts, but not a
/// defensible probability-of-loss model or the owner's risk utility. The final decision layer can
/// therefore identify a trade-off without contaminating `RecommendationEngine`'s reward score.
public enum ProtectionDecisionStatus: String, Equatable, Sendable {
    /// The alternate funding path does not appear to threaten a relevant, trusted card benefit.
    case notRelevant
    /// The purchase amount is material and the direct card has shopping protection, but the
    /// merchant category cannot tell us what item is being bought. The buyer must supply context.
    case purchaseContextNeeded
    /// A declared or conservatively inferred durable purchase has card-linked protection that an
    /// alternate funding path may sever. This is a trade-off, not a negative dollar score.
    case potentialTradeoff
}

public struct ProtectionDecisionAssessment: Equatable, Sendable {
    public let status: ProtectionDecisionStatus
    public let directCardId: String
    public let relevantKinds: [BenefitKind]
    public let verification: BenefitVerification?

    public init(status: ProtectionDecisionStatus,
                directCardId: String,
                relevantKinds: [BenefitKind] = [],
                verification: BenefitVerification? = nil) {
        self.status = status
        self.directCardId = directCardId
        self.relevantKinds = relevantKinds
        self.verification = verification
    }
}

public enum ProtectionDecisionAdvisor {
    private static let shoppingKinds: [BenefitKind] = [
        .purchaseProtection,
        .extendedWarranty,
        .mobileDeviceInsurance,
    ]

    /// Assesses whether replacing the destination-card charge with an alternate funding instrument
    /// creates a protection trade-off. Only non-stub benefit facts participate.
    ///
    /// Merchant category is deliberately not treated as purchase type. When the amount is material
    /// but the category is normally consumable, the honest answer is `purchaseContextNeeded` rather
    /// than assuming either that protection matters or that it does not.
    public static func alternateFundingAssessment(
        directCardId: String,
        purchase: PurchaseContext,
        benefits: BenefitsCatalogue,
        declaredContext: BenefitContext? = nil
    ) -> ProtectionDecisionAssessment {
        guard let card = benefits.card(directCardId),
              card.certificate.verificationStatus != .stub else {
            return ProtectionDecisionAssessment(status: .notRelevant,
                                                directCardId: directCardId)
        }

        let availableKinds = Set(card.benefits.compactMap { benefit -> BenefitKind? in
            guard benefit.knownFamily == .shopping,
                  let kind = benefit.knownKind,
                  shoppingKinds.contains(kind) else { return nil }
            return kind
        })
        guard !availableKinds.isEmpty else {
            return ProtectionDecisionAssessment(status: .notRelevant,
                                                directCardId: directCardId,
                                                verification: card.certificate.verificationStatus)
        }

        if let declaredContext {
            let relevant = declaredContext.relevantKinds.filter { availableKinds.contains($0) }
            return ProtectionDecisionAssessment(
                status: relevant.isEmpty ? .notRelevant : .potentialTradeoff,
                directCardId: directCardId,
                relevantKinds: relevant,
                verification: card.certificate.verificationStatus)
        }

        guard purchase.amountCad >= benefits.triggers.bigTicketThresholdCad else {
            return ProtectionDecisionAssessment(status: .notRelevant,
                                                directCardId: directCardId,
                                                verification: card.certificate.verificationStatus)
        }

        if benefits.triggers.consumableCategories.contains(purchase.category) {
            return ProtectionDecisionAssessment(
                status: .purchaseContextNeeded,
                directCardId: directCardId,
                relevantKinds: shoppingKinds.filter { availableKinds.contains($0) },
                verification: card.certificate.verificationStatus)
        }

        let conservativelyRelevant = [BenefitKind.purchaseProtection, .extendedWarranty]
            .filter { availableKinds.contains($0) }
        guard !conservativelyRelevant.isEmpty else {
            return ProtectionDecisionAssessment(
                status: .purchaseContextNeeded,
                directCardId: directCardId,
                relevantKinds: shoppingKinds.filter { availableKinds.contains($0) },
                verification: card.certificate.verificationStatus)
        }

        return ProtectionDecisionAssessment(status: .potentialTradeoff,
                                            directCardId: directCardId,
                                            relevantKinds: conservativelyRelevant,
                                            verification: card.certificate.verificationStatus)
    }
}
