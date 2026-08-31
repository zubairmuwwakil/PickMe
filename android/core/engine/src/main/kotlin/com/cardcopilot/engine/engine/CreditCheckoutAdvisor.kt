package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.CardCredit
import com.cardcopilot.engine.models.CreditRedemptionMethod
import com.cardcopilot.engine.models.Money
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.ReportingCurrency
import com.cardcopilot.engine.models.SourceType
import kotlinx.serialization.Serializable

@Serializable
data class CheckoutCreditMatch(
    val cardId: String,
    val creditId: String,
    val label: String,
    val valueCad: Double,
    val redemptionMethod: CreditRedemptionMethod
)

/** Fail-closed POS credit matching. Only one credit is counted until stacking is contractual. */
object CreditCheckoutAdvisor {
    fun bestMatch(card: CardProduct, purchase: PurchaseContext,
                  ownerState: OwnerState, asOf: String): CheckoutCreditMatch? {
        val cardState = ownerState.cardStates[card.cardId] ?: CardState()
        return bestMatch(card.cardId, card.credits ?: emptyList(), cardState, purchase, asOf)
    }

    fun bestMatch(cardId: String, credits: List<CardCredit>, cardState: CardState,
                  purchase: PurchaseContext, asOf: String): CheckoutCreditMatch? {
        val canonical = purchase.canonicalized()
        return credits.mapNotNull { credit ->
            if (credit.sourceType != SourceType.ISSUER_CONFIRMED) return@mapNotNull null
            val method = credit.redemptionMethod ?: return@mapNotNull null
            val predicate = credit.purchasePredicate ?: return@mapNotNull null
            if (!RuleMatcher.matches(predicate, canonical, cardState)) return@mapNotNull null
            val opportunity = CreditAdvisor.opportunity(cardId, credit, cardState, asOf)
                ?: return@mapNotNull null
            if (opportunity.status != CreditOpportunityStatus.AVAILABLE) return@mapNotNull null

            val purchaseCad = maxOf(0.0, canonical.amountCad)
            val minimumCad = credit.minimumTransaction?.let(ReportingCurrency::toReporting)
            if (minimumCad != null && purchaseCad + 0.000001 < minimumCad) return@mapNotNull null
            val remainingCad = ReportingCurrency.toReporting(
                Money(opportunity.remainingAmount, credit.value.currency)
            )
            val valueCad = if (credit.allowsPartialUse == true) {
                minOf(remainingCad, purchaseCad)
            } else {
                if (purchaseCad + 0.000001 < remainingCad) return@mapNotNull null
                remainingCad
            }
            if (valueCad <= 0.000001) return@mapNotNull null
            CheckoutCreditMatch(cardId, credit.creditId, credit.label, valueCad, method)
        }.maxWithOrNull(compareBy<CheckoutCreditMatch> { it.valueCad }.thenByDescending { it.creditId })
    }
}
