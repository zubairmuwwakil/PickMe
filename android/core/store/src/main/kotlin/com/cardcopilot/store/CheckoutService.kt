package com.cardcopilot.store

import com.cardcopilot.engine.engine.Explanation
import com.cardcopilot.engine.engine.RecommendationEngine
import com.cardcopilot.engine.engine.RecommendationExplainer
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.engine.models.RecommendationOutcome
import com.cardcopilot.store.models.CategoryPrediction
import com.cardcopilot.store.models.ConfidenceSource
import com.cardcopilot.store.models.NearbyPlace

data class CheckoutBranch(
    val category: String,
    val recommendation: Recommendation
)

/**
 * The engine declined to advise, with the per-card reasons it gave. Checkout has no honest
 * fallback here — a card the engine cannot value is not a card it can rank — so this surfaces
 * rather than degrading to a $0.00 winner. The Kotlin twin of Swift's `CheckoutError`.
 */
class CannotAdviseException(val reasons: List<String>) :
    Exception("cannot advise: ${reasons.joinToString("; ")}")

sealed interface CheckoutOutcome {
    data class Single(val recommendation: Recommendation) : CheckoutOutcome
    data class Fork(val branches: List<CheckoutBranch>) : CheckoutOutcome
}

data class CheckoutResult(
    val merchant: NearbyPlace,
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
        merchant: NearbyPlace,
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

        fun recommend(context: PurchaseContext): Recommendation =
            when (val outcome = engine.recommend(context, asOf)) {
                is RecommendationOutcome.Advised -> outcome.recommendation
                is RecommendationOutcome.CannotAdvise -> throw CannotAdviseException(outcome.reasons)
            }

        if (prediction.candidates.size <= 1) {
            val rec = recommend(primaryContext)
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
                recommendation = recommend(branchContext)
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
