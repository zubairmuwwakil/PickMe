package com.cardcopilot.engine

import com.cardcopilot.engine.engine.AmbientAdvantage
import com.cardcopilot.engine.engine.AmbientDeliveryTier
import com.cardcopilot.engine.engine.AmbientGate
import com.cardcopilot.engine.engine.AmbientGateInput
import com.cardcopilot.engine.engine.AmbientMerchantConfidence
import com.cardcopilot.engine.engine.AmbientSuppressionReason
import com.cardcopilot.engine.models.SwitchThreshold
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class AmbientGateTest {
    private val both = SwitchThreshold(
        minAdvantagePercentagePoints = 1.0,
        minAdvantageCad = 1.0,
        semantics = "both"
    )

    private fun passingInput() = AmbientGateInput(
        merchantConfidence = AmbientMerchantConfidence.VERIFIED,
        recommendedCardId = "amex-cobalt",
        defaultCardId = "wealthsimple-vip",
        advantage = AmbientAdvantage(percentagePoints = 1.5, cad = 2.0),
        switchThreshold = both,
        isMuted = false
    )

    @Test
    fun clearArrivalInterrupts() {
        assertEquals(AmbientDeliveryTier.INTERRUPT, AmbientGate.evaluate(passingInput()).tier)
    }

    @Test
    fun defaultCardWinConfirmsRatherThanSilencing() {
        val input = passingInput().copy(recommendedCardId = "wealthsimple-vip")
        assertEquals(AmbientDeliveryTier.CONFIRM, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun advantageBelowThresholdConfirms() {
        val input = passingInput().copy(
            advantage = AmbientAdvantage(percentagePoints = 0.99, cad = 2.0)
        )
        assertEquals(AmbientDeliveryTier.CONFIRM, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun unknownMerchantGetsPresenceWithoutAdvice() {
        val input = passingInput().copy(merchantConfidence = AmbientMerchantConfidence.UNKNOWN)
        assertEquals(AmbientDeliveryTier.PRESENCE, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun mutedMerchantIsSilent() {
        assertEquals(
            AmbientDeliveryTier.SILENT,
            AmbientGate.evaluate(passingInput().copy(isMuted = true)).tier
        )
    }

    @Test
    fun mutePrecedesEveryOtherReason() {
        val input = passingInput().copy(
            isMuted = true,
            merchantConfidence = AmbientMerchantConfidence.UNKNOWN,
            recommendedCardId = "wealthsimple-vip"
        )
        assertEquals(AmbientDeliveryTier.SILENT, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun unknownMerchantPrecedesVolumeReasons() {
        val input = passingInput().copy(
            merchantConfidence = AmbientMerchantConfidence.UNKNOWN,
            recommendedCardId = "wealthsimple-vip"
        )
        assertEquals(AmbientDeliveryTier.PRESENCE, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun firesStillMeansInterrupt() {
        val inputs = listOf(
            passingInput(),
            passingInput().copy(isMuted = true),
            passingInput().copy(merchantConfidence = AmbientMerchantConfidence.UNKNOWN),
            passingInput().copy(recommendedCardId = "wealthsimple-vip")
        )
        for (input in inputs) {
            val decision = AmbientGate.evaluate(input)
            assertEquals(decision.tier == AmbientDeliveryTier.INTERRUPT, decision.fires)
            assertEquals(decision.suppressionReasons.isEmpty(), decision.fires)
        }
    }

    /**
     * The tier this replaces was UNKNOWN, a hard stop no multiplier can reach. Apple classifying a
     * POI as a pharmacy is evidence about the category, which is the only thing the card actually
     * depends on, so it must be able to reach the advantage conjunct at all.
     */
    @Test
    fun categoryMatchedMerchantIsNotAHardStop() {
        val input = passingInput().copy(
            merchantConfidence = AmbientMerchantConfidence.CATEGORY_MATCHED,
            advantage = AmbientAdvantage(percentagePoints = 2.0, cad = 2.0)
        )
        val decision = AmbientGate.evaluate(input)
        assertEquals(AmbientDeliveryTier.INTERRUPT, decision.tier)
        assertFalse(
            AmbientSuppressionReason.MERCHANT_CONFIDENCE_LOW in decision.suppressionReasons
        )
    }

    /**
     * Its multiplier starts equal to the unverified one, so introducing the tier changes which bar
     * a place-type arrival is judged against but never moves the bar itself.
     */
    @Test
    fun categoryMatchedStartsAtTheSameBarAsABrandMatchedGuess() {
        val base = passingInput().copy(
            merchantConfidence = AmbientMerchantConfidence.CATEGORY_MATCHED
        )
        assertFalse(
            AmbientGate.evaluate(
                base.copy(advantage = AmbientAdvantage(percentagePoints = 2.0, cad = 1.99))
            ).fires
        )
        assertTrue(
            AmbientGate.evaluate(
                base.copy(advantage = AmbientAdvantage(percentagePoints = 2.0, cad = 2.0))
            ).fires
        )
    }

    /**
     * Its own counter, for the reason ADVANTAGE_BELOW_UNVERIFIED_THRESHOLD has one: the multiplier
     * is separately tunable, and pooled misses can only be tuned against evidence that belongs to
     * another tier.
     */
    @Test
    fun categoryMatchedMissIsCountedUnderItsOwnReasonAndConfirms() {
        val decision = AmbientGate.evaluate(
            passingInput().copy(
                merchantConfidence = AmbientMerchantConfidence.CATEGORY_MATCHED,
                advantage = AmbientAdvantage(percentagePoints = 0.5, cad = 0.5)
            )
        )
        assertEquals(
            setOf(AmbientSuppressionReason.ADVANTAGE_BELOW_CATEGORY_THRESHOLD),
            decision.suppressionReasons
        )
        assertEquals(AmbientDeliveryTier.CONFIRM, decision.tier)
    }

    /** Every tier is measured against exactly one threshold, so no counter double-counts a miss. */
    @Test
    fun everyTierMissesAgainstExactlyOneThreshold() {
        val advantageReasons = setOf(
            AmbientSuppressionReason.ADVANTAGE_BELOW_SWITCH_THRESHOLD,
            AmbientSuppressionReason.ADVANTAGE_BELOW_UNVERIFIED_THRESHOLD,
            AmbientSuppressionReason.ADVANTAGE_BELOW_FREQUENTED_THRESHOLD,
            AmbientSuppressionReason.ADVANTAGE_BELOW_CATEGORY_THRESHOLD
        )
        for (confidence in AmbientMerchantConfidence.entries) {
            val reasons = AmbientGate.evaluate(
                passingInput().copy(
                    merchantConfidence = confidence,
                    advantage = AmbientAdvantage(percentagePoints = 0.0, cad = 0.0)
                )
            ).suppressionReasons
            assertTrue(
                reasons.intersect(advantageReasons).size <= 1,
                "$confidence was measured against more than one threshold"
            )
        }
    }

    /**
     * The point of moving these onto the input is that they can change at runtime, so the one
     * thing that must not change is what happens when nobody changes them.
     */
    @Test
    fun omittedMultipliersReproduceTheShippedPolicy() {
        val input = passingInput()
        assertEquals(2.0, input.unverifiedAdvantageMultiplier)
        assertEquals(1.0, input.frequentedAdvantageMultiplier)
        assertEquals(2.0, input.categoryAdvantageMultiplier)
    }

    @Test
    fun theUnverifiedMultiplierIsReadFromTheInput() {
        val base = passingInput().copy(
            merchantConfidence = AmbientMerchantConfidence.BRAND_MATCHED,
            advantage = AmbientAdvantage(percentagePoints = 1.0, cad = 1.0)
        )
        assertEquals(
            setOf(AmbientSuppressionReason.ADVANTAGE_BELOW_UNVERIFIED_THRESHOLD),
            AmbientGate.evaluate(base).suppressionReasons
        )
        assertTrue(AmbientGate.evaluate(base.copy(unverifiedAdvantageMultiplier = 1.0)).fires)
    }

    @Test
    fun theFrequentedMultiplierIsReadFromTheInput() {
        val base = passingInput().copy(
            merchantConfidence = AmbientMerchantConfidence.FREQUENTED,
            advantage = AmbientAdvantage(percentagePoints = 1.0, cad = 1.0)
        )
        assertTrue(AmbientGate.evaluate(base).fires)
        assertEquals(
            setOf(AmbientSuppressionReason.ADVANTAGE_BELOW_FREQUENTED_THRESHOLD),
            AmbientGate.evaluate(base.copy(frequentedAdvantageMultiplier = 2.0)).suppressionReasons
        )
    }

    @Test
    fun theCategoryMultiplierIsReadFromTheInput() {
        val base = passingInput().copy(
            merchantConfidence = AmbientMerchantConfidence.CATEGORY_MATCHED,
            advantage = AmbientAdvantage(percentagePoints = 1.0, cad = 1.0)
        )
        assertEquals(
            setOf(AmbientSuppressionReason.ADVANTAGE_BELOW_CATEGORY_THRESHOLD),
            AmbientGate.evaluate(base).suppressionReasons
        )
        assertTrue(AmbientGate.evaluate(base.copy(categoryAdvantageMultiplier = 1.0)).fires)
    }

    /** Each multiplier reaches exactly its own tier; the verified tier is never scaled. */
    @Test
    fun eachMultiplierReachesOnlyItsOwnTier() {
        val input = passingInput().copy(
            advantage = AmbientAdvantage(percentagePoints = 1.0, cad = 1.0),
            unverifiedAdvantageMultiplier = 100.0,
            frequentedAdvantageMultiplier = 100.0,
            categoryAdvantageMultiplier = 100.0
        )
        assertTrue(AmbientGate.evaluate(input).fires)
    }
}
