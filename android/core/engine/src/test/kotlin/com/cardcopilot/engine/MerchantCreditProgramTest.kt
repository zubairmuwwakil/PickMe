package com.cardcopilot.engine

import com.cardcopilot.engine.engine.Scorer
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.MerchantCreditValuation
import com.cardcopilot.engine.models.Valuations
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class MerchantCreditProgramTest {

    @Test
    fun `face value applies when the usability factor is not applied`() {
        val v = MerchantCreditValuation(
            cadPerUnit = 1.0, optionalUsabilityFactor = 0.8,
            usabilityFactorApplied = false, merchantScope = listOf("gap"), basis = "test")
        val cad = requireNotNull(
            Scorer.valueCad(100.0, "gapInc", Valuations(mapOf("gapInc" to v)), CardState()))
        assertEquals(100.0, cad, 0.0001)
    }

    @Test
    fun `usability factor discounts a merchant-locked dollar`() {
        val v = MerchantCreditValuation(
            cadPerUnit = 1.0, optionalUsabilityFactor = 0.8,
            usabilityFactorApplied = true, merchantScope = listOf("gap"), basis = "test")
        val cad = requireNotNull(
            Scorer.valueCad(100.0, "gapInc", Valuations(mapOf("gapInc" to v)), CardState()))
        assertEquals(80.0, cad, 0.0001)
    }
}
