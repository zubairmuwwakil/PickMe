package com.cardcopilot.engine

import com.cardcopilot.engine.engine.PurchaseRouteAdvisor
import com.cardcopilot.engine.engine.PurchaseRouteCatalogue
import com.cardcopilot.engine.engine.PurchaseRouteEvidenceLevel
import com.cardcopilot.engine.engine.AlternativePurchaseRoute
import com.cardcopilot.engine.engine.PurchaseRouteVerdict
import com.cardcopilot.engine.engine.ProtectionDecisionStatus
import com.cardcopilot.engine.engine.RecommendationEngine
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.RecommendationOutcome
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PurchaseRouteAdvisorTest {
    private fun engine(): RecommendationEngine = RecommendationEngine(
        catalogue = SeedLoader.loadCatalogue(),
        ownerState = SeedLoader.loadOwnerState(),
        includeCheckoutCredits = false
    )

    @Test
    fun `shoppers route can beat direct payment`() {
        val engine = engine()
        val directContext = PurchaseContext(
            amountCad = 100.0,
            category = "drugStore",
            mcc = 5912,
            merchantBrand = "shoppers-drug-mart"
        )
        val direct = (engine.recommend(directContext, "2026-09-04") as RecommendationOutcome.Advised).recommendation

        val result = PurchaseRouteAdvisor.bestAlternative(
            directRecommendation = direct,
            destination = directContext,
            destinationMerchantName = "Shoppers Drug Mart",
            engine = engine,
            asOf = "2026-09-04"
        )

        assertNotNull(result)
        result!!
        assertEquals("shoppers-gift-card-via-grocery-5411", result.route.routeId)
        assertTrue(result.advantageCad >= 1.0)
        assertTrue(result.advantagePercentagePoints >= 1.0)
        assertEquals(PurchaseRouteEvidenceLevel.COMMUNITY_OBSERVED, result.route.evidenceLevel)
    }

    @Test
    fun `material gift card route keeps reward gain separate from protection tradeoff`() {
        val engine = engine()
        val benefits = SeedLoader.loadBenefitsCatalogue()
        val directContext = PurchaseContext(
            amountCad = 500.0,
            category = "drugStore",
            mcc = 5912,
            merchantBrand = "shoppers-drug-mart"
        )
        val direct = (engine.recommend(directContext, "2026-09-04") as RecommendationOutcome.Advised).recommendation

        val result = PurchaseRouteAdvisor.bestAlternative(
            directRecommendation = direct,
            destination = directContext,
            destinationMerchantName = "Shoppers Drug Mart",
            engine = engine,
            asOf = "2026-09-04",
            benefits = benefits
        )!!

        assertTrue(result.advantageCad > 0.0)
        assertEquals(PurchaseRouteVerdict.REWARD_PROTECTION_TRADEOFF, result.verdict)
        assertNotEquals(ProtectionDecisionStatus.NOT_RELEVANT, result.protectionAssessment.status)
        assertEquals(result.routeValueCad - result.directValueCad, result.advantageCad, 0.000001)
    }

    @Test
    fun `small purchase is suppressed by friction threshold`() {
        val engine = engine()
        val directContext = PurchaseContext(
            amountCad = 5.0,
            category = "drugStore",
            mcc = 5912,
            merchantBrand = "shoppers-drug-mart"
        )
        val direct = (engine.recommend(directContext, "2026-09-04") as RecommendationOutcome.Advised).recommendation

        assertNull(PurchaseRouteAdvisor.bestAlternative(
            directRecommendation = direct,
            destination = directContext,
            destinationMerchantName = "Shoppers Drug Mart",
            engine = engine,
            asOf = "2026-09-04"
        ))
    }

    @Test
    fun `route does not leak to other drugstores`() {
        val engine = engine()
        val directContext = PurchaseContext(
            amountCad = 100.0,
            category = "drugStore",
            mcc = 5912,
            merchantBrand = "rexall"
        )
        val direct = (engine.recommend(directContext, "2026-09-04") as RecommendationOutcome.Advised).recommendation

        assertNull(PurchaseRouteAdvisor.bestAlternative(
            directRecommendation = direct,
            destination = directContext,
            destinationMerchantName = "Rexall",
            engine = engine,
            asOf = "2026-09-04"
        ))
    }

    @Test
    fun `merchant matching ignores case and punctuation`() {
        val route = PurchaseRouteCatalogue.canadaV1[0]
        assertTrue(route.matches("SHOPPERS DRUG MART #1234"))
        assertTrue(route.matches("Pharmaprix - Montreal"))
        assertFalse(route.matches("Rexall Pharmacy"))
    }

    @Test
    fun `equal reward routes use stable route id tie break`() {
        val engine = engine()
        val directContext = PurchaseContext(
            amountCad = 100.0,
            category = "drugStore",
            mcc = 5912,
            merchantBrand = "shoppers-drug-mart"
        )
        val direct = (engine.recommend(directContext, "2026-09-04") as RecommendationOutcome.Advised).recommendation
        fun route(routeId: String) = AlternativePurchaseRoute(
            routeId = routeId,
            destinationMerchantAliases = listOf("Shoppers"),
            instrumentLabel = "Test gift card",
            acquisitionMerchantLabel = "Test grocery store",
            acquisitionCategory = "grocery",
            acquisitionMcc = 5411,
            evidenceLevel = PurchaseRouteEvidenceLevel.EXPERIMENTAL,
            disclosure = "Test only"
        )

        val result = PurchaseRouteAdvisor.bestAlternative(
            directRecommendation = direct,
            destination = directContext,
            destinationMerchantName = "Shoppers Drug Mart",
            routes = listOf(route("z-route"), route("a-route")),
            engine = engine,
            asOf = "2026-09-04"
        )

        assertEquals("a-route", result?.route?.routeId)
    }
}
