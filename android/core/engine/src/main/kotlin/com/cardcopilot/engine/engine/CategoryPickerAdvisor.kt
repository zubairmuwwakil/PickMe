package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.engine.models.SpendDistribution
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

data class AmountBand(
    val lowerBoundCad: Double,
    val upperBoundCad: Double?,
    val cardId: String,
    val recommendation: Recommendation
)

object CategoryPickerAdvisor {
    data class CuratedEntry(
        val category: String,
        val reason: String
    )

    val curatedCategories: List<CuratedEntry> = listOf(
        CuratedEntry(
            category = "other",
            reason = "The catch-all for unaccelerated spend — every wallet needs an answer for 'nothing special applies here,' even though no earnRule predicate names it."
        ),
        CuratedEntry(
            category = "wholesaleClub",
            reason = "Costco's winner is decided by its Mastercard-only acceptance gate, not an accelerator — no earnRule predicate lists this category."
        )
    )

    val excludedCategories: List<CuratedEntry> = listOf(
        CuratedEntry(
            category = "ownerSelectedTangerineCategory",
            reason = "Placeholder for whichever categories the owner picked on Tangerine — a rule condition RuleMatcher resolves against the owner's selections, not a category any statement shows."
        )
    )

    fun acceleratedVocabulary(catalogue: Catalogue): Set<String> {
        return catalogue.cards.flatMap { it.earnRules }.mapNotNull { it.predicate.categories }.flatten().toSet()
    }

    fun derivedCategories(catalogue: Catalogue): List<String> {
        val curated = curatedCategories.map { it.category }.toSet()
        val excluded = excludedCategories.map { it.category }.toSet()
        return (acceleratedVocabulary(catalogue) + curated - excluded).sorted()
    }

    val curatedLabels: Map<String, String> = mapOf(
        "ctFamily" to "Canadian Tire family",
        "marriottDirect" to "Marriott direct",
        "other" to "General merchandise",
        "evCharging" to "EV charging"
    )

    fun label(
        category: String,
        distribution: SpendDistribution = SpendDistribution.placeholderCanadianHousehold
    ): String {
        val bucket = matchingBucket(category, distribution)
        if (bucket != null) return bucket.label
        val curated = curatedLabels[category]
        if (curated != null) return curated
        return humanize(category)
    }

    fun humanize(category: String): String {
        if (category.isEmpty()) return category
        val sb = StringBuilder()
        for (ch in category) {
            if (ch.isUpperCase() && sb.isNotEmpty()) {
                sb.append(' ')
            }
            sb.append(ch)
        }
        val s = sb.toString()
        return s.take(1).uppercase() + s.drop(1).lowercase()
    }

    fun enrichedTemplate(
        category: String,
        distribution: SpendDistribution = SpendDistribution.placeholderCanadianHousehold
    ): PurchaseContext {
        val bucket = matchingBucket(category, distribution)
        if (bucket != null) return bucket.context
        return PurchaseContext(amountCad = 1.0, category = category)
    }

    private fun matchingBucket(
        category: String,
        distribution: SpendDistribution
    ): SpendDistribution.Bucket? {
        if (category == "other") return null
        return distribution.buckets.firstOrNull { it.context.category == category }
    }

    fun bands(
        category: String,
        catalogue: Catalogue,
        ownerState: OwnerState,
        distribution: SpendDistribution = SpendDistribution.placeholderCanadianHousehold,
        asOf: String
    ): List<AmountBand> {
        val engine = RecommendationEngine(catalogue, ownerState)
        val template = enrichedTemplate(category, distribution)

        fun recommendation(cents: Int): Recommendation {
            val context = template.copy(amountCad = cents.toDouble() / 100.0)
            return engine.recommend(context, asOf)
        }

        val sweepMaxCad = sweepCeilingCad(catalogue)
        val boundaryCents = detectBoundaryCents({ recommendation(it) }, sweepMaxCad)

        if (boundaryCents.isEmpty()) {
            val rec = recommendation(100)
            return listOf(
                AmountBand(
                    lowerBoundCad = 0.0,
                    upperBoundCad = null,
                    cardId = rec.winner.cardId,
                    recommendation = rec
                )
            )
        }

        val result = mutableListOf<AmountBand>()
        var lowerCents = 0
        for (boundaryCentsValue in boundaryCents) {
            val representativeCents = lowerCents + maxOf(1, (boundaryCentsValue - lowerCents) / 2)
            val rec = recommendation(representativeCents)
            result.add(
                AmountBand(
                    lowerBoundCad = lowerCents.toDouble() / 100.0,
                    upperBoundCad = boundaryCentsValue.toDouble() / 100.0,
                    cardId = rec.winner.cardId,
                    recommendation = rec
                )
            )
            lowerCents = boundaryCentsValue
        }

        val finalCents = maxOf(lowerCents + 1, (sweepMaxCad * 100.0).roundToInt())
        val finalRec = recommendation(finalCents)
        result.add(
            AmountBand(
                lowerBoundCad = lowerCents.toDouble() / 100.0,
                upperBoundCad = null,
                cardId = finalRec.winner.cardId,
                recommendation = finalRec
            )
        )
        return result
    }

    fun detectBoundaryCents(
        recommendation: (Int) -> Recommendation,
        sweepMaxCad: Double
    ): List<Int> {
        val sweepMaxCents = maxOf((sweepMaxCad * 100.0).roundToInt(), 100)
        val minCents = 1
        val sampleCount = 600
        val ratio = sweepMaxCents.toDouble() / minCents.toDouble()

        data class Sample(val cents: Int, val cardId: String)
        val samples = ArrayList<Sample>(sampleCount + 1)
        for (i in 0..sampleCount) {
            val t = i.toDouble() / sampleCount.toDouble()
            val cents = maxOf(minCents, (minCents.toDouble() * ratio.pow(t)).roundToInt())
            samples.add(Sample(cents, recommendation(cents).winner.cardId))
        }

        val boundaries = mutableListOf<Int>()
        for (i in 1 until samples.size) {
            if (!isSameRegime(samples[i - 1].cardId, samples[i].cents, recommendation)) {
                val boundary = binarySearchBoundaryCents(
                    lowCents = samples[i - 1].cents,
                    lowCardId = samples[i - 1].cardId,
                    highCents = samples[i].cents,
                    recommendation = recommendation
                )
                boundaries.add(boundary)
            }
        }

        val sorted = boundaries.sorted()
        val deduped = mutableListOf<Int>()
        for (b in sorted) {
            if (deduped.isEmpty() || deduped.last() != b) {
                deduped.add(b)
            }
        }
        return deduped
    }

    fun binarySearchBoundaryCents(
        lowCents: Int,
        lowCardId: String,
        highCents: Int,
        recommendation: (Int) -> Recommendation
    ): Int {
        var lo = lowCents
        var hi = highCents
        while (hi - lo > 1) {
            val mid = lo + (hi - lo) / 2
            if (isSameRegime(lowCardId, mid, recommendation)) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return hi
    }

    const val REGIME_TOLERANCE_CAD = 0.000001

    fun isSameRegime(
        cardId: String,
        cents: Int,
        recommendation: (Int) -> Recommendation
    ): Boolean {
        val rec = recommendation(cents)
        if (rec.winner.cardId == cardId) return true
        val candidate = rec.allCandidates.firstOrNull { it.cardId == cardId } ?: return false
        if (candidate.excluded) return false
        return abs(candidate.netValueCad - rec.winner.netValueCad) < REGIME_TOLERANCE_CAD
    }

    fun sweepCeilingCad(catalogue: Catalogue): Double {
        val largestCapLimit = catalogue.cards.flatMap { it.caps }.map { it.limit }.maxOrNull() ?: 0.0
        return maxOf(largestCapLimit, 1000.0) * 1.5
    }
}
