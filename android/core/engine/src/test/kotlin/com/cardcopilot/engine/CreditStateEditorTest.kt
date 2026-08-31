package com.cardcopilot.engine

import com.cardcopilot.engine.engine.CreditAdvisor
import com.cardcopilot.engine.engine.CreditOpportunityStatus
import com.cardcopilot.engine.engine.CreditStateAction
import com.cardcopilot.engine.engine.CreditStateEditor
import com.cardcopilot.engine.engine.CreditPortfolioRecoveryCalculator
import com.cardcopilot.engine.models.CardCredit
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Carry
import com.cardcopilot.engine.models.CreditSchedule
import com.cardcopilot.engine.models.CreditScheduleBasis
import com.cardcopilot.engine.models.CreditScheduleUnit
import com.cardcopilot.engine.models.Currency
import com.cardcopilot.engine.models.Money
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.SourceType
import com.cardcopilot.engine.models.SwitchThreshold
import com.cardcopilot.engine.models.Valuations
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test

class CreditStateEditorTest {
    private val credit = CardCredit(
        creditId = "monthly-credit", label = "Monthly credit", value = Money(10.0, Currency.CAD),
        schedule = CreditSchedule(CreditScheduleBasis.CALENDAR, CreditScheduleUnit.MONTH),
        sourceType = SourceType.ISSUER_CONFIRMED, lastVerifiedAt = "2026-08-24"
    )

    @Test
    fun pendingUseAndPostingRemainDistinct() {
        val pending = CreditStateEditor.applying(
            CreditStateAction.MarkConsumed(), owner(), "card", credit, "2026-08-25"
        )
        assertNotNull(pending)
        var opportunity = CreditAdvisor.opportunity(
            "card", credit, pending!!.cardStates.getValue("card"), "2026-08-25"
        )!!
        assertEquals(CreditOpportunityStatus.USED, opportunity.status)
        assertEquals(10.0, opportunity.consumedAmount)
        assertEquals(0.0, opportunity.realizedAmount)

        val posted = CreditStateEditor.applying(
            CreditStateAction.ConfirmRealized(), pending, "card", credit, "2026-08-26"
        )!!
        opportunity = CreditAdvisor.opportunity(
            "card", credit, posted.cardStates.getValue("card"), "2026-08-26"
        )!!
        assertEquals(10.0, opportunity.realizedAmount)
    }

    @Test
    fun unresolvedAnniversaryWindowCannotBeMarkedUsed() {
        val annual = credit.copy(
            creditId = "annual",
            schedule = CreditSchedule(CreditScheduleBasis.ACCOUNT_ANNIVERSARY, intervalMonths = 12)
        )
        assertNull(CreditStateEditor.applying(
            CreditStateAction.MarkConsumed(), owner(), "card", annual, "2026-08-25"
        ))
    }

    @Test
    fun portfolioCountsPostedCreditButOnlyDisclosesUnspentPotential() {
        val initial = owner()
        val before = CreditPortfolioRecoveryCalculator.recovery(
            "card", listOf(credit), initial.cardStates.getValue("card"), "2026-08-25"
        )
        assertEquals(0.0, before.realizedCad)
        assertEquals(10.0, before.unspentPotentialCad)

        val posted = CreditStateEditor.applying(
            CreditStateAction.ConfirmRealized(), initial, "card", credit, "2026-08-25"
        )!!
        val after = CreditPortfolioRecoveryCalculator.recovery(
            "card", listOf(credit), posted.cardStates.getValue("card"), "2026-08-25"
        )
        assertEquals(10.0, after.realizedCad)
        assertEquals(0.0, after.unspentPotentialCad)
    }

    private fun owner() = OwnerState(
        ownerStateVersion = "1.0", ownedCardIds = listOf("card"), defaultCardId = "card",
        switchThreshold = SwitchThreshold(0.0, 0.0, "either"), carry = Carry(),
        cardStates = mapOf("card" to CardState()), valuationsCad = Valuations()
    )
}
