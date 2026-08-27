package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.engine.models.ValuationDirection
import com.cardcopilot.engine.models.Warning
import java.util.Locale

data class Explanation(
    val headline: String,
    val why: String,
    val runnerUpLine: String?,
    val valuationLine: String?,
    val warningLines: List<String>
)

class RecommendationExplainer(catalogue: Catalogue) {
    private val namesById: Map<String, String> = catalogue.cards.associate { it.cardId to it.officialName }

    fun explain(recommendation: Recommendation, purchase: PurchaseContext): Explanation {
        val name = displayName(recommendation.winner.cardId)
        val verb = if (recommendation.switchedFromDefault || recommendation.defaultNotAccepted) "Use" else "Stay on"
        val headline = "$verb $name — about ${money(recommendation.winner.netValueCad)} back on this ${money(purchase.amountCad)} purchase."

        val why = if (recommendation.winner.appliedRuleId != null) {
            val fxClause = if (recommendation.winner.fxCostCad > 0) {
                " minus ${money(recommendation.winner.fxCostCad)} foreign-transaction fee."
            } else {
                "."
            }
            "Applied rule ${recommendation.winner.appliedRuleId}: ${money(recommendation.winner.grossRewardCad)} in rewards$fxClause"
        } else {
            "No earn rule applied."
        }

        var runnerUpLine: String? = null
        if (recommendation.suppressedBetterCard != null) {
            val delta = recommendation.suppressedBetterCard.netValueCad - recommendation.winner.netValueCad
            runnerUpLine = "${displayName(recommendation.suppressedBetterCard.cardId)} is marginally better (+${money(delta)}) — not worth the wallet dig."
        } else if (recommendation.runnerUp != null) {
            val delta = recommendation.winner.netValueCad - recommendation.runnerUp.netValueCad
            runnerUpLine = "Next best: ${displayName(recommendation.runnerUp.cardId)} (${money(recommendation.runnerUp.netValueCad)}) — you'd give up ${money(delta)}."
        }

        var valuationLine: String? = null
        if (recommendation.valuationSensitive &&
            recommendation.declaredCentsPerPoint != null &&
            recommendation.breakevenCentsPerPoint != null &&
            recommendation.alternateWinnerCardId != null &&
            recommendation.valuationDirection != null
        ) {
            val side = if (recommendation.valuationDirection == ValuationDirection.BELOW) "Below" else "Above"
            valuationLine = "Assumes your points are worth ${cents(recommendation.declaredCentsPerPoint)} each. " +
                "$side about ${cents(recommendation.breakevenCentsPerPoint)}, ${displayName(recommendation.alternateWinnerCardId)} wins instead."
        }

        return Explanation(
            headline = headline,
            why = why,
            runnerUpLine = runnerUpLine,
            valuationLine = valuationLine,
            warningLines = recommendation.winner.warnings.map { lineFor(it) }
        )
    }

    private fun lineFor(warning: Warning): String {
        return when (warning) {
            Warning.DRAWER_CARD -> "This card is in your drawer — bring it or take the runner-up."
            Warning.CAP_NEARLY_EXHAUSTED -> "Category cap nearly used up — the winner may flip soon."
            Warning.NEGATIVE_NET_VALUE -> "This card would LOSE money here after fees."
            Warning.NETWORK_NOT_ACCEPTED -> "Card network not accepted at this merchant."
            Warning.UNRESOLVED_OWNER_STATE -> "Card skipped — account state not set up yet."
            Warning.FX_ALLOWANCE_ASSUMED -> "Assumed within this card's monthly FX-free allowance."
            Warning.HYPOTHETICAL_SELECTION -> "Assumes this is one of your selected 2% categories — check your selections."
            Warning.UNSUPPORTED_PROGRAM -> "Card skipped — you haven't set what this card's rewards are worth."
            // Reachable on a card that WON: the excluded case never reaches an explanation, because
            // an excluded card is never the winner. Worded for the case the owner can actually see.
            Warning.UNSUPPORTED_CAPABILITY ->
                "This card has a better rule here that this app can't check yet — it may be worth more than shown."
            Warning.PRODUCT_WITHDRAWN ->
                "This card has been discontinued and is no longer recommended."
            // Never reachable on a winner: a draft card is excluded before scoring, so this
            // warning never travels with a Recommendation. Listed for exhaustiveness only.
            Warning.DRAFT_PRODUCT ->
                "This card is a research-grade catalogue entry and should not have been scorable."
        }
    }

    private fun displayName(cardId: String): String = namesById[cardId] ?: cardId
    private fun money(value: Double): String = String.format(Locale.US, "$%.2f", value)
    private fun cents(value: Double): String = String.format(Locale.US, "%.2f¢", value)
}
