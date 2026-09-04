package com.cardcopilot.store

import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.engine.models.CategoryTaxonomy
import com.cardcopilot.store.db.CardCopilotDatabase
import com.cardcopilot.store.db.PredictionRecord
import com.cardcopilot.store.db.StoredMerchantEntity
import com.cardcopilot.store.db.StoredObservationEntity
import com.cardcopilot.store.db.StoredPredictionEntity
import com.cardcopilot.store.db.StoredPurchaseEntity
import com.cardcopilot.store.models.CaptureSource
import com.cardcopilot.store.models.ConfidenceSource
import com.cardcopilot.store.models.MissClass
import com.cardcopilot.store.models.NearbyPlace
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlin.math.abs

enum class ArithmeticVerdict {
    NOT_ELIGIBLE,
    MATCHES,
    MISMATCH
}

data class ExperimentMetrics(
    val confirmedCount: Int,
    val categoryCorrectCount: Int,
    val missBreakdown: Map<MissClass, Int>,
    val targetCheckouts: Int = TARGET_CHECKOUTS,
    val arithmeticEligibleCount: Int,
    val arithmeticCorrectCount: Int
) {
    val categoryAccuracy: Double?
        get() = if (confirmedCount > 0) categoryCorrectCount.toDouble() / confirmedCount else null

    val arithmeticCorrectRate: Double?
        get() = if (arithmeticEligibleCount > 0) arithmeticCorrectCount.toDouble() / arithmeticEligibleCount else null

    val progressToTarget: Int get() = confirmedCount
    val meetsCategoryBar: Boolean? get() = categoryAccuracy?.let { it >= 0.85 }
    val meetsArithmeticBar: Boolean? get() = arithmeticCorrectRate?.let { it == 1.0 }

    companion object {
        const val TARGET_CHECKOUTS = 30

        val EMPTY = ExperimentMetrics(
            confirmedCount = 0,
            categoryCorrectCount = 0,
            missBreakdown = emptyMap(),
            targetCheckouts = TARGET_CHECKOUTS,
            arithmeticEligibleCount = 0,
            arithmeticCorrectCount = 0
        )
    }
}

data class ValueRecovered(
    val confirmedAdvantageCad: Double,
    val pendingAdvantageCad: Double
)

class PredictionLogRepository(private val db: CardCopilotDatabase) {

    fun observeAllRecords(): Flow<List<PredictionRecord>> = db.predictionDao().observeAllRecords()

    suspend fun recordPrediction(
        merchant: NearbyPlace,
        predictedCategory: String,
        confidenceSource: ConfidenceSource,
        recommendation: Recommendation,
        scoredAmountCad: Double?,
        valuationCentsPerPoint: Double?,
        headline: String,
        initialPurchase: StoredPurchaseEntity? = null
    ): StoredPredictionEntity {
        val prediction = StoredPredictionEntity(
            merchantName = merchant.name,
            merchantIdentifier = merchant.id,
            predictedCategory = CategoryTaxonomy.canonicalId(predictedCategory),
            confidenceSourceRaw = confidenceSource.rawValue,
            winnerCardId = recommendation.winner.cardId,
            winnerValueCad = recommendation.winner.netValueCad,
            predictedRewardUnits = recommendation.winner.rewardUnits,
            predictedRewardUnitKind = if (recommendation.winner.appliedRuleId?.contains("point") == true) "point" else "cad",
            defaultCardValueCad = recommendation.allCandidates.firstOrNull { !it.excluded }?.netValueCad,
            winnerRuleId = recommendation.winner.appliedRuleId,
            runnerUpCardId = recommendation.runnerUp?.cardId,
            runnerUpValueCad = recommendation.runnerUp?.netValueCad,
            scoredAmountCad = scoredAmountCad,
            valuationCentsPerPoint = valuationCentsPerPoint,
            rawCategory = predictionRawCategory(merchant, predictedCategory),
            categoryTaxonomyVersion = CategoryTaxonomy.taxonomyVersion,
            categoryConfidenceScore = confidenceSource.defaultScore,
            merchantCategoryCode = merchant.merchantCategoryCode,
            merchantGroupID = CategoryTaxonomy.merchantGroupId(predictedCategory),
            headline = headline
        )

        db.predictionDao().insert(prediction)

        val purchase = initialPurchase ?: StoredPurchaseEntity(
            predictionId = prediction.id,
            rawCategoryAtPurchase = prediction.rawCategory,
            categoryTaxonomyVersion = prediction.categoryTaxonomyVersion,
            categoryConfidenceScore = prediction.categoryConfidenceScore,
            merchantCategoryCode = prediction.merchantCategoryCode,
            merchantGroupID = prediction.merchantGroupID
        )
        db.purchaseDao().insert(purchase)

        // Seed or update truth graph merchant node
        val existing = db.merchantDao().findByIdentifier(merchant.id)
            ?: db.merchantDao().findByName(merchant.name)
        if (existing == null) {
            db.merchantDao().insertOrUpdate(
                StoredMerchantEntity(
                    name = merchant.name,
                    identifier = merchant.id,
                    poiCategoryRaw = merchant.poiCategoryRaw,
                    latitude = merchant.latitude,
                    longitude = merchant.longitude,
                    rawCategory = merchant.poiCategoryRaw,
                    merchantCategoryCode = merchant.merchantCategoryCode
                )
            )
        }

        return prediction
    }

    suspend fun updatePurchase(
        purchaseId: String,
        cardUsedId: String? = null,
        cardSource: CaptureSource? = null,
        amountCad: Double? = null,
        amountSource: CaptureSource? = null
    ) {
        val purchase = db.purchaseDao().getById(purchaseId) ?: return
        if (cardUsedId != null) {
            purchase.cardUsedId = cardUsedId
            purchase.cardSourceRaw = cardSource?.rawValue
        }
        if (amountCad != null) {
            purchase.amountCad = amountCad
            purchase.amountSourceRaw = amountSource?.rawValue
        }
        if (purchase.cardUsedId != null && purchase.amountCad != null) {
            purchase.completedAt = System.currentTimeMillis()
        }
        db.purchaseDao().update(purchase)
    }

    suspend fun confirmObservation(
        purchaseId: String,
        observedCategory: String,
        observedRewardUnits: Double? = null,
        missClass: MissClass? = null,
        note: String? = null
    ) {
        val canonicalObservedCategory = CategoryTaxonomy.canonicalId(observedCategory)
        val obs = StoredObservationEntity(
            purchaseId = purchaseId,
            observedCategory = canonicalObservedCategory,
            observedRewardUnits = observedRewardUnits,
            missClassRaw = missClass?.rawValue,
            note = note,
            rawObservedCategory = observedCategory,
            categoryTaxonomyVersion = CategoryTaxonomy.taxonomyVersion,
            categorySourceRaw = ConfidenceSource.OWNER_CONFIRMED_TERMINAL.rawValue,
            categoryConfidenceScore = ConfidenceSource.OWNER_CONFIRMED_TERMINAL.defaultScore
        )
        db.observationDao().insert(obs)

        // Promote merchant in Truth Graph if category is confirmed
        val purchase = db.purchaseDao().getById(purchaseId) ?: return
        val prediction = db.predictionDao().getById(purchase.predictionId) ?: return
        val merchant = (prediction.merchantIdentifier?.let { db.merchantDao().findByIdentifier(it) }
            ?: db.merchantDao().findByName(prediction.merchantName)) ?: return

        merchant.confirmedCategory = canonicalObservedCategory
        merchant.confirmationCount += 1
        merchant.lastSeenAt = System.currentTimeMillis()
        merchant.rawCategory = observedCategory
        merchant.categoryTaxonomyVersion = CategoryTaxonomy.taxonomyVersion
        merchant.categoryConfidenceScore = if (merchant.confirmationCount >= 2) {
            ConfidenceSource.REPEATED_TERMINAL.defaultScore
        } else ConfidenceSource.OWNER_CONFIRMED_TERMINAL.defaultScore
        merchant.lastConfirmedAt = System.currentTimeMillis()
        db.merchantDao().insertOrUpdate(merchant)
    }

    private fun predictionRawCategory(merchant: NearbyPlace, predictedCategory: String): String? =
        merchant.poiCategoryRaw ?: predictedCategory

    fun observeMetrics(): Flow<ExperimentMetrics> {
        return observeAllRecords().map { computeMetrics(it) }
    }

    fun computeMetrics(records: List<PredictionRecord>): ExperimentMetrics {
        var confirmedCount = 0
        var categoryCorrectCount = 0
        val missBreakdown = mutableMapOf<MissClass, Int>()
        var arithmeticEligibleCount = 0
        var arithmeticCorrectCount = 0

        for (record in records) {
            val obs = record.purchaseWithObservation?.observation ?: continue
            confirmedCount += 1
            if (obs.missClassRaw == null) {
                categoryCorrectCount += 1
            } else {
                val miss = MissClass.fromRaw(obs.missClassRaw)
                if (miss != null) {
                    missBreakdown[miss] = (missBreakdown[miss] ?: 0) + 1
                }
            }

            val verdict = computeArithmeticVerdict(record)
            if (verdict != ArithmeticVerdict.NOT_ELIGIBLE) {
                arithmeticEligibleCount += 1
                if (verdict == ArithmeticVerdict.MATCHES) {
                    arithmeticCorrectCount += 1
                }
            }
        }

        return ExperimentMetrics(
            confirmedCount = confirmedCount,
            categoryCorrectCount = categoryCorrectCount,
            missBreakdown = missBreakdown,
            arithmeticEligibleCount = arithmeticEligibleCount,
            arithmeticCorrectCount = arithmeticCorrectCount
        )
    }

    fun computeArithmeticVerdict(record: PredictionRecord): ArithmeticVerdict {
        val purchase = record.purchaseWithObservation?.purchase ?: return ArithmeticVerdict.NOT_ELIGIBLE
        val obs = record.purchaseWithObservation?.observation ?: return ArithmeticVerdict.NOT_ELIGIBLE
        val prediction = record.prediction

        if (obs.observedCategory != prediction.predictedCategory) return ArithmeticVerdict.NOT_ELIGIBLE
        if (purchase.cardUsedId != prediction.winnerCardId) return ArithmeticVerdict.NOT_ELIGIBLE
        if (purchase.amountCad == null) return ArithmeticVerdict.NOT_ELIGIBLE

        val predicted = prediction.predictedRewardUnits ?: return ArithmeticVerdict.NOT_ELIGIBLE
        val observed = obs.observedRewardUnits ?: return ArithmeticVerdict.NOT_ELIGIBLE

        val tolerance = if (prediction.predictedRewardUnitKind == "point") 1.0 else 0.01
        return if (abs(predicted - observed) <= tolerance + 1e-9) ArithmeticVerdict.MATCHES else ArithmeticVerdict.MISMATCH
    }

    fun computeValueRecovered(records: List<PredictionRecord>): ValueRecovered {
        var confirmed = 0.0
        var pending = 0.0

        for (record in records) {
            val purchase = record.purchaseWithObservation?.purchase ?: continue
            val obs = record.purchaseWithObservation?.observation
            val prediction = record.prediction

            val defaultVal = prediction.defaultCardValueCad ?: 0.0
            val advantage = maxOf(0.0, prediction.winnerValueCad - defaultVal)
            if (purchase.cardUsedId == prediction.winnerCardId) {
                val actualAmount = purchase.amountCad ?: (prediction.scoredAmountCad ?: 0.0)
                val scoredAmount = prediction.scoredAmountCad ?: actualAmount
                val scaledAdvantage = if (scoredAmount > 0) advantage * (actualAmount / scoredAmount) else advantage

                if (obs != null) {
                    confirmed += scaledAdvantage
                } else {
                    pending += scaledAdvantage
                }
            }
        }

        return ValueRecovered(confirmedAdvantageCad = confirmed, pendingAdvantageCad = pending)
    }
}
