package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.CardCredit
import com.cardcopilot.engine.models.CreditState
import com.cardcopilot.engine.models.Money
import com.cardcopilot.engine.models.ReportingCurrency
import com.cardcopilot.engine.models.SourceType
import java.time.LocalDate

data class CreditPortfolioRecovery(
    val realizedCad: Double,
    val unspentPotentialCad: Double
)

object CreditPortfolioRecoveryCalculator {
    fun recovery(card: CardProduct, cardState: CardState,
                 asOf: String): CreditPortfolioRecovery =
        recovery(card.cardId, card.credits ?: emptyList(), cardState, asOf)

    fun recovery(cardId: String, credits: List<CardCredit>, cardState: CardState,
                 asOf: String): CreditPortfolioRecovery {
        val asOfDate = LocalDate.parse(asOf)
        val trailingStart = asOfDate.minusMonths(12)
        var realized = 0.0
        var potential = 0.0

        for (credit in credits.filter { it.sourceType == SourceType.ISSUER_CONFIRMED }) {
            val state = cardState.creditStates?.get(credit.creditId) ?: CreditState()
            val posted = state.windows.values.filter { it.realizedAmount > 0.0 }
            val months = credit.effectiveSchedule?.intervalMonths
            if (months != null && months > 12) {
                val cycleStart = asOfDate.minusMonths(months.toLong())
                val recent = posted.filter {
                    val updated = LocalDate.parse(it.updatedAt)
                    !updated.isBefore(cycleStart) && !updated.isAfter(asOfDate)
                }.maxByOrNull { it.updatedAt }
                if (recent != null) {
                    realized += ReportingCurrency.toReporting(Money(
                        recent.realizedAmount * 12.0 / months.toDouble(), credit.value.currency
                    ))
                }
            } else {
                realized += posted.filter {
                    val updated = LocalDate.parse(it.updatedAt)
                    !updated.isBefore(trailingStart) && !updated.isAfter(asOfDate)
                }.sumOf {
                    ReportingCurrency.toReporting(Money(it.realizedAmount, credit.value.currency))
                }
            }

            val opportunity = CreditAdvisor.opportunity(cardId, credit, cardState, asOf)
            if (opportunity != null && (opportunity.status == CreditOpportunityStatus.AVAILABLE ||
                    opportunity.status == CreditOpportunityStatus.NEEDS_ENROLLMENT)) {
                potential += ReportingCurrency.toReporting(
                    Money(opportunity.remainingAmount, credit.value.currency)
                )
            }
        }
        return CreditPortfolioRecovery(realized, potential)
    }
}
