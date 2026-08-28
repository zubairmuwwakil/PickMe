package com.cardcopilot.engine

import com.cardcopilot.engine.engine.RuleMatcher
import com.cardcopilot.engine.engine.RuleResolution
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.PurchaseContext
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Kotlin twin of `OwnerConditionRegistryTests`. Both engines must agree exactly, or the shared
 * contracts/engine-fixtures.json gate reports what is really a parity bug as a scoring difference.
 */
class OwnerConditionTest {

    @Test
    fun `any declared condition resolves from flags`() {
        val state = CardState(flags = mapOf("amazonEligiblePrimeLinked" to true))
        assertTrue(RuleMatcher.conditionsResolveTrue(listOf("amazonEligiblePrimeLinked"), state))
    }

    @Test
    fun `unanswered condition fails closed`() {
        assertFalse(RuleMatcher.conditionsResolveTrue(listOf("amazonEligiblePrimeLinked"), CardState()))
    }

    @Test
    fun `amazon prime unanswered falls to non-prime rule`() {
        val card = requireNotNull(SeedLoader.loadCatalogue().cards
            .firstOrNull { it.cardId == "amazon-ca-rewards-mastercard" })
        val purchase = PurchaseContext(
            amountCad = 100.0,
            category = "other",
            merchantBrand = "amazon-ca",
            channel = "online"
        )
        val resolution = RuleMatcher.resolve(
            card,
            purchase,
            SeedLoader.loadOwnerState(),
            "2026-08-20"
        ) as? RuleResolution.Applied

        assertEquals(
            "amazon-ca-nonprime-1_5x",
            resolution?.rule?.ruleId,
            "unanswered Prime must fail closed without suppressing the 1.5x fallback"
        )
    }

    @Test
    fun `explicit no fails closed`() {
        val state = CardState(flags = mapOf("rogersEligibleServiceLinked" to false))
        assertFalse(RuleMatcher.conditionsResolveTrue(listOf("rogersEligibleServiceLinked"), state))
    }

    @Test
    fun `legacy named booleans fold into resolved flags`() {
        val state = CardState(rogersEligibleServiceLinked = true)
        assertEquals(true, state.resolvedFlags["rogersEligibleServiceLinked"])
        assertTrue(RuleMatcher.conditionsResolveTrue(listOf("rogersEligibleServiceLinked"), state))
    }

    @Test
    fun `flags win over a stale mirrored legacy key`() {
        val state = CardState(
            rogersEligibleServiceLinked = false,
            flags = mapOf("rogersEligibleServiceLinked" to true)
        )
        assertEquals(true, state.resolvedFlags["rogersEligibleServiceLinked"])
    }

    @Test
    fun `unanswered condition is absent not false`() {
        assertNull(CardState().resolvedFlags["rogersEligibleServiceLinked"])
    }

    @Test
    fun `tangerine stays on its structural field`() {
        val state = CardState(selectedCategories = listOf("grocery"))
        assertTrue(RuleMatcher.conditionsResolveTrue(listOf("tangerineCategorySelected"), state))
        assertFalse(RuleMatcher.conditionsResolveTrue(listOf("tangerineCategorySelected"), CardState()))
    }

    @Test
    fun `all conditions must hold together`() {
        val state = CardState(flags = mapOf("rogersEligibleServiceLinked" to true))
        assertFalse(
            RuleMatcher.conditionsResolveTrue(
                listOf("rogersEligibleServiceLinked", "amazonEligiblePrimeLinked"), state
            )
        )
    }

    @Test
    fun `unknown condition fails closed`() {
        val state = CardState(flags = mapOf("somethingElse" to true))
        assertFalse(RuleMatcher.conditionsResolveTrue(listOf("neverDeclaredAnywhere"), state))
    }

    @Test
    fun `null conditions list matches`() {
        assertTrue(RuleMatcher.conditionsResolveTrue(null, CardState()))
    }
}
