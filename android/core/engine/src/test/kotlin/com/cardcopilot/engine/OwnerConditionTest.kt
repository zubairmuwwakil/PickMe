package com.cardcopilot.engine

import com.cardcopilot.engine.engine.RuleMatcher
import com.cardcopilot.engine.models.CardState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

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
