package com.cardcopilot.engine

import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Valuations
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Co-brand reward currencies: `programId` values that name a real currency, carry no valuation, and
 * are safe only because every card on them is a draft. Kotlin end of the ratchet Swift's
 * CoBrandProgramTests holds.
 *
 * Catalogue 2.4 opened the enum to the co-brand currencies the US market is mostly made of — Avios,
 * AAdvantage, SkyMiles, Atmos Rewards. The 2026-08-27 Option 1 ruling refused to map those onto a
 * near-enough existing value, because a Delta card recorded as `amexMembershipRewardsUs` is not
 * approximately right: it values the card in a currency it does not earn.
 *
 * None of them is valued in programs.json, because `centsPerPoint` is a DISCLOSED ASSUMPTION and
 * there is no honest source for one yet. An unvalued programme is not inert — `Scorer.valueCad`
 * answers null and the card is excluded with `unsupportedProgram` — so what makes shipping them
 * safe is that a draft is stopped before that check is ever reached.
 *
 * Nothing here hardcodes the new programIds. The set is DERIVED as "declared by a card, absent from
 * programs.json", so it maintains itself as the remaining co-brand currencies land.
 */
class CoBrandProgramTest {

    private val valuations = Valuations(programs = SeedLoader.programValuationDefaults)

    /** Programmes some card declares and programs.json does not value. */
    private fun unvaluedDeclaredPrograms(): Set<String> =
        SeedLoader.loadCatalogue().cards
            .map { it.program.programId }
            .filter { it !in SeedLoader.programValuationDefaults }
            .toSortedSet()

    /**
     * The load-bearing one, and the exact mirror image of
     * `ProgramValuationTest.everyCatalogueProgramIdHasACatalogueDefault`. That test asks "is every
     * published programme valued?"; this asks "is every unvalued programme unpublished?" They are
     * the same rule read from both ends, and stating it twice is deliberate: the first would still
     * pass if a card were quietly published on an unvalued programme AND a hollow valuation added
     * to silence it.
     */
    @Test
    fun everyCardOnAnUnvaluedProgramIsADraft() {
        val unvalued = unvaluedDeclaredPrograms()
        val leaked = SeedLoader.loadCatalogue().cards
            .filter { it.program.programId in unvalued && it.isPublished }
            .map { "${it.cardId} (${it.program.programId})" }
        assertTrue(
            leaked.isEmpty(),
            "published card(s) on a programme with no valuation: $leaked. Scorer excludes these " +
                "with unsupportedProgram, so they vanish from every recommendation rather than " +
                "ranking badly. Add a sourced default to contracts/programs.json, or leave the " +
                "card a draft until one exists — never publish it unvalued."
        )
    }

    /**
     * An unvalued programme must stay distinct from a valued-at-zero one. `noRewards` answers 0.0
     * and the card is scored; a co-brand currency answers null and the card is excluded. Collapsing
     * them would rank "we cannot value this" as "this is worth nothing" — the inversion `noRewards`
     * exists to keep impossible.
     */
    @Test
    fun anUnvaluedProgramAnswersNullNotZero() {
        for (program in unvaluedDeclaredPrograms()) {
            assertNull(
                Scorer.valueCad(100.0, program, valuations, CardState()),
                "$program must answer null, keeping it distinct from noRewards' 0.0"
            )
        }
    }

    /**
     * A draft states identity and fee and claims NOTHING about how the card earns. Pinned because
     * the temptation on a co-brand is to write the marketed "3x on airfare" from an aggregator's
     * prose, which is the drift the draft lane exists to prevent.
     */
    @Test
    fun coBrandDraftsClaimNoEarnStructure() {
        val unvalued = unvaluedDeclaredPrograms()
        for (card in SeedLoader.loadCatalogue().cards.filter { it.program.programId in unvalued }) {
            assertTrue(card.earnRules.isEmpty(), "${card.cardId} must claim no earn rules")
            assertTrue(card.fxRules.isEmpty(), "${card.cardId} must claim no FX terms")
            assertTrue(card.caps.isEmpty(), "${card.cardId} must claim no caps")
        }
    }

    /**
     * Avios is the shared IAG currency: British Airways, Aer Lingus and Iberia all earn it, and
     * RBC's Canadian British Airways card earns it into the same Executive Club account. One
     * programId across two markets is INTENDED, on the same 2026-08-27 side-ruling that keeps
     * `marriottBonvoy` and `aeroplan` cross-market — valuation is keyed on programId alone, so
     * sharing one is correct precisely when the currency is genuinely the same. It is not correct
     * for currencies that merely rhyme, which is why the Costco certificates were left out: the
     * CIBC one is CAD and spends only in Canadian warehouses, the Citi one USD and only in US ones.
     */
    @Test
    fun aviosSpansBothMarketsOnOneProgramId() {
        val avios = SeedLoader.loadCatalogue().cards.filter { it.program.programId == "avios" }
        assertEquals(4, avios.size, "Aer Lingus, British Airways, Iberia (US) and RBC BA (CA)")
        assertEquals(
            setOf("US", "CA"), avios.map { it.market.name.uppercase() }.toSet(),
            "the cross-market case is the point — do not let this collapse to one market"
        )
    }
}
