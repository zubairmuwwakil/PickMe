package com.cardcopilot.store

import com.cardcopilot.engine.engine.Explanation
import com.cardcopilot.engine.engine.RecommendationEngine
import com.cardcopilot.engine.engine.RecommendationExplainer
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.store.models.CategoryPrediction
import com.cardcopilot.store.models.ConfidenceSource
import com.cardcopilot.store.models.NearbyMerchant

data class CheckoutBranch(
    val category: String,
    val recommendation: Recommendation
)

sealed interface CheckoutOutcome {
    data class Single(val recommendation: Recommendation) : CheckoutOutcome
    data class Fork(val branches: List<CheckoutBranch>) : CheckoutOutcome
}

data class CheckoutResult(
    val merchant: NearbyMerchant,
    val prediction: CategoryPrediction,
    val scoredContext: PurchaseContext,
    val outcome: CheckoutOutcome,
    val primaryRecommendation: Recommendation,
    val explanation: Explanation
)

class CheckoutService(
    val catalogue: Catalogue,
    val ownerState: OwnerState
) {
    private val engine = RecommendationEngine(catalogue, ownerState)
    private val explainer = RecommendationExplainer(catalogue)

    fun evaluate(
        merchant: NearbyMerchant,
        userAmountCad: Double? = null,
        overrideCategory: String? = null,
        asOf: String
    ): CheckoutResult {
        val prediction: CategoryPrediction = if (overrideCategory != null) {
            CategoryPrediction(
                category = overrideCategory,
                confidenceSource = ConfidenceSource.OWNER_CONFIRMED_TERMINAL,
                candidates = listOf(overrideCategory)
            )
        } else {
            CategoryMapper.predict(merchant.poiCategoryRaw, merchant.name)
        }

        val brand = CategoryMapper.canonicalEngineBrand(merchant.name)
        val networks = CategoryMapper.knownAcceptedNetworks(brand)
        val amount = userAmountCad
            ?: (CategoryMapper.categoryAmountEstimates[prediction.category] ?: CategoryMapper.FALLBACK_AMOUNT_ESTIMATE)

        val primaryContext = PurchaseContext(
            amountCad = amount,
            category = prediction.category,
            merchantBrand = brand,
            acceptedNetworks = networks
        )

        if (prediction.candidates.size <= 1) {
            val rec = engine.recommend(primaryContext, asOf)
            val explanation = explainer.explain(rec, primaryContext)
            return CheckoutResult(
                merchant = merchant,
                prediction = prediction,
                scoredContext = primaryContext,
                outcome = CheckoutOutcome.Single(rec),
                primaryRecommendation = rec,
                explanation = explanation
            )
        }

        val branches = prediction.candidates.map { cat ->
            val branchContext = primaryContext.copy(
                category = cat,
                amountCad = userAmountCad ?: (CategoryMapper.categoryAmountEstimates[cat] ?: CategoryMapper.FALLBACK_AMOUNT_ESTIMATE)
            )
            CheckoutBranch(
                category = cat,
                recommendation = engine.recommend(branchContext, asOf)
            )
        }

        val primaryRec = branches.first().recommendation
        val explanation = explainer.explain(primaryRec, primaryContext)

        return CheckoutResult(
            merchant = merchant,
            prediction = prediction,
            scoredContext = primaryContext,
            outcome = CheckoutOutcome.Fork(branches),
            primaryRecommendation = primaryRec,
            explanation = explanation
        )
    }
}
