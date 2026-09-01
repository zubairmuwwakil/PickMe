package com.cardcopilot.engine

import com.cardcopilot.engine.engine.AmbientAdvantage
import com.cardcopilot.engine.engine.AmbientDeliveryTier
import com.cardcopilot.engine.engine.AmbientGate
import com.cardcopilot.engine.engine.AmbientGateInput
import com.cardcopilot.engine.engine.AmbientMerchantConfidence
import com.cardcopilot.engine.models.SwitchThreshold
import org.junit.jupiter.api.Assertions.assertEquals
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
}
