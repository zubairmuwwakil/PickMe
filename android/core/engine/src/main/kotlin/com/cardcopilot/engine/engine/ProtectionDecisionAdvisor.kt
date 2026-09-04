package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.BenefitFamily
import com.cardcopilot.engine.models.BenefitKind
import com.cardcopilot.engine.models.BenefitVerification
import com.cardcopilot.engine.models.BenefitsCatalogue
import com.cardcopilot.engine.models.PurchaseContext

enum class ProtectionDecisionStatus {
    NOT_RELEVANT,
    PURCHASE_CONTEXT_NEEDED,
    POTENTIAL_TRADEOFF
}

data class ProtectionDecisionAssessment(
    val status: ProtectionDecisionStatus,
    val directCardId: String,
    val relevantKinds: List<BenefitKind> = emptyList(),
    val verification: BenefitVerification? = null
)

object ProtectionDecisionAdvisor {
    private val shoppingKinds = listOf(
        BenefitKind.PURCHASE_PROTECTION,
        BenefitKind.EXTENDED_WARRANTY,
        BenefitKind.MOBILE_DEVICE_INSURANCE
    )

    fun alternateFundingAssessment(
        directCardId: String,
        purchase: PurchaseContext,
        benefits: BenefitsCatalogue,
        declaredContext: BenefitContext? = null
    ): ProtectionDecisionAssessment {
        val card = benefits.card(directCardId)
            ?: return ProtectionDecisionAssessment(ProtectionDecisionStatus.NOT_RELEVANT, directCardId)
        if (card.certificate.verificationStatus == BenefitVerification.STUB) {
            return ProtectionDecisionAssessment(ProtectionDecisionStatus.NOT_RELEVANT, directCardId)
        }

        val availableKinds = card.benefits.mapNotNull { benefit ->
            val family = benefit.knownFamily
            val kind = benefit.knownKind
            if (family == BenefitFamily.SHOPPING && kind != null && shoppingKinds.contains(kind)) kind else null
        }.toSet()

        if (availableKinds.isEmpty()) {
            return ProtectionDecisionAssessment(
                ProtectionDecisionStatus.NOT_RELEVANT,
                directCardId,
                verification = card.certificate.verificationStatus
            )
        }

        if (declaredContext != null) {
            val relevant = declaredContext.relevantKinds.filter { availableKinds.contains(it) }
            return ProtectionDecisionAssessment(
                if (relevant.isEmpty()) ProtectionDecisionStatus.NOT_RELEVANT
                else ProtectionDecisionStatus.POTENTIAL_TRADEOFF,
                directCardId,
                relevant,
                card.certificate.verificationStatus
            )
        }

        if (purchase.amountCad < benefits.triggers.bigTicketThresholdCad) {
            return ProtectionDecisionAssessment(
                ProtectionDecisionStatus.NOT_RELEVANT,
                directCardId,
                verification = card.certificate.verificationStatus
            )
        }

        if (benefits.triggers.consumableCategories.contains(purchase.category)) {
            return ProtectionDecisionAssessment(
                ProtectionDecisionStatus.PURCHASE_CONTEXT_NEEDED,
                directCardId,
                shoppingKinds.filter { availableKinds.contains(it) },
                card.certificate.verificationStatus
            )
        }

        val conservativelyRelevant = listOf(
            BenefitKind.PURCHASE_PROTECTION,
            BenefitKind.EXTENDED_WARRANTY
        ).filter { availableKinds.contains(it) }

        if (conservativelyRelevant.isEmpty()) {
            return ProtectionDecisionAssessment(
                ProtectionDecisionStatus.PURCHASE_CONTEXT_NEEDED,
                directCardId,
                shoppingKinds.filter { availableKinds.contains(it) },
                card.certificate.verificationStatus
            )
        }

        return ProtectionDecisionAssessment(
            ProtectionDecisionStatus.POTENTIAL_TRADEOFF,
            directCardId,
            conservativelyRelevant,
            card.certificate.verificationStatus
        )
    }
}
