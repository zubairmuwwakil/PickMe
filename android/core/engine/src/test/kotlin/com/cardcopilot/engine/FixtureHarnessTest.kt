package com.cardcopilot.engine

import com.cardcopilot.engine.engine.RecommendationEngine
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.math.abs

class FixtureHarnessTest {

    @Serializable
    private data class FixtureFile(
        val cases: List<FixtureCase>,
        val pinnedValuations: PinnedValuations
    ) {
        @Serializable
        data class PinnedValuations(val amexMembershipRewards: Double)
    }

    @Serializable
    private data class FixtureCase(
        val caseId: String,
        val purchase: PurchaseContext,
        val asOf: String? = null,
        val ownerStateOverrides: Overrides? = null,
        val expected: Expected
    ) {
        @Serializable
        data class Overrides(val cardStates: Map<String, CardStateOverride>? = null)

        @Serializable
        data class CardStateOverride(
            val capProgress: Map<String, Double>? = null,
            val scotiaAccountYearAnchorMonth: Int? = null,
            val selectedCategories: List<String>? = null,
            val treatAsAllSelected: Boolean? = null,
            val thirdCategoryUnlocked: Boolean? = null,
            val nextChangeEffectiveDate: String? = null,
            val rogersEligibleServiceLinked: Boolean? = null,
            val rogersAccountAnniversaryMonth: Int? = null,
            val feeWaiverActive: Boolean? = null,
            val cryptoLevelUpProActive: Boolean? = null,
            val croHandling: String? = null,
            val unsetFields: List<String>? = null
        )

        @Serializable
        data class Expected(
            val winner: String,
            val winnerValueCad: Double,
            val winnerRule: String? = null,
            val runnerUp: String? = null,
            val runnerUpValueCad: Double? = null,
            val switchFromDefault: Boolean? = null,
            val advantageOverDefaultCad: Double? = null,
            val defaultNotAccepted: Boolean? = null,
            val suppressedBetterCard: String? = null,
            val suppressedValueCad: Double? = null,
            val warnings: List<String>? = null,
            val warningsAbsent: List<String>? = null,
            val valuationSensitive: Boolean? = null,
            val valuationDirection: String? = null,
            val alternateWinner: String? = null,
            val breakevenCentsPerPoint: Double? = null
        )
    }

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    @Test
    fun testAllFixtures() {
        val stream = javaClass.getResourceAsStream("/com/cardcopilot/engine/engine-fixtures.json")
            ?: javaClass.classLoader.getResourceAsStream("com/cardcopilot/engine/engine-fixtures.json")
        assertNotNull(stream, "engine-fixtures.json not found in test resources")

        val content = stream.bufferedReader().use { it.readText() }
        val fixtureFile = json.decodeFromString<FixtureFile>(content)

        assertEquals(28, fixtureFile.cases.size)
        assertEquals(28, fixtureFile.cases.map { it.caseId }.toSet().size, "duplicate caseId")

        val catalogue = SeedLoader.loadCatalogue()
        var baseState = SeedLoader.loadOwnerState()

        val updatedValuations = baseState.valuationsCad.copy(
            amexMembershipRewards = baseState.valuationsCad.amexMembershipRewards.copy(
                centsPerPoint = fixtureFile.pinnedValuations.amexMembershipRewards
            )
        )
        baseState = baseState.copy(valuationsCad = updatedValuations)

        val defaultAsOf = "2026-08-20"

        for (fixture in fixtureFile.cases) {
            var state = baseState
            val ctx = "case ${fixture.caseId}"

            val overrides = fixture.ownerStateOverrides?.cardStates
            if (overrides != null) {
                val updatedStates = state.cardStates.toMutableMap()
                for ((cardId, override) in overrides) {
                    var merged = updatedStates[cardId] ?: CardState()
                    if (override.capProgress != null) {
                        merged = merged.copy(capProgress = (merged.capProgress ?: emptyMap()) + override.capProgress)
                    }
                    if (override.cryptoLevelUpProActive != null) merged = merged.copy(cryptoLevelUpProActive = override.cryptoLevelUpProActive)
                    if (override.croHandling != null) merged = merged.copy(croHandling = override.croHandling)
                    if (override.rogersEligibleServiceLinked != null) merged = merged.copy(rogersEligibleServiceLinked = override.rogersEligibleServiceLinked)
                    if (override.selectedCategories != null) merged = merged.copy(selectedCategories = override.selectedCategories)

                    for (field in override.unsetFields ?: emptyList()) {
                        merged = when (field) {
                            "capProgress" -> merged.copy(capProgress = null)
                            "cryptoLevelUpProActive" -> merged.copy(cryptoLevelUpProActive = null)
                            "croHandling" -> merged.copy(croHandling = null)
                            "rogersEligibleServiceLinked" -> merged.copy(rogersEligibleServiceLinked = null)
                            "selectedCategories" -> merged.copy(selectedCategories = null)
                            "treatAsAllSelected" -> merged.copy(treatAsAllSelected = null)
                            else -> throw AssertionError("$ctx: unknown unsetFields entry '$field'")
                        }
                    }
                    updatedStates[cardId] = merged
                }
                state = state.copy(cardStates = updatedStates)
            }

            val engine = RecommendationEngine(catalogue, state)
            val r = engine.recommend(fixture.purchase, fixture.asOf ?: defaultAsOf)
            val e = fixture.expected

            assertEquals(e.winner, r.winner.cardId, ctx)
            assertEquals(e.winnerValueCad, r.winner.netValueCad, 0.005, ctx)

            if (e.winnerRule != null) {
                assertEquals(e.winnerRule, r.winner.appliedRuleId, ctx)
            }
            if (e.runnerUp != null) {
                assertEquals(e.runnerUp, r.runnerUp?.cardId, ctx)
            }
            if (e.runnerUpValueCad != null) {
                assertEquals(e.runnerUpValueCad, r.runnerUp?.netValueCad ?: Double.NaN, 0.005, ctx)
            }
            if (e.switchFromDefault != null) {
                assertEquals(e.switchFromDefault, r.switchedFromDefault, ctx)
            }
            if (e.advantageOverDefaultCad != null) {
                assertEquals(e.advantageOverDefaultCad, r.advantageOverDefaultCad ?: Double.NaN, 0.005, ctx)
            }
            if (e.defaultNotAccepted != null) {
                assertEquals(e.defaultNotAccepted, r.defaultNotAccepted, ctx)
            }
            if (e.suppressedBetterCard != null) {
                assertEquals(e.suppressedBetterCard, r.suppressedBetterCard?.cardId, ctx)
            }
            if (e.suppressedValueCad != null) {
                assertEquals(e.suppressedValueCad, r.suppressedBetterCard?.netValueCad ?: Double.NaN, 0.005, ctx)
            }

            val actualWarnings = r.winner.warnings.map { it.rawValue }
            for (w in e.warnings ?: emptyList()) {
                assertTrue(actualWarnings.contains(w), "$ctx: missing warning $w, actual: $actualWarnings")
            }
            for (w in e.warningsAbsent ?: emptyList()) {
                assertFalse(actualWarnings.contains(w), "$ctx: unexpected warning $w, actual: $actualWarnings")
            }

            if (e.valuationSensitive != null) {
                assertEquals(e.valuationSensitive, r.valuationSensitive, ctx)
            }
            if (e.valuationDirection != null) {
                assertEquals(e.valuationDirection, r.valuationDirection?.name?.lowercase(), ctx)
            }
            if (e.alternateWinner != null) {
                assertEquals(e.alternateWinner, r.alternateWinnerCardId, ctx)
            }
            if (e.breakevenCentsPerPoint != null) {
                assertEquals(e.breakevenCentsPerPoint, r.breakevenCentsPerPoint ?: Double.NaN, 0.005, ctx)
            }
        }
    }
}
