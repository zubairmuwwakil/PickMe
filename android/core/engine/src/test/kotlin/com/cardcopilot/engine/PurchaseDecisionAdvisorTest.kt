package com.cardcopilot.engine

import com.cardcopilot.engine.engine.BenefitContext
import com.cardcopilot.engine.engine.BenefitContextKind
import com.cardcopilot.engine.engine.PurchaseDecisionAdvisor
import com.cardcopilot.engine.engine.PurchaseDecisionVerdict
import com.cardcopilot.engine.engine.RecommendationEngine
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.BenefitKind
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.engine.models.RecommendationOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PurchaseDecisionAdvisorTest {
    private data class Fixture(
        val recommendation: Recommendation,
        val purchase: PurchaseContext,
        val ownerCardIds: List<String>
    )

    private fun fixture(amountCad: Double): Fixture {
        val catalogue = SeedLoader.loadCatalogue()
        val owner = SeedLoader.loadOwnerState()
        val engine = RecommendationEngine(catalogue, owner)
        val purchase = PurchaseContext(amountCad = amountCad, category = "retailShopping")
        val recommendation = (engine.recommend(purchase, "2026-09-04") as RecommendationOutcome.Advised).recommendation
        return Fixture(recommendation, purchase, owner.ownedCardIds)
    }

    @Test
    fun `small purchase stays reward only`() {
        val fixture = fixture(50.0)
        val result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation = fixture.recommendation,
            purchase = fixture.purchase,
            wallet = fixture.ownerCardIds,
            benefits = SeedLoader.loadBenefitsCatalogue()
        )

        assertEquals(PurchaseDecisionVerdict.REWARD_LEADER, result.verdict)
        assertEquals("conservative-multi-attribute-v1", result.policyVersion)
    }

    @Test
    fun `material purchase requests item context instead of inferring from merchant`() {
        val fixture = fixture(500.0)
        val result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation = fixture.recommendation,
            purchase = fixture.purchase,
            wallet = fixture.ownerCardIds,
            benefits = SeedLoader.loadBenefitsCatalogue()
        )

        assertEquals(PurchaseDecisionVerdict.PURCHASE_CONTEXT_NEEDED, result.verdict)
        assertFalse(result.relevantKinds.isEmpty())
    }

    @Test
    fun `declared electronics context produces protection decision`() {
        val fixture = fixture(500.0)
        val result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation = fixture.recommendation,
            purchase = fixture.purchase,
            wallet = fixture.ownerCardIds,
            benefits = SeedLoader.loadBenefitsCatalogue(),
            declaredContext = BenefitContext(BenefitContextKind.ELECTRONICS)
        )

        assertNotEquals(PurchaseDecisionVerdict.PURCHASE_CONTEXT_NEEDED, result.verdict)
        assertTrue(result.relevantKinds.contains(BenefitKind.PURCHASE_PROTECTION))
        assertTrue(result.relevantKinds.contains(BenefitKind.EXTENDED_WARRANTY))
    }

    @Test
    fun `declared other context means known no modelled protection context`() {
        val fixture = fixture(500.0)
        val context = BenefitContext(BenefitContextKind.OTHER)

        assertTrue(context.relevantKinds.isEmpty())

        val result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation = fixture.recommendation,
            purchase = fixture.purchase,
            wallet = fixture.ownerCardIds,
            benefits = SeedLoader.loadBenefitsCatalogue(),
            declaredContext = context
        )

        assertEquals(PurchaseDecisionVerdict.REWARD_LEADER, result.verdict)
        assertTrue(result.relevantKinds.isEmpty())
    }
}
