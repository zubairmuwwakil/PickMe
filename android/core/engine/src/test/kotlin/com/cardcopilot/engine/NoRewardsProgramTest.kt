package com.cardcopilot.engine

import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.NoRewardsValuation
import com.cardcopilot.engine.models.Valuations
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * `noRewards` — the valuation model for a card that earns nothing. Kotlin end of the ratchet
 * Swift's NoRewardsProgramTests holds.
 *
 * The distinction under test is the one Scorer.valueCad has always drawn and could not previously
 * express: a MISSING valuation answers null and the card is excluded with `unsupportedProgram`,
 * because "we do not know what this is worth" must never rank as "worth nothing". A card with no
 * rewards programme is the other case — valued, at zero — and had no way to say so, because
 * `program` is required with a closed `programId` enum.
 */
class NoRewardsProgramTest {

    private val valuations = Valuations(programs = SeedLoader.programValuationDefaults)

    @Test
    fun noRewardsValuesToZeroRatherThanNull() {
        assertEquals(
            0.0,
            Scorer.valueCad(100.0, "noRewards", valuations, CardState()),
            "noRewards must value to zero, not null — null excludes the card"
        )
    }

    @Test
    fun anUnknownProgramStillAnswersNull() {
        assertNull(
            Scorer.valueCad(100.0, "notARealProgramme", valuations, CardState()),
            "the unvalued case must stay distinct from the valued-at-zero case"
        )
    }

    @Test
    fun theCatalogueShipsTheDefaultWithItsDisclosure() {
        val v = SeedLoader.programValuationDefaults["noRewards"]
        assertTrue(v is NoRewardsValuation, "programs.json must ship a noRewards default")
        assertFalse((v as NoRewardsValuation).basis.isNullOrEmpty(),
            "a shipped default must disclose its basis")
    }

    @Test
    fun theCardsThatForcedItAreInTheCatalogue() {
        val onIt = SeedLoader.loadCatalogue().cards
            .filter { it.program.programId == "noRewards" }
            .map { it.cardId }
        assertTrue(onIt.isNotEmpty(),
            "programs.json values noRewards, so some card must declare it — see " +
                "everyCatalogueProgramIdHasACatalogueDefault's mirror image")
    }
}
