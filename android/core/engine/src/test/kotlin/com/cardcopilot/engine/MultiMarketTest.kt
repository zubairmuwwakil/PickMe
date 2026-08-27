package com.cardcopilot.engine

import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.models.Cap
import com.cardcopilot.engine.models.CapMeasure
import com.cardcopilot.engine.models.CapPeriod
import com.cardcopilot.engine.models.CardKind
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardStatus
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Carry
import com.cardcopilot.engine.models.CashBackValuation
import com.cardcopilot.engine.models.Currency
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.Fee
import com.cardcopilot.engine.models.FxRule
import com.cardcopilot.engine.models.Market
import com.cardcopilot.engine.models.Network
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.Predicate
import com.cardcopilot.engine.models.Program
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.RuleStatus
import com.cardcopilot.engine.models.SourceType
import com.cardcopilot.engine.models.SwitchThreshold
import com.cardcopilot.engine.models.Valuations
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.math.abs

/**
 * Targeted coverage for the 2026-08-26 multi-market capabilities (Money-shaped fee/credit
 * values, market/billingCurrency, spendNative replacing spendCad, calendarQuarter, draft status)
 * — deliberately NOT added to engine-fixtures.json, the cross-language contract keyed to the
 * real 41-card catalogue, every one of which is CAD-billing today. A synthetic card belongs
 * here, constructed directly, never in the shared production catalogue (D3's sourcing bar).
 *
 * Mirrors `src/engine/cards-twin/multiMarket.test.ts` in MoneyTalks.
 */
class MultiMarketTest {

    private val asOf = "2026-08-26"

    private val usdCashbackCard = CardProduct(
        cardId = "usd-cashback-test",
        officialName = "Test USD Cashback Card",
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
            EarnRule(
                ruleId = "base",
                status = RuleStatus.CURRENT,
                sourceType = SourceType.ISSUER_CONFIRMED,
                earn = Earn.Cashback(rate = 0.01),
                predicate = Predicate(),
                capId = null,
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

    private fun ownerState(cardStates: Map<String, CardState> = emptyMap()) = OwnerState(
        ownerStateVersion = "test",
        ownedCardIds = emptyList(),
        defaultCardId = "usd-cashback-test",
        switchThreshold = SwitchThreshold(0.0, 0.0, "either"),
        carry = Carry(emptyList()),
        cardStates = cardStates,
        valuationsCad = Valuations(programs = mapOf("cashback" to CashBackValuation(cadPerDollar = 1.0))),
    )

    @Test
    fun earnsOnTheUsdEquivalentAmountNotTheCadAmount() {
        val purchase = PurchaseContext(
            amountCad = 137.0,
            currency = "CAD",
            usdEquivalent = 100.0,
            category = "grocery",
        )
        val score = Scorer.score(usdCashbackCard, purchase, ownerState(), asOf)
        assertFalse(score.excluded)
        assertEquals("grocery-5x-quarterly", score.appliedRuleId)
        // 5% of the $100 USD equivalent (= US$5 cashback), converted to the CAD reporting figure
        // — NOT left as if US$5 were C$5. Cashback is real money in the card's billing currency,
        // unlike points (a currency-agnostic token), so this conversion is load-bearing.
        val expectedCad = 100.0 * 0.05 * (1.0 / Scorer.FALLBACK_CAD_TO_USD)
        assertTrue(abs(score.rewardUnits - expectedCad) < 1e-6, "expected $expectedCad, got ${score.rewardUnits}")
    }

    @Test
    fun fallsBackToThePinnedRateWhenNoUsdEquivalentSupplied() {
        val purchase = PurchaseContext(amountCad = 137.0, currency = "CAD", category = "grocery")
        val score = Scorer.score(usdCashbackCard, purchase, ownerState(), asOf)
        // CAD -> USD (FALLBACK_CAD_TO_USD) to compute native earn, then USD -> CAD (its exact
        // inverse) to report it — the two conversions cancel, leaving 137 * 0.05.
        val expected = 137.0 * Scorer.FALLBACK_CAD_TO_USD * 0.05 * (1.0 / Scorer.FALLBACK_CAD_TO_USD)
        assertTrue(abs(score.rewardUnits - expected) < 1e-6)
    }

    @Test
    fun chargesFxWhenPurchaseCurrencyDiffersFromTheCardsBillingCurrency() {
        val purchase = PurchaseContext(amountCad = 137.0, currency = "CAD", usdEquivalent = 100.0, category = "other")
        val score = Scorer.score(usdCashbackCard, purchase, ownerState(), asOf)
        val expectedFxCad = (100.0 * 0.025) * (1.0 / Scorer.FALLBACK_CAD_TO_USD)
        assertTrue(abs(score.fxCostCad - expectedFxCad) < 1e-6, "expected $expectedFxCad, got ${score.fxCostCad}")
    }

    @Test
    fun chargesNoFxWhenPurchaseCurrencyMatchesTheCardsUsdBillingCurrency() {
        val purchase = PurchaseContext(amountCad = 137.0, currency = "USD", usdEquivalent = 100.0, category = "other")
        val score = Scorer.score(usdCashbackCard, purchase, ownerState(), asOf)
        assertEquals(0.0, score.fxCostCad)
    }

    @Test
    fun splitsAQuarterlyCapStraddleUsingTheNativeUsdAmount() {
        val purchase = PurchaseContext(amountCad = 274.0, currency = "CAD", usdEquivalent = 200.0, category = "grocery")
        val state = ownerState(cardStates = mapOf("usd-cashback-test" to CardState(capProgress = mapOf("grocery-cap" to 1400.0))))
        val score = Scorer.score(usdCashbackCard, purchase, state, asOf)
        val expected = (100.0 * 0.05 + 100.0 * 0.01) * (1.0 / Scorer.FALLBACK_CAD_TO_USD)
        assertTrue(abs(score.rewardUnits - expected) < 1e-6, "expected $expected, got ${score.rewardUnits}")
    }

    @Test
    fun excludesADraftCardEvenWhenOwned() {
        val draftCard = usdCashbackCard.copy(status = CardStatus.DRAFT)
        val purchase = PurchaseContext(amountCad = 100.0, currency = "CAD", category = "grocery")
        val state = ownerState().copy(ownedCardIds = listOf("usd-cashback-test"))
        val score = Scorer.score(draftCard, purchase, state, asOf)
        assertTrue(score.excluded)
    }

    @Test
    fun scoresNormallyWhenStatusIsPublishedOrAbsent() {
        val purchase = PurchaseContext(amountCad = 100.0, currency = "CAD", usdEquivalent = 73.0, category = "grocery")
        assertFalse(Scorer.score(usdCashbackCard, purchase, ownerState(), asOf).excluded)
        assertFalse(
            Scorer.score(usdCashbackCard.copy(status = CardStatus.PUBLISHED), purchase, ownerState(), asOf).excluded,
        )
    }
}
