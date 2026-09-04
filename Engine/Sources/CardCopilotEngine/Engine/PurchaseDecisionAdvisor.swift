import Foundation

/// Final checkout decisions are intentionally multi-attribute. `RecommendationEngine` remains the
/// economic/reward authority; this layer decides whether verified protection facts agree with that
/// winner, conflict with it, or require purchase context before PickMe can make a stronger claim.
///
/// This is deliberately replaceable policy. A future evidence-backed utility model may supersede
/// it without changing reward contracts or benefit certificates.
public enum PurchaseDecisionVerdict: String, Equatable, Sendable {
    /// No material trusted protection evidence is currently relevant to the choice.
    case rewardLeader
    /// The user declared what they are buying and the unique protection leader is also the reward
    /// leader (or the reward leader is the only wallet card with relevant verified coverage).
    case rewardProtectionAligned
    /// Reward economics and protection evidence point at different cards.
    case rewardProtectionTradeoff
    /// The user declared the purchase type, but verified coverage has a genuine Pareto trade-off;
    /// there is no single protection winner to silently turn into a card ranking.
    case protectionTradeoffUnresolved
    /// The amount is material and the wallet contains relevant shopping protection, but merchant
    /// category is not enough to know the item being purchased.
    case purchaseContextNeeded
}

public struct PurchaseDecisionAssessment: Equatable, Sendable {
    public let verdict: PurchaseDecisionVerdict
    public let rewardCardId: String
    public let protectionLeaderCardId: String?
    public let relevantKinds: [BenefitKind]
    public let policyVersion: String

    public init(verdict: PurchaseDecisionVerdict,
                rewardCardId: String,
                protectionLeaderCardId: String? = nil,
                relevantKinds: [BenefitKind] = [],
                policyVersion: String = PurchaseDecisionAdvisor.policyVersion) {
        self.verdict = verdict
        self.rewardCardId = rewardCardId
        self.protectionLeaderCardId = protectionLeaderCardId
        self.relevantKinds = relevantKinds
        self.policyVersion = policyVersion
    }
}

public enum PurchaseDecisionAdvisor {
    /// Versioned independently from reward/card contracts so policy can evolve without pretending
    /// a policy change is a change to issuer facts.
    public static let policyVersion = "conservative-multi-attribute-v1"

    private static let shoppingKinds: Set<BenefitKind> = [
        .purchaseProtection,
        .extendedWarranty,
        .mobileDeviceInsurance,
    ]

    /// Combines the reward result with benefit facts without converting insurance limits to an
    /// invented dollar value. When purchase type is unknown, this returns `purchaseContextNeeded`
    /// rather than inferring an item from the merchant's MCC/category.
    public static func assess(
        rewardRecommendation: Recommendation,
        purchase: PurchaseContext,
        wallet: [String],
        benefits: BenefitsCatalogue,
        declaredContext: BenefitContext? = nil
    ) -> PurchaseDecisionAssessment {
        let rewardCardId = rewardRecommendation.winner.cardId

        if let declaredContext {
            let comparison = BenefitsAdvisor.comparison(
                context: declaredContext,
                wallet: wallet,
                catalogue: benefits)
            let kinds = comparison.relevantKinds

            guard !comparison.columns.isEmpty else {
                return PurchaseDecisionAssessment(verdict: .rewardLeader,
                                                  rewardCardId: rewardCardId,
                                                  relevantKinds: kinds)
            }

            if let leader = comparison.dominantCardId {
                return PurchaseDecisionAssessment(
                    verdict: leader == rewardCardId ? .rewardProtectionAligned : .rewardProtectionTradeoff,
                    rewardCardId: rewardCardId,
                    protectionLeaderCardId: leader,
                    relevantKinds: kinds)
            }

            // A single relevant-coverage column is effectively the only protection candidate even
            // when there are too few comparable numeric fields for the Pareto helper to name it.
            if comparison.columns.count == 1, let only = comparison.columns.first?.cardId {
                return PurchaseDecisionAssessment(
                    verdict: only == rewardCardId ? .rewardProtectionAligned : .rewardProtectionTradeoff,
                    rewardCardId: rewardCardId,
                    protectionLeaderCardId: only,
                    relevantKinds: kinds)
            }

            return PurchaseDecisionAssessment(verdict: .protectionTradeoffUnresolved,
                                              rewardCardId: rewardCardId,
                                              relevantKinds: kinds)
        }

        guard purchase.amountCad >= benefits.triggers.bigTicketThresholdCad else {
            return PurchaseDecisionAssessment(verdict: .rewardLeader,
                                              rewardCardId: rewardCardId)
        }

        let walletHasTrustedShoppingProtection = wallet.contains { cardId in
            guard let card = benefits.card(cardId),
                  card.certificate.verificationStatus != .stub else { return false }
            return card.benefits.contains { benefit in
                benefit.knownFamily == .shopping
                    && benefit.knownKind.map { shoppingKinds.contains($0) } == true
            }
        }

        guard walletHasTrustedShoppingProtection else {
            return PurchaseDecisionAssessment(verdict: .rewardLeader,
                                              rewardCardId: rewardCardId)
        }

        return PurchaseDecisionAssessment(
            verdict: .purchaseContextNeeded,
            rewardCardId: rewardCardId,
            relevantKinds: [.purchaseProtection, .extendedWarranty, .mobileDeviceInsurance])
    }
}
