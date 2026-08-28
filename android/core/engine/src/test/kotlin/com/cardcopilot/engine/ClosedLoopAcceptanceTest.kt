package com.cardcopilot.engine

import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.Acceptance
import com.cardcopilot.engine.models.AcceptanceScope
import com.cardcopilot.engine.models.CandidateScore
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.Network
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.RuleStatus
import com.cardcopilot.engine.models.SourceType
import com.cardcopilot.engine.models.Warning
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The Kotlin twin of `Engine/Tests/CardCopilotEngineTests/ClosedLoopAcceptanceTests.swift`.
 *
 * A private-label card runs on no payment network. Before `privateLabel` existed the only way to
 * land one was to guess — and a Kohl's card recorded as `visa` gets recommended at a gas station
 * and declined at the till. Both engines read the same catalogue, so both must gate the same way.
 */
class ClosedLoopAcceptanceTest {

    private val asOf = "2026-08-27"

    /**
     * A real, valued catalogue card with its acceptance rewritten — the same trick
     * [CapabilityGatingTest] uses, and for the same reason: it keeps `program`, `fee` and the
     * valuation honest, so a closed-loop card that scores does so for real reasons.
     */
    private fun card(network: Network, acceptance: Acceptance?): CardProduct =
        SeedLoader.loadCatalogue().cards.first { it.cardId == "scotia-momentum-vi-plus" }
            .copy(
                network = network,
                acceptance = acceptance,
                caps = emptyList(),
                earnRules = listOf(
                    EarnRule(
                        ruleId = "flat-2pct",
                        status = RuleStatus.CURRENT,
                        sourceType = SourceType.ISSUER_CONFIRMED,
                        earn = Earn.Cashback(rate = 0.02)
                    )
                )
            )

    private fun closedLoopCard(merchants: List<String>): CardProduct =
        card(Network.PRIVATE_LABEL, Acceptance(AcceptanceScope.CLOSED_LOOP, merchants))

    private fun score(card: CardProduct, purchase: PurchaseContext): CandidateScore =
        Scorer.score(card, purchase, SeedLoader.loadOwnerState(), asOf)

    @Test
    fun aClosedLoopCardIsExcludedAtAnotherMerchant() {
        val s = score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "gasStation", merchantBrand = "petro-canada")
        )
        assertTrue(s.excluded)
        assertTrue(Warning.MERCHANT_NOT_ACCEPTED in s.warnings)
    }

    /**
     * The product claim, not just the guard: at its own merchant the card scores a real number.
     * Asserting only the absence of a warning would pass even if the card were excluded for some
     * unrelated reason, which would hide exactly the regression this file exists to catch.
     */
    @Test
    fun aClosedLoopCardIsAcceptedAtItsOwnMerchant() {
        val s = score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "retail", merchantBrand = "kohls")
        )
        assertFalse(Warning.MERCHANT_NOT_ACCEPTED in s.warnings)
        assertFalse(s.excluded, "exclusion reason: ${s.exclusionReason ?: "none"}")
        assertEquals(1.0, s.netValueCad, 0.0001, "2% of \$50, scored like any other card")
    }

    /**
     * The safe failure direction: silence beats recommending a card that gets declined. These
     * cards are only ever as good as brand resolution — a stated assumption, not a hidden one.
     */
    @Test
    fun anUnknownMerchantExcludesAClosedLoopCard() {
        val s = score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "retail", merchantBrand = null)
        )
        assertTrue(s.excluded)
        assertTrue(Warning.MERCHANT_NOT_ACCEPTED in s.warnings)
    }

    /**
     * MERCHANT_NOT_ACCEPTED is its own case because the two facts are different and the UI must
     * not conflate them: "this card only works at Kohl's" is not "Visa isn't accepted here".
     */
    @Test
    fun theNetworkWarningIsNotReusedForAMerchantRefusal() {
        val s = score(
            closedLoopCard(listOf("kohls")),
            PurchaseContext(amountCad = 50.0, category = "retail", merchantBrand = "petro-canada")
        )
        assertFalse(Warning.NETWORK_NOT_ACCEPTED in s.warnings)
    }

    /** Fail-closed: an open-loop card is untouched by any of this. */
    @Test
    fun anOpenLoopCardStillGuardsOnNetwork() {
        val s = score(
            card(Network.VISA, acceptance = null),
            PurchaseContext(
                amountCad = 50.0,
                category = "retail",
                acceptedNetworks = setOf(Network.MASTERCARD)
            )
        )
        assertTrue(s.excluded)
        assertTrue(Warning.NETWORK_NOT_ACCEPTED in s.warnings)
        assertEquals("visa not accepted", s.exclusionReason)
    }

    /**
     * `Network.rawValue` used to be `name.lowercase()`, which was correct only while every case
     * was one word. PRIVATE_LABEL would have rendered as "private_label" where Swift renders
     * "privateLabel" — a divergence that reaches the owner through `exclusionReason`.
     *
     * Both enums are pinned here because nothing else does it. The two engines were verified to
     * emit identical bytes for a closed-loop card — `"network":"privateLabel"` and
     * `"acceptance":{"scope":"closedLoop","merchants":[...]}`, with the key omitted entirely when
     * acceptance is absent — but only these spellings are asserted, so a renamed @SerialName
     * would otherwise diverge silently until a real private-label card existed to break.
     */
    @Test
    fun theWireNamesOfTheNewEnumsMatchSwift() {
        assertEquals("privateLabel", Network.PRIVATE_LABEL.rawValue)
        assertEquals("closedLoop", AcceptanceScope.CLOSED_LOOP.rawValue)
        assertEquals("openLoop", AcceptanceScope.OPEN_LOOP.rawValue)
    }
}
