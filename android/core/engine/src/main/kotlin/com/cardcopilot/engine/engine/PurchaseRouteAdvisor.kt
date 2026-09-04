package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.Network
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.engine.models.RecommendationOutcome

enum class PurchaseRouteEvidenceLevel {
    RETAILER_CONFIRMED,
    COMMUNITY_OBSERVED,
    EXPERIMENTAL
}

data class AlternativePurchaseRoute(
    val routeId: String,
    val destinationMerchantAliases: List<String>,
    val instrumentLabel: String,
    val acquisitionMerchantLabel: String,
    val acquisitionCategory: String,
    val acquisitionMcc: Int? = null,
    val acquisitionMerchantBrand: String? = null,
    val acceptedNetworks: Set<Network> = setOf(Network.AMEX, Network.VISA, Network.MASTERCARD),
    val fixedFeeCad: Double = 0.0,
    val estimatedFrictionCad: Double = 0.0,
    val evidenceLevel: PurchaseRouteEvidenceLevel,
    val disclosure: String
) {
    fun matches(destinationMerchantName: String): Boolean {
        val merchant = normalized(destinationMerchantName)
        return destinationMerchantAliases.any { alias ->
            val candidate = normalized(alias)
            candidate.isNotEmpty() && merchant.contains(candidate)
        }
    }

    private fun normalized(value: String): String =
        value.lowercase()
            .replace(Regex("[^a-z0-9]+"), " ")
            .trim()
}

data class PurchaseRouteThreshold(
    val minAdvantageCad: Double = 1.0,
    val minAdvantagePercentagePoints: Double = 1.0
) {
    companion object {
        val SHIPPED = PurchaseRouteThreshold()
    }
}

data class PurchaseRouteEvaluation(
    val route: AlternativePurchaseRoute,
    val acquisitionRecommendation: Recommendation,
    val directValueCad: Double,
    val routeValueCad: Double,
    val advantageCad: Double,
    val advantagePercentagePoints: Double
)

object PurchaseRouteAdvisor {
    fun bestAlternative(
        directRecommendation: Recommendation,
        destination: PurchaseContext,
        destinationMerchantName: String,
        routes: List<AlternativePurchaseRoute> = PurchaseRouteCatalogue.canadaV1,
        engine: RecommendationEngine,
        asOf: String,
        threshold: PurchaseRouteThreshold = PurchaseRouteThreshold.SHIPPED
    ): PurchaseRouteEvaluation? {
        if (destination.amountCad <= 0.0) return null

        val directValue = directRecommendation.winner.decisionValueCad
        val eligible = mutableListOf<PurchaseRouteEvaluation>()

        for (route in routes) {
            if (!route.matches(destinationMerchantName)) continue

            val acquisition = PurchaseContext(
                amountCad = destination.amountCad,
                currency = destination.currency,
                usdEquivalent = destination.usdEquivalent,
                category = route.acquisitionCategory,
                mcc = route.acquisitionMcc,
                merchantBrand = route.acquisitionMerchantBrand,
                country = destination.country,
                channel = "cardPresent",
                recurringIndicator = false,
                acceptedNetworks = route.acceptedNetworks
            )

            val outcome = engine.recommend(acquisition, asOf)
            val recommendation = (outcome as? RecommendationOutcome.Advised)?.recommendation ?: continue
            val routeValue = recommendation.winner.decisionValueCad -
                route.fixedFeeCad - route.estimatedFrictionCad
            val advantage = routeValue - directValue
            val advantagePP = advantage / destination.amountCad * 100.0

            if (advantage < threshold.minAdvantageCad ||
                advantagePP < threshold.minAdvantagePercentagePoints
            ) continue

            eligible += PurchaseRouteEvaluation(
                route = route,
                acquisitionRecommendation = recommendation,
                directValueCad = directValue,
                routeValueCad = routeValue,
                advantageCad = advantage,
                advantagePercentagePoints = advantagePP
            )
        }

        return eligible.maxByOrNull { it.advantageCad }
    }
}

object PurchaseRouteCatalogue {
    val canadaV1: List<AlternativePurchaseRoute> = listOf(
        AlternativePurchaseRoute(
            routeId = "shoppers-gift-card-via-grocery-5411",
            destinationMerchantAliases = listOf("Shoppers Drug Mart", "Shoppers", "Pharmaprix"),
            instrumentLabel = "Shoppers Drug Mart gift card",
            acquisitionMerchantLabel = "an eligible grocery store that codes as MCC 5411",
            acquisitionCategory = "grocery",
            acquisitionMcc = 5411,
            evidenceLevel = PurchaseRouteEvidenceLevel.COMMUNITY_OBSERVED,
            disclosure = "Gift-card inventory and issuer reward treatment can vary by store and transaction. Confirm availability before relying on this route."
        )
    )
}
