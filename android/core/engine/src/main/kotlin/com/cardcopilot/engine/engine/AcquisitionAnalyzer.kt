package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.ReportingCurrency
import com.cardcopilot.engine.models.SpendDistribution

enum class AcquisitionVerdict {
    WORTH_ADDING,
    BENEFITS_REQUIRED,
    NO_EARN_ADVANTAGE
}

data class AcquisitionBucketGain(
    val label: String,
    val annualSpendCad: Double,
    val valueBeforeCad: Double,
    val valueAfterCad: Double,
    val displacedCardIds: List<String>
) {
    val marginalValueCad: Double get() = valueAfterCad - valueBeforeCad
}

data class AcquisitionCandidate(
    val cardId: String,
    val grossRewardValueCad: Double,
    val marginalRewardValueCad: Double,
    val annualFeeCad: Double,
    val netAnnualValueCad: Double,
    val verdict: AcquisitionVerdict,
    val requiredBenefitValueCad: Double,
    val feeWaiverUnresolved: Boolean,
    val neverScorable: Boolean,
    val bucketGains: List<AcquisitionBucketGain>,
    /**
     * Whether a resident of `OwnerState.resolvedMarket` can hold this card at all —
     * `card.eligibility?.residency ?: [card.market]`. Does not remove the candidate from
     * [AcquisitionAnalysis.candidates]; it only gates [AcquisitionAnalysis.recommended].
     */
    val eligibleForResident: Boolean
)

data class AcquisitionAnalysis(
    val profileId: String,
    val asOf: String,
    val walletCardIds: List<String>,
    val baselinePortfolioValueCad: Double,
    val candidates: List<AcquisitionCandidate>
) {
    val recommended: List<AcquisitionCandidate>
        get() = candidates.filter { it.verdict == AcquisitionVerdict.WORTH_ADDING && it.eligibleForResident }

    fun candidate(cardId: String): AcquisitionCandidate? = candidates.firstOrNull { it.cardId == cardId }
}

class AcquisitionAnalyzer(
    val walletCatalogue: Catalogue,
    val candidateCatalogue: Catalogue,
    val ownerState: OwnerState
) {
    fun analyze(distribution: SpendDistribution, asOf: String): AcquisitionAnalysis {
        val owned = ownerState.ownedCardIds.toSet()
        val walletProductIds = walletCatalogue.cards.map { it.cardId }.toSet()
        val knownCards = walletCatalogue.cards + candidateCatalogue.cards.filter { !walletProductIds.contains(it.cardId) }
        val knownCatalogue = walletCatalogue.copy(cards = knownCards)

        val walletIds = owned.intersect(knownCards.map { it.cardId }.toSet())
        val baselineAnalyzer = PortfolioAnalyzer(
            catalogue = knownCatalogue,
            ownerState = ownerState,
            cardIds = walletIds
        )
        val baseline = baselineAnalyzer.run(distribution, emptySet(), asOf)
        val annualSpendByLabel = distribution.buckets.associate { it.label to it.annualCad }

        val results = mutableListOf<AcquisitionCandidate>()
        for (card in candidateCatalogue.cards) {
            if (owned.contains(card.cardId)) continue

            val combinedIds = walletIds + card.cardId
            val combined = PortfolioAnalyzer(
                catalogue = knownCatalogue,
                ownerState = ownerState,
                cardIds = combinedIds
            ).run(distribution, emptySet(), asOf)

            val marginal = combined.totalValueCad - baseline.totalValueCad
            val fee = when {
                card.fee.annual != null -> ReportingCurrency.toReporting(card.fee.annual)
                card.fee.monthly != null -> ReportingCurrency.toReporting(card.fee.monthly) * 12.0
                else -> 0.0
            }
            val net = marginal - fee
            val eligibleMarkets = card.eligibility?.residency ?: listOf(card.market)
            val eligibleForResident = eligibleMarkets.contains(ownerState.resolvedMarket)

            val gains = combined.winnersByBucket.keys.mapNotNull { label ->
                if (combined.winnersByBucket[label]?.contains(card.cardId) != true) return@mapNotNull null
                val before = baseline.valueByBucket[label] ?: 0.0
                val after = combined.valueByBucket[label] ?: 0.0
                if (after <= before + 0.005) return@mapNotNull null
                AcquisitionBucketGain(
                    label = label,
                    annualSpendCad = annualSpendByLabel[label] ?: 0.0,
                    valueBeforeCad = before,
                    valueAfterCad = after,
                    displacedCardIds = (baseline.winnersByBucket[label] ?: emptySet()).toList().sorted()
                )
            }.sortedWith { a, b ->
                if (a.marginalValueCad != b.marginalValueCad) {
                    b.marginalValueCad.compareTo(a.marginalValueCad)
                } else {
                    a.label.compareTo(b.label)
                }
            }

            val scorable = combined.scorableCards.contains(card.cardId)
            val verdict = when {
                net > 0.01 -> AcquisitionVerdict.WORTH_ADDING
                marginal > 0.01 -> AcquisitionVerdict.BENEFITS_REQUIRED
                else -> AcquisitionVerdict.NO_EARN_ADVANTAGE
            }

            results.add(
                AcquisitionCandidate(
                    cardId = card.cardId,
                    grossRewardValueCad = combined.valueByCard[card.cardId] ?: 0.0,
                    marginalRewardValueCad = marginal,
                    annualFeeCad = fee,
                    netAnnualValueCad = net,
                    verdict = verdict,
                    requiredBenefitValueCad = maxOf(0.0, fee - marginal),
                    feeWaiverUnresolved = card.fee.waiver != null && ownerState.cardStates[card.cardId]?.feeWaiverActive == null,
                    neverScorable = !scorable,
                    bucketGains = gains,
                    eligibleForResident = eligibleForResident
                )
            )
        }

        results.sortWith { a, b ->
            if (a.netAnnualValueCad != b.netAnnualValueCad) {
                b.netAnnualValueCad.compareTo(a.netAnnualValueCad)
            } else {
                a.cardId.compareTo(b.cardId)
            }
        }

        return AcquisitionAnalysis(
            profileId = distribution.profileId,
            asOf = asOf,
            walletCardIds = walletIds.toList().sorted(),
            baselinePortfolioValueCad = baseline.totalValueCad,
            candidates = results
        )
    }
}
