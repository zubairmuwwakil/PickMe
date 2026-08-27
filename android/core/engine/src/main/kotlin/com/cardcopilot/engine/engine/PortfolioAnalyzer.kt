package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CandidateScore
import com.cardcopilot.engine.models.CapPeriod
import com.cardcopilot.engine.models.CapMeasure
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.ReportingCurrency
import com.cardcopilot.engine.models.SpendDistribution
import java.util.Locale

enum class PortfolioVerdict {
    FREE_TO_KEEP,
    KEEP,
    DOWNGRADE,
    CANCEL
}

data class BackfillShare(
    val cardId: String,
    val bucketLabels: List<String>,
    val valueRetainedCad: Double
)

data class CardContribution(
    val cardId: String,
    val marginalValueCad: Double,
    val grossRewardValueCad: Double,
    val annualFeeCad: Double,
    val netContributionCad: Double,
    val verdict: PortfolioVerdict,
    val requiredBenefitValueCad: Double,
    val feeWaiverUnresolved: Boolean,
    val neverScorable: Boolean,
    val winningBuckets: List<String>,
    val backfilledBy: List<BackfillShare>
)

data class RedundantPair(
    val cardIds: List<String>,
    val jointMarginalCad: Double,
    val sumOfIndividualMarginalsCad: Double,
    val combinedAnnualFeeCad: Double
)

data class PortfolioAnalysis(
    val profileId: String,
    val asOf: String,
    val totalAnnualSpendCad: Double,
    val portfolioValueCad: Double,
    val totalAnnualFeesCad: Double,
    val contributions: List<CardContribution>,
    val redundantPairs: List<RedundantPair>
) {
    fun contribution(cardId: String): CardContribution? = contributions.firstOrNull { it.cardId == cardId }
}

data class PortfolioRun(
    val totalValueCad: Double,
    val valueByCard: Map<String, Double>,
    val valueByBucket: Map<String, Double>,
    val scorableCards: Set<String>,
    val winnersByBucket: Map<String, Set<String>>
)

class PortfolioAnalyzer(
    val catalogue: Catalogue,
    val ownerState: OwnerState,
    cardIds: Set<String>? = null
) {
    private val scopedCatalogue: Catalogue = if (cardIds != null) {
        catalogue.copy(cards = catalogue.cards.filter { cardIds.contains(it.cardId) })
    } else if (ownerState.ownedCardIds.isNotEmpty()) {
        val owned = ownerState.ownedCardIds.toSet()
        catalogue.copy(cards = catalogue.cards.filter { owned.contains(it.cardId) })
    } else {
        catalogue
    }

    companion object {
        const val REDUNDANCY_MATERIALITY_FRACTION = 0.1

        fun advance(isoDate: String, byMonths: Int): String {
            val parts = isoDate.split("-").mapNotNull { it.toIntOrNull() }
            if (parts.size != 3) return isoDate
            val zeroBased = (parts[0] * 12 + parts[1] - 1) + byMonths
            val year = zeroBased / 12
            val month = zeroBased % 12 + 1
            val day = minOf(parts[2], 28)
            return String.format(Locale.US, "%04d-%02d-%02d", year, month, day)
        }
    }

    fun analyze(distribution: SpendDistribution, asOf: String): PortfolioAnalysis {
        val full = run(distribution, emptySet(), asOf)

        val contributions = mutableListOf<CardContribution>()
        for (card in scopedCatalogue.cards) {
            val without = run(distribution, setOf(card.cardId), asOf)
            val marginal = full.totalValueCad - without.totalValueCad
            val fee = ReportingCurrency.toReporting(card.fee.annual)
            val wins = full.winnersByBucket
                .filter { it.value.contains(card.cardId) }
                .keys.sorted()

            contributions.add(
                CardContribution(
                    cardId = card.cardId,
                    marginalValueCad = marginal,
                    grossRewardValueCad = full.valueByCard[card.cardId] ?: 0.0,
                    annualFeeCad = fee,
                    netContributionCad = marginal - fee,
                    verdict = verdict(card, marginal, fee),
                    requiredBenefitValueCad = maxOf(0.0, fee - marginal),
                    feeWaiverUnresolved = feeWaiverUnresolved(card),
                    neverScorable = !full.scorableCards.contains(card.cardId),
                    winningBuckets = wins,
                    backfilledBy = backfill(card.cardId, wins, without)
                )
            )
        }

        contributions.sortWith { a, b ->
            if (a.netContributionCad != b.netContributionCad) {
                b.netContributionCad.compareTo(a.netContributionCad)
            } else {
                a.cardId.compareTo(b.cardId)
            }
        }

        return PortfolioAnalysis(
            profileId = distribution.profileId,
            asOf = asOf,
            totalAnnualSpendCad = distribution.totalAnnualCad,
            portfolioValueCad = full.totalValueCad,
            totalAnnualFeesCad = scopedCatalogue.cards.sumOf { ReportingCurrency.toReporting(it.fee.annual) },
            contributions = contributions,
            redundantPairs = redundantPairs(distribution, asOf, full, contributions)
        )
    }

    fun marginalValue(
        ofRemoving: Set<String>,
        from: SpendDistribution,
        asOf: String
    ): Double {
        return run(from, emptySet(), asOf).totalValueCad - run(from, ofRemoving, asOf).totalValueCad
    }

    fun run(
        distribution: SpendDistribution,
        excluding: Set<String>,
        asOf: String
    ): PortfolioRun {
        val subCatalogue = scopedCatalogue.copy(cards = scopedCatalogue.cards.filter { !excluding.contains(it.cardId) })
        var state = forwardYearState()

        var total = 0.0
        val byCard = mutableMapOf<String, Double>()
        val byBucket = mutableMapOf<String, Double>()
        val winners = mutableMapOf<String, MutableSet<String>>()
        val scorable = mutableSetOf<String>()

        for (month in 0 until 12) {
            state = resetMonthlyCaps(state, subCatalogue)
            val monthAsOf = advance(asOf, month)

            for (bucket in distribution.buckets) {
                if (bucket.annualCad <= 0) continue
                val purchase = bucket.context.copy(
                    amountCad = bucket.annualCad / 12.0,
                    usdEquivalent = bucket.context.usdEquivalent?.let { it / 12.0 }
                )

                if (!subCatalogue.cards.any { purchase.acceptedNetworks.contains(it.network) }) {
                    continue
                }

                val engine = RecommendationEngine(subCatalogue, state)
                val candidates = engine.recommendOrNull(purchase, monthAsOf)?.allCandidates ?: emptyList()
                scorable.addAll(candidates.map { it.cardId })
                val best = candidates.firstOrNull() ?: continue

                total += best.netValueCad
                byCard[best.cardId] = (byCard[best.cardId] ?: 0.0) + best.netValueCad
                byBucket[bucket.label] = (byBucket[bucket.label] ?: 0.0) + best.netValueCad
                winners.getOrPut(bucket.label) { mutableSetOf() }.add(best.cardId)

                state = accrueCapProgress(best, purchase, subCatalogue, state)
            }
        }

        return PortfolioRun(
            totalValueCad = total,
            valueByCard = byCard,
            valueByBucket = byBucket,
            scorableCards = scorable,
            winnersByBucket = winners
        )
    }

    private fun forwardYearState(): OwnerState {
        val resetCardStates = ownerState.cardStates.mapValues { (_, cardState) ->
            cardState.copy(capProgress = cardState.capProgress?.mapValues { 0.0 })
        }
        return ownerState.copy(cardStates = resetCardStates)
    }

    private fun resetMonthlyCaps(state: OwnerState, catalogue: Catalogue): OwnerState {
        val updatedCardStates = state.cardStates.toMutableMap()
        for (card in catalogue.cards) {
            for (cap in card.caps) {
                if (cap.period == CapPeriod.CALENDAR_MONTH) {
                    val cs = updatedCardStates[card.cardId] ?: CardState()
                    val progress = (cs.capProgress ?: emptyMap()).toMutableMap()
                    progress[cap.capId] = 0.0
                    updatedCardStates[card.cardId] = cs.copy(capProgress = progress)
                }
            }
        }
        return state.copy(cardStates = updatedCardStates)
    }

    private fun accrueCapProgress(
        score: CandidateScore,
        purchase: PurchaseContext,
        catalogue: Catalogue,
        state: OwnerState
    ): OwnerState {
        val card = catalogue.cards.firstOrNull { it.cardId == score.cardId } ?: return state
        val ruleId = score.appliedRuleId ?: return state
        val capId = card.earnRules.firstOrNull { it.ruleId == ruleId }?.capId ?: return state
        val cap = card.caps.firstOrNull { it.capId == capId } ?: return state

        val amount = if (cap.measure == CapMeasure.SPEND_USD_EQUIVALENT) {
            purchase.usdEquivalent ?: (purchase.amountCad * Scorer.FALLBACK_CAD_TO_USD)
        } else {
            purchase.amountCad
        }

        val cardState = state.cardStates[card.cardId] ?: CardState()
        val currentProgress = (cardState.capProgress ?: emptyMap()).toMutableMap()
        currentProgress[capId] = (currentProgress[capId] ?: 0.0) + amount
        val updatedCardStates = state.cardStates.toMutableMap()
        updatedCardStates[card.cardId] = cardState.copy(capProgress = currentProgress)
        return state.copy(cardStates = updatedCardStates)
    }

    private fun verdict(card: CardProduct, marginal: Double, fee: Double): PortfolioVerdict {
        if (fee <= 0) return PortfolioVerdict.FREE_TO_KEEP
        if (marginal >= fee) return PortfolioVerdict.KEEP
        val soleHolderOfProgram = !scopedCatalogue.cards.any {
            it.cardId != card.cardId && it.program.programId == card.program.programId
        }
        return if (marginal > 0 && soleHolderOfProgram) PortfolioVerdict.DOWNGRADE else PortfolioVerdict.CANCEL
    }

    private fun feeWaiverUnresolved(card: CardProduct): Boolean {
        return card.fee.waiver != null && ownerState.cardStates[card.cardId]?.feeWaiverActive == null
    }

    private fun backfill(cardId: String, wins: List<String>, without: PortfolioRun): List<BackfillShare> {
        val buckets = mutableMapOf<String, MutableList<String>>()
        val retained = mutableMapOf<String, Double>()
        for (label in wins) {
            val successors = without.winnersByBucket[label]?.sorted() ?: emptyList()
            for (successor in successors) {
                buckets.getOrPut(successor) { mutableListOf() }.add(label)
                retained[successor] = (retained[successor] ?: 0.0) + (without.valueByBucket[label] ?: 0.0)
            }
        }

        val sortedKeys = buckets.keys.sortedWith { a, b ->
            val ra = retained[a] ?: 0.0
            val rb = retained[b] ?: 0.0
            if (ra != rb) rb.compareTo(ra) else a.compareTo(b)
        }

        return sortedKeys.map {
            BackfillShare(
                cardId = it,
                bucketLabels = buckets[it] ?: emptyList(),
                valueRetainedCad = retained[it] ?: 0.0
            )
        }
    }

    private fun redundantPairs(
        distribution: SpendDistribution,
        asOf: String,
        full: PortfolioRun,
        contributions: List<CardContribution>
    ): List<RedundantPair> {
        val unearned = contributions.filter { it.marginalValueCad < it.annualFeeCad }
        val pairs = mutableListOf<RedundantPair>()
        for (i in unearned.indices) {
            val a = unearned[i]
            for (j in (i + 1) until unearned.size) {
                val b = unearned[j]
                val aCoversB = a.backfilledBy.any { it.cardId == b.cardId }
                val bCoversA = b.backfilledBy.any { it.cardId == a.cardId }
                if (!aCoversB && !bCoversA) continue

                val joint = full.totalValueCad - run(distribution, setOf(a.cardId, b.cardId), asOf).totalValueCad
                val individually = a.marginalValueCad + b.marginalValueCad
                val combinedFee = a.annualFeeCad + b.annualFeeCad
                if (joint - individually >= REDUNDANCY_MATERIALITY_FRACTION * combinedFee && joint > individually + 0.01) {
                    pairs.add(
                        RedundantPair(
                            cardIds = listOf(a.cardId, b.cardId).sorted(),
                            jointMarginalCad = joint,
                            sumOfIndividualMarginalsCad = individually,
                            combinedAnnualFeeCad = combinedFee
                        )
                    )
                }
            }
        }
        return pairs.sortedByDescending { it.jointMarginalCad }
    }
}
