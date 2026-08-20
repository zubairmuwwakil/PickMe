package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CandidateScore
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Recommendation
import com.cardcopilot.engine.models.ValuationDirection
import kotlin.math.abs

class RecommendationEngine(
    val catalogue: Catalogue,
    val ownerState: OwnerState
) {
    private data class Verdict(
        val winner: CandidateScore,
        val runnerUp: CandidateScore?,
        val switched: Boolean,
        val advantage: Double?,
        val defaultNotAccepted: Boolean,
        val suppressed: CandidateScore?,
        val ranked: List<CandidateScore>
    )

    fun recommend(purchase: PurchaseContext, asOf: String): Recommendation {
        val candidateCards = if (ownerState.ownedCardIds.isEmpty()) {
            catalogue.cards
        } else {
            val ownedSet = ownerState.ownedCardIds.toSet()
            catalogue.cards.filter { ownedSet.contains(it.cardId) }
        }
        val scores = candidateCards
            .map { Scorer.score(it, purchase, ownerState, asOf) }
            .filter { !it.excluded }
        check(scores.isNotEmpty()) { "no scorable card — catalogue misconfigured" }

        val declared = rank(scores, purchase) { it.netValueCad }
        val floor = rank(scores, purchase) { it.floorNetValueCad }
        val aspirational = rank(scores, purchase) { it.aspirationalNetValueCad }

        var sensitive = false
        var direction: ValuationDirection? = null
        var alternateId: String? = null
        var breakeven: Double? = null
        var declaredCents: Double? = null

        if (declared.winner.cardId != floor.winner.cardId &&
            abs(declared.winner.floorNetValueCad - declared.winner.netValueCad) > 0.0001 &&
            declared.winner.rewardUnits > 0
        ) {
            sensitive = true
            direction = ValuationDirection.BELOW
            alternateId = floor.winner.cardId
            breakeven = breakevenCents(
                pointsCard = declared.winner,
                incumbent = floor.winner,
                ranked = declared.ranked,
                purchase = purchase
            )
            declaredCents = centsPerUnit(declared.winner)
        } else if (aspirational.winner.cardId != declared.winner.cardId &&
            aspirational.winner.rewardUnits > 0 &&
            abs(aspirational.winner.aspirationalNetValueCad - aspirational.winner.netValueCad) > 0.0001
        ) {
            val challenger = declared.ranked.firstOrNull { it.cardId == aspirational.winner.cardId }
            if (challenger != null) {
                val flip = breakevenCents(
                    pointsCard = challenger,
                    incumbent = declared.winner,
                    ranked = declared.ranked,
                    purchase = purchase
                )
                val benchmarkCents = (challenger.aspirationalNetValueCad + challenger.fxCostCad) * 100.0 / challenger.rewardUnits
                if (flip <= benchmarkCents + 0.0001) {
                    sensitive = true
                    direction = ValuationDirection.ABOVE
                    alternateId = challenger.cardId
                    breakeven = flip
                    declaredCents = centsPerUnit(challenger)
                }
            }
        }

        return Recommendation(
            winner = declared.winner,
            runnerUp = declared.runnerUp,
            switchedFromDefault = declared.switched,
            advantageOverDefaultCad = declared.advantage,
            defaultNotAccepted = declared.defaultNotAccepted,
            suppressedBetterCard = declared.suppressed,
            valuationSensitive = sensitive,
            valuationDirection = direction,
            alternateWinnerCardId = alternateId,
            breakevenCentsPerPoint = breakeven,
            declaredCentsPerPoint = declaredCents,
            allCandidates = declared.ranked
        )
    }

    private fun centsPerUnit(score: CandidateScore): Double {
        return if (score.rewardUnits > 0) (score.grossRewardCad / score.rewardUnits) * 100.0 else 0.0
    }

    private fun breakevenCents(
        pointsCard: CandidateScore,
        incumbent: CandidateScore,
        ranked: List<CandidateScore>,
        purchase: PurchaseContext
    ): Double {
        val t = ownerState.switchThreshold
        val ppFloorCad = t.minAdvantagePercentagePoints * purchase.amountCad / 100.0
        val requiredAdvantage = if (t.semantics == "either") {
            minOf(t.minAdvantageCad, ppFloorCad)
        } else {
            maxOf(t.minAdvantageCad, ppFloorCad)
        }
        val defaultId = ownerState.defaultCardId

        var needed = incumbent.netValueCad + (if (incumbent.cardId == defaultId) requiredAdvantage else 0.0)
        if (incumbent.cardId != defaultId && pointsCard.cardId != defaultId) {
            val defaultScore = ranked.firstOrNull { it.cardId == defaultId }
            if (defaultScore != null) {
                needed = maxOf(needed, defaultScore.netValueCad + requiredAdvantage)
            }
        }
        return (needed + pointsCard.fxCostCad) * 100.0 / pointsCard.rewardUnits
    }

    private fun rank(
        scores: List<CandidateScore>,
        purchase: PurchaseContext,
        value: (CandidateScore) -> Double
    ): Verdict {
        val defaultId = ownerState.defaultCardId
        val ranked = scores.sortedWith { a, b ->
            val va = value(a)
            val vb = value(b)
            if (va != vb) return@sortedWith vb.compareTo(va)
            if (a.cardId == defaultId) return@sortedWith -1
            if (b.cardId == defaultId) return@sortedWith 1
            a.cardId.compareTo(b.cardId)
        }

        val best = ranked[0]
        val runnerUp = if (ranked.size > 1) ranked[1] else null

        val defaultScore = ranked.firstOrNull { it.cardId == defaultId }
            ?: return Verdict(
                winner = best,
                runnerUp = runnerUp,
                switched = true,
                advantage = null,
                defaultNotAccepted = true,
                suppressed = null,
                ranked = ranked
            )

        val advantage = value(best) - value(defaultScore)
        val advantagePP = if (purchase.amountCad > 0) advantage / purchase.amountCad * 100.0 else 0.0
        val t = ownerState.switchThreshold
        val cadOk = advantage >= t.minAdvantageCad
        val ppOk = advantagePP >= t.minAdvantagePercentagePoints
        val clearsThreshold = if (t.semantics == "either") (cadOk || ppOk) else (cadOk && ppOk)

        if (best.cardId != defaultId && clearsThreshold) {
            return Verdict(
                winner = best,
                runnerUp = runnerUp,
                switched = true,
                advantage = advantage,
                defaultNotAccepted = false,
                suppressed = null,
                ranked = ranked
            )
        }

        val suppressed = if (best.cardId != defaultId && advantage > 0) best else null
        return Verdict(
            winner = defaultScore,
            runnerUp = ranked.firstOrNull { it.cardId != defaultId },
            switched = false,
            advantage = 0.0,
            defaultNotAccepted = false,
            suppressed = suppressed,
            ranked = ranked
        )
    }
}
