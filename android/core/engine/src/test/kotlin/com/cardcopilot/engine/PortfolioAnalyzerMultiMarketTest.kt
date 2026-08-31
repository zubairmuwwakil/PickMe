package com.cardcopilot.engine

import com.cardcopilot.engine.engine.PortfolioAnalyzer
import com.cardcopilot.engine.models.Cap
import com.cardcopilot.engine.models.CapMeasure
import com.cardcopilot.engine.models.CapPeriod
import com.cardcopilot.engine.models.CardCredit
import com.cardcopilot.engine.models.CardKind
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.Carry
import com.cardcopilot.engine.models.CashBackValuation
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.Currency
import com.cardcopilot.engine.models.CreditEnrollment
import com.cardcopilot.engine.models.CreditRedemptionMethod
import com.cardcopilot.engine.models.CreditSchedule
import com.cardcopilot.engine.models.CreditScheduleBasis
import com.cardcopilot.engine.models.CreditScheduleUnit
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.Fee
import com.cardcopilot.engine.models.FxRule
import com.cardcopilot.engine.models.Market
import com.cardcopilot.engine.models.Network
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.Predicate
import com.cardcopilot.engine.models.Program
import com.cardcopilot.engine.models.ReportingCurrency
import com.cardcopilot.engine.models.RuleStatus
import com.cardcopilot.engine.models.SourceType
import com.cardcopilot.engine.models.SpendDistribution
import com.cardcopilot.engine.models.SwitchThreshold
import com.cardcopilot.engine.models.Valuations
import kotlin.math.abs
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Mirrors `PortfolioAnalyzerTests.swift`'s
 * `testQuarterlyCapsResetAndAccrueInTheCardsNativeCurrencyOverAFullYear` — the annual keep/cancel
 * simulation, not just `Scorer.score` in isolation, has to get a `.calendarQuarter` cap's reset
 * and its native-currency accrual right across all twelve simulated months.
 */
class PortfolioAnalyzerMultiMarketTest {

    /** A USD-billing card with a $1,500 USD/quarter grocery cap. */
    private val quarterlyUsdCashbackCard = CardProduct(
        cardId = "usd-cashback-quarterly-test",
        officialName = "Test USD Quarterly Cashback Card",
        issuer = "Test Bank",
        market = Market.US,
        billingCurrency = Currency.USD,
        network = Network.VISA,
        kind = CardKind.CREDIT,
        fee = Fee(),
        program = Program(programId = "cashback", unit = "cashback"),
        fxRules = listOf(FxRule(status = RuleStatus.CURRENT, rate = 0.025)),
        earnRules = listOf(
            EarnRule(
                ruleId = "grocery-5x-quarterly",
                status = RuleStatus.CURRENT,
                sourceType = SourceType.ISSUER_CONFIRMED,
                earn = Earn.Cashback(rate = 0.05),
                predicate = Predicate(categories = listOf("grocery")),
                capId = "grocery-cap",
            ),
        ),
        caps = listOf(
            Cap(
                capId = "grocery-cap",
                measure = CapMeasure.SPEND_NATIVE,
                limit = 1500.0,
                period = CapPeriod.CALENDAR_QUARTER,
                resetTimeZone = "UTC",
                postCapEarn = Earn.Cashback(rate = 0.01),
                proration = true,
            ),
        ),
        perTransactionRewardVisibility = "issuerConfirmed",
        lastVerifiedAt = "2026-08-26",
    )

    /**
     * Twelve months of grocery spend sized to blow through the $1,500 USD quarterly cap by the
     * third month of every quarter — so a full year is four identical quarters *only if* the cap
     * actually resets every three months and is checked against the same currency it accrues in.
     *
     * Before this fix: `resetMonthlyCaps` never reset a `CALENDAR_QUARTER` cap at all, so month 4
     * onward stayed permanently over-cap; separately, `accrueCapProgress` recorded
     * `purchase.amountCad` (here, a CAD figure picked to diverge sharply from the $600 USD
     * actually spent) against a limit denominated in the card's own USD billing currency. Either
     * bug alone moves the annual total far from the value below; this pins the fixed number so
     * neither can silently come back.
     */
    @Test
    fun quarterlyCapsResetAndAccrueInTheCardsNativeCurrencyOverAFullYear() {
        val catalogue = Catalogue(catalogueVersion = "2.0", currency = "CAD", cards = listOf(quarterlyUsdCashbackCard))
        val ownerState = OwnerState(
            ownerStateVersion = "test",
            ownedCardIds = emptyList(),
            defaultCardId = "usd-cashback-quarterly-test",
            switchThreshold = SwitchThreshold(0.0, 0.0, "either"),
            carry = Carry(emptyList()),
            cardStates = emptyMap(),
            valuationsCad = Valuations(programs = mapOf("cashback" to CashBackValuation(cadPerDollar = 1.0))),
        )

        val distribution = SpendDistribution(
            profileId = "quarterly-cap-currency-check",
            basis = "synthetic: \$600 USD/mo of grocery spend against a \$1,500 USD/quarter cap, " +
                "quoted at a CAD amount (\$822/mo) chosen to diverge sharply from \$600 so a " +
                "currency mix-up in cap accrual cannot cancel out unnoticed",
            buckets = listOf(
                SpendDistribution.Bucket(
                    label = "Groceries",
                    annualCad = 822.0 * 12,
                    category = "grocery",
                    usdEquivalent = 600.0 * 12,
                ),
            ),
        )

        val analyzer = PortfolioAnalyzer(catalogue = catalogue, ownerState = ownerState)
        val run = analyzer.run(distribution, emptySet(), "2026-01-01")

        // Every quarter: $600 in-cap at 5% for two months, then a 3rd month split $300 in-cap /
        // $300 over-cap (300×0.05 + 300×0.01) — 78 USD cashback units/quarter, ×4 quarters, minus
        // the 2.5% FX spread charged every month on the full $600 USD (never gated by the cap),
        // all converted to CAD at the pinned USD->CAD rate.
        val quarterlyUnitsUsd = 600.0 * 0.05 + 600.0 * 0.05 + (300.0 * 0.05 + 300.0 * 0.01)
        val quarterlyFxUsd = 600.0 * 0.025 * 3
        val expected = (quarterlyUnitsUsd * 4 - quarterlyFxUsd * 4) * ReportingCurrency.pinnedUsdToCad
        assertTrue(
            abs(run.totalValueCad - expected) < 0.01,
            "expected $expected, got ${run.totalValueCad}",
        )
    }

    /** Checkout urgency is a one-window decision input, never repeatable annual reward yield. */
    @Test
    fun portfolioSimulationDoesNotReplayCheckoutCreditAcrossTheYear() {
        val credit = CardCredit(
            creditId = "monthly-dining", label = "Monthly dining credit",
            value = com.cardcopilot.engine.models.Money(10.0, Currency.CAD),
            schedule = CreditSchedule(CreditScheduleBasis.CALENDAR, CreditScheduleUnit.MONTH),
            redemptionMethod = CreditRedemptionMethod.STATEMENT_CREDIT,
            purchasePredicate = Predicate(categories = listOf("dining")),
            allowsPartialUse = true, enrollment = CreditEnrollment(required = false),
            sourceType = SourceType.ISSUER_CONFIRMED, lastVerifiedAt = "2026-08-31",
        )
        fun card(id: String, rate: Double, credits: List<CardCredit>? = null) = CardProduct(
            cardId = id, officialName = id, issuer = "Test Bank", network = Network.VISA,
            kind = CardKind.CREDIT, fee = Fee(), program = Program("cashback", "cashback"),
            fxRules = listOf(FxRule(status = RuleStatus.CURRENT, rate = 0.0)),
            earnRules = listOf(EarnRule(
                ruleId = "base", status = RuleStatus.CURRENT,
                sourceType = SourceType.ISSUER_CONFIRMED,
                earn = Earn.Cashback(rate = rate), predicate = Predicate(),
            )),
            perTransactionRewardVisibility = "issuerConfirmed",
            lastVerifiedAt = "2026-08-31", credits = credits,
        )
        val catalogue = Catalogue("2.18", "CAD", listOf(
            card("credit-card", 0.0, listOf(credit)), card("two-percent", 0.02),
        ))
        val owner = OwnerState(
            ownerStateVersion = "test", ownedCardIds = listOf("credit-card", "two-percent"),
            defaultCardId = "two-percent", switchThreshold = SwitchThreshold(0.0, 0.0, "either"),
            carry = Carry(),
            cardStates = mapOf("credit-card" to com.cardcopilot.engine.models.CardState()),
            valuationsCad = Valuations(programs = mapOf(
                "cashback" to CashBackValuation(cadPerDollar = 1.0),
            )),
        )
        val distribution = SpendDistribution(
            "credit-isolation", "synthetic",
            listOf(SpendDistribution.Bucket("Dining", 1200.0, "dining")),
        )

        val run = PortfolioAnalyzer(catalogue, owner).run(distribution, emptySet(), "2026-08-01")
        assertEquals(24.0, run.totalValueCad, 0.001)
        assertEquals(24.0, run.valueByCard["two-percent"]!!, 0.001)
        assertNull(run.valueByCard["credit-card"])
    }
}
