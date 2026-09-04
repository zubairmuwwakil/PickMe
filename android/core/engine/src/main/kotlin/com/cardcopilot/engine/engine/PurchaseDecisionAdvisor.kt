package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.BenefitFamily
import com.cardcopilot.engine.models.BenefitKind
import com.cardcopilot.engine.models.BenefitVerification
import com.cardcopilot.engine.models.BenefitsCatalogue
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation

enum class PurchaseDecisionVerdict {
    REWARD_LEADER,
    REWARD_PROTECTION_ALIGNED,
    REWARD_PROTECTION_TRADEOFF,
    PROTECTION_TRADEOFF_UNRESOLVED,
    PURCHASE_CONTEXT_NEEDED
}

data class PurchaseDecisionAssessment(
    val verdict: PurchaseDecisionVerdict,
    val rewardCardId: String,
    val protectionLeaderCardId: String? = null,
    val relevantKinds: List<BenefitKind> = emptyList(),
    val policyVersion: String = PurchaseDecisionAdvisor.POLICY_VERSION
)

/**
 * Final checkout policy. Reward economics remain owned by RecommendationEngine; this layer keeps
 * verified protection facts as a separate decision attribute instead of inventing a CAD value for
 * insurance. Policy versioning lets a future evidence-backed model replace this without changing
 * issuer contract facts.
 */
object PurchaseDecisionAdvisor {
    const val POLICY_VERSION = "conservative-multi-attribute-v1"

    private val shoppingKinds = setOf(
        BenefitKind.PURCHASE_PROTECTION,
        BenefitKind.EXTENDED_WARRANTY,
        BenefitKind.MOBILE_DEVICE_INSURANCE
    )

    fun assess(
        rewardRecommendation: Recommendation,
        purchase: PurchaseContext,
        wallet: List<String>,
        benefits: BenefitsCatalogue,
        declaredContext: BenefitContext? = null
    ): PurchaseDecisionAssessment {
        val rewardCardId = rewardRecommendation.winner.cardId

        if (declaredContext != null) {
            val comparison = BenefitsAdvisor.comparison(declaredContext, wallet, benefits)
            val kinds = comparison.relevantKinds
            if (comparison.columns.isEmpty()) {
                return PurchaseDecisionAssessment(
                    PurchaseDecisionVerdict.REWARD_LEADER,
                    rewardCardId,
                    relevantKinds = kinds
                )
            }

            comparison.dominantCardId?.let { leader ->
                return PurchaseDecisionAssessment(
                    verdict = if (leader == rewardCardId) {
                        PurchaseDecisionVerdict.REWARD_PROTECTION_ALIGNED
                    } else {
                        PurchaseDecisionVerdict.REWARD_PROTECTION_TRADEOFF
                    },
                    rewardCardId = rewardCardId,
                    protectionLeaderCardId = leader,
                    relevantKinds = kinds
                )
            }

            if (comparison.columns.size == 1) {
                val only = comparison.columns.first().cardId
                return PurchaseDecisionAssessment(
                    verdict = if (only == rewardCardId) {
                        PurchaseDecisionVerdict.REWARD_PROTECTION_ALIGNED
                    } else {
                        PurchaseDecisionVerdict.REWARD_PROTECTION_TRADEOFF
                    },
                    rewardCardId = rewardCardId,
                    protectionLeaderCardId = only,
                    relevantKinds = kinds
                )
            }

            return PurchaseDecisionAssessment(
                PurchaseDecisionVerdict.PROTECTION_TRADEOFF_UNRESOLVED,
                rewardCardId,
                relevantKinds = kinds
            )
        }

        if (purchase.amountCad < benefits.triggers.bigTicketThresholdCad) {
            return PurchaseDecisionAssessment(PurchaseDecisionVerdict.REWARD_LEADER, rewardCardId)
        }

        val walletHasTrustedShoppingProtection = wallet.any { cardId ->
            val card = benefits.card(cardId) ?: return@any false
            if (card.certificate.verificationStatus == BenefitVerification.STUB) return@any false
            card.benefits.any { benefit ->
                benefit.knownFamily == BenefitFamily.SHOPPING &&
                    benefit.knownKind?.let { shoppingKinds.contains(it) } == true
            }
        }

        if (!walletHasTrustedShoppingProtection) {
            return PurchaseDecisionAssessment(PurchaseDecisionVerdict.REWARD_LEADER, rewardCardId)
        }

        return PurchaseDecisionAssessment(
            verdict = PurchaseDecisionVerdict.PURCHASE_CONTEXT_NEEDED,
            rewardCardId = rewardCardId,
            relevantKinds = listOf(
                BenefitKind.PURCHASE_PROTECTION,
                BenefitKind.EXTENDED_WARRANTY,
                BenefitKind.MOBILE_DEVICE_INSURANCE
            )
        )
    }
}
