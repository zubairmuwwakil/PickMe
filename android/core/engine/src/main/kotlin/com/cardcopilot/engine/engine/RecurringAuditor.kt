package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CandidateScore
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.Network
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.Placement
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.RecurringCategoryDefaults
import com.cardcopilot.engine.models.RecurringFlagStatus
import com.cardcopilot.engine.models.RecurringPayment
import com.cardcopilot.engine.models.RecurringPlan
import com.cardcopilot.engine.models.Warning

enum class RecurringAction {
    ALREADY_OPTIMAL,
    MOVE,
    BELOW_BAR,
    BASELINE_UNKNOWN
}

sealed interface FlagRobustness {
    data object FlagIndependent : FlagRobustness
    data object FlagConfirmed : FlagRobustness
    data object FlagRefuted : FlagRobustness
    data class FlagContingent(val contingency: FlagContingency) : FlagRobustness
}

data class FlagContingency(
    val cardIfFlagged: String,
    val cardIfNotFlagged: String,
    val annualGainIfFlaggedCad: Double,
    val oneCycleCostIfNotFlaggedCad: Double,
    val testWorthRunning: Boolean
)

sealed interface RecurringDisclosure {
    data class MccAssumed(val mcc: Int) : RecurringDisclosure
    data class MccGateUnverified(val ruleId: String) : RecurringDisclosure
    data object AmexAcceptanceAssumed : RecurringDisclosure
    data class ValuationSensitive(val alternateCardId: String) : RecurringDisclosure
    data object HypotheticalTangerineSelection : RecurringDisclosure
}

data class RecurringAssignment(
    val paymentId: String,
    val label: String,
    val annualCad: Double,
    val currentPlacement: Placement,
    val recommendedCardId: String,
    val recommendedAnnualValueCad: Double,
    val currentAnnualValueCad: Double?,
    val annualGainCad: Double?,
    val advantagePercentagePoints: Double?,
    val action: RecurringAction,
    val robustness: FlagRobustness,
    val disclosures: List<RecurringDisclosure>
) {
    val id: String get() = paymentId
}

data class RecurringAudit(
    val planId: String,
    val basis: String,
    val asOf: String,
    val totalAnnualDeclaredCad: Double,
    val assignments: List<RecurringAssignment>,
    val projectionsAtCurrentPlacement: List<CapProjectionOutcome>,
    val projectionsAtRecommendedPlacement: List<CapProjectionOutcome>
) {
    fun assignment(paymentId: String): RecurringAssignment? = assignments.firstOrNull { it.paymentId == paymentId }
}

class RecurringAuditor(
    val catalogue: Catalogue,
    val ownerState: OwnerState
) {
    companion object {
        const val MIN_ADVANTAGE_PERCENTAGE_POINTS = 0.5
        const val MIN_ANNUAL_GAIN_CAD = 5.0
    }

    fun audit(
        plan: RecurringPlan,
        asOf: String,
        capProgressAsOf: String? = null
    ): RecurringAudit {
        val assignments = plan.payments.map { assign(it, asOf) }
        val byId = plan.payments.associateBy { it.id }
        val projector = CapProjector(catalogue, ownerState)

        fun placements(cardIdSelector: (RecurringAssignment) -> String?): List<PlacedPayment> {
            return assignments.mapNotNull { assignment ->
                val payment = byId[assignment.paymentId] ?: return@mapNotNull null
                val cardId = cardIdSelector(assignment) ?: return@mapNotNull null
                PlacedPayment(
                    payment = payment,
                    cardId = cardId,
                    assumeFlagged = payment.flagStatus != RecurringFlagStatus.REFUTED
                )
            }
        }

        return RecurringAudit(
            planId = plan.planId,
            basis = plan.basis,
            asOf = asOf,
            totalAnnualDeclaredCad = plan.totalAnnualCad,
            assignments = assignments,
            projectionsAtCurrentPlacement = projector.project(
                placements { assignment ->
                    if (assignment.currentPlacement is Placement.Card) assignment.currentPlacement.cardId else null
                },
                asOf = asOf,
                capProgressAsOf = capProgressAsOf
            ),
            projectionsAtRecommendedPlacement = projector.project(
                placements { it.recommendedCardId },
                asOf = asOf,
                capProgressAsOf = capProgressAsOf
            )
        )
    }

    private fun assign(payment: RecurringPayment, asOf: String): RecurringAssignment {
        val disclosures = mutableListOf<RecurringDisclosure>()
        val mcc = resolvedMcc(payment, disclosures)

        val flagged = world(payment, mcc, flagged = true, asOf = asOf)
        val unflagged = world(payment, mcc, flagged = false, asOf = asOf)
        val verdict = resolve(payment, flagged, unflagged)
        val recommendedId = verdict.recommendedCardId

        val recommendedValue = verdict.value(recommendedId)
        val currentValue: Double? = when (val p = payment.placement) {
            is Placement.Card -> verdict.value(p.cardId)
            Placement.OffWallet -> 0.0
            Placement.Unknown -> null
        }

        val gain = currentValue?.let { verdict.gain(payment.placement, recommendedId) }
        disclose(payment, verdict, mcc, disclosures)
        val advantagePP = gain?.let { if (payment.annualCad > 0) it / payment.annualCad * 100.0 else 0.0 }

        return RecurringAssignment(
            paymentId = payment.id,
            label = payment.label,
            annualCad = payment.annualCad,
            currentPlacement = payment.placement,
            recommendedCardId = recommendedId,
            recommendedAnnualValueCad = recommendedValue,
            currentAnnualValueCad = currentValue,
            annualGainCad = gain,
            advantagePercentagePoints = advantagePP,
            action = action(payment, recommendedId, gain, advantagePP),
            robustness = verdict.robustness,
            disclosures = disclosures
        )
    }

    private fun action(
        payment: RecurringPayment,
        recommendedId: String,
        gain: Double?,
        advantagePP: Double?
    ): RecurringAction {
        if (gain == null || advantagePP == null) return RecurringAction.BASELINE_UNKNOWN
        if (payment.placement is Placement.Card && payment.placement.cardId == recommendedId) {
            return RecurringAction.ALREADY_OPTIMAL
        }
        val clears = gain >= MIN_ANNUAL_GAIN_CAD && advantagePP >= MIN_ADVANTAGE_PERCENTAGE_POINTS
        return if (clears) RecurringAction.MOVE else RecurringAction.BELOW_BAR
    }

    private fun disclose(
        payment: RecurringPayment,
        verdict: Verdict,
        mcc: Int?,
        disclosures: MutableList<RecurringDisclosure>
    ) {
        val world = verdict.representativeWorld
        val score = world.score(verdict.recommendedCardId) ?: return
        val card = catalogue.cards.firstOrNull { it.cardId == verdict.recommendedCardId } ?: return

        if (mcc == null) {
            val ruleId = score.appliedRuleId
            if (ruleId != null && card.earnRules.firstOrNull { it.ruleId == ruleId }?.predicate?.mccInclude != null) {
                disclosures.add(RecurringDisclosure.MccGateUnverified(ruleId))
            }
        }

        if (card.network == Network.AMEX && payment.declaredAcceptedNetworks == null) {
            disclosures.add(RecurringDisclosure.AmexAcceptanceAssumed)
        }

        val floorWinner = world.floorWinner
        if (floorWinner != null && floorWinner.cardId != verdict.recommendedCardId) {
            disclosures.add(RecurringDisclosure.ValuationSensitive(floorWinner.cardId))
        }

        if (score.warnings.contains(Warning.HYPOTHETICAL_SELECTION)) {
            disclosures.add(RecurringDisclosure.HypotheticalTangerineSelection)
        }
    }

    private enum class Mode { FLAGGED_ONLY, UNFLAGGED_ONLY, CONSERVATIVE_BOTH }

    private data class Verdict(
        val recommendedCardId: String,
        val robustness: FlagRobustness,
        val mode: Mode,
        val flagged: ScoredWorld,
        val unflagged: ScoredWorld
    ) {
        val representativeWorld: ScoredWorld
            get() = if (mode == Mode.FLAGGED_ONLY) flagged else unflagged

        fun value(cardId: String): Double {
            return when (mode) {
                Mode.FLAGGED_ONLY -> flagged.annualValue(cardId)
                Mode.UNFLAGGED_ONLY -> unflagged.annualValue(cardId)
                Mode.CONSERVATIVE_BOTH -> minOf(flagged.annualValue(cardId), unflagged.annualValue(cardId))
            }
        }

        fun gain(placement: Placement, recommendedId: String): Double {
            fun current(world: ScoredWorld): Double {
                return if (placement is Placement.Card) world.annualValue(placement.cardId) else 0.0
            }
            return when (mode) {
                Mode.FLAGGED_ONLY -> flagged.annualValue(recommendedId) - current(flagged)
                Mode.UNFLAGGED_ONLY -> unflagged.annualValue(recommendedId) - current(unflagged)
                Mode.CONSERVATIVE_BOTH -> minOf(
                    flagged.annualValue(recommendedId) - current(flagged),
                    unflagged.annualValue(recommendedId) - current(unflagged)
                )
            }
        }
    }

    private fun resolve(
        payment: RecurringPayment,
        flagged: ScoredWorld,
        unflagged: ScoredWorld
    ): Verdict {
        fun verdict(cardId: String?, robustness: FlagRobustness, mode: Mode): Verdict {
            return Verdict(
                recommendedCardId = cardId ?: "",
                robustness = robustness,
                mode = mode,
                flagged = flagged,
                unflagged = unflagged
            )
        }

        return when (payment.flagStatus) {
            RecurringFlagStatus.CONFIRMED -> verdict(flagged.winner?.cardId, FlagRobustness.FlagConfirmed, Mode.FLAGGED_ONLY)
            RecurringFlagStatus.REFUTED -> verdict(unflagged.winner?.cardId, FlagRobustness.FlagRefuted, Mode.UNFLAGGED_ONLY)
            RecurringFlagStatus.ASSUMED -> {
                val ifFlagged = flagged.winner?.cardId
                val ifNot = unflagged.winner?.cardId
                if (ifFlagged == null || ifNot == null) {
                    return verdict(null, FlagRobustness.FlagIndependent, Mode.CONSERVATIVE_BOTH)
                }
                if (ifFlagged == ifNot) {
                    return verdict(ifFlagged, FlagRobustness.FlagIndependent, Mode.CONSERVATIVE_BOTH)
                }

                val gainIfFlagged = flagged.annualValue(ifFlagged) - unflagged.annualValue(ifNot)
                val oneCycleCost = (unflagged.annualValue(ifNot) - unflagged.annualValue(ifFlagged)) / payment.cadence.chargesPerYear
                val worthRunning = gainIfFlagged > oneCycleCost

                verdict(
                    if (worthRunning) ifFlagged else ifNot,
                    FlagRobustness.FlagContingent(
                        FlagContingency(
                            cardIfFlagged = ifFlagged,
                            cardIfNotFlagged = ifNot,
                            annualGainIfFlaggedCad = gainIfFlagged,
                            oneCycleCostIfNotFlaggedCad = oneCycleCost,
                            testWorthRunning = worthRunning
                        )
                    ),
                    if (worthRunning) Mode.FLAGGED_ONLY else Mode.UNFLAGGED_ONLY
                )
            }
        }
    }

    private data class ScoredWorld(
        val candidates: List<CandidateScore>,
        val perYear: Double,
        val defaultCardId: String
    ) {
        val winner: CandidateScore? get() = candidates.firstOrNull()

        fun score(cardId: String): CandidateScore? = candidates.firstOrNull { it.cardId == cardId }

        fun annualValue(cardId: String): Double = (score(cardId)?.netValueCad ?: 0.0) * perYear

        val floorWinner: CandidateScore?
            get() = candidates.sortedWith { a, b ->
                if (a.floorNetValueCad != b.floorNetValueCad) {
                    b.floorNetValueCad.compareTo(a.floorNetValueCad)
                } else if (a.cardId == defaultCardId) {
                    -1
                } else if (b.cardId == defaultCardId) {
                    1
                } else {
                    a.cardId.compareTo(b.cardId)
                }
            }.firstOrNull()
    }

    private fun world(
        payment: RecurringPayment,
        mcc: Int?,
        flagged: Boolean,
        asOf: String
    ): ScoredWorld {
        val purchase = PurchaseContext(
            amountCad = payment.amountCad,
            currency = payment.currency,
            category = payment.category,
            mcc = mcc,
            merchantBrand = payment.merchantBrand,
            channel = "online",
            recurringIndicator = flagged,
            acceptedNetworks = payment.effectiveAcceptedNetworks
        )
        val candidates = RecommendationEngine(catalogue, ownerState)
            .recommendOrNull(purchase, asOf)?.allCandidates ?: emptyList()
        return ScoredWorld(
            candidates = candidates,
            perYear = payment.cadence.chargesPerYear,
            defaultCardId = ownerState.defaultCardId
        )
    }

    private fun resolvedMcc(payment: RecurringPayment, disclosures: MutableList<RecurringDisclosure>): Int? {
        if (payment.mcc != null) return payment.mcc
        val representative = RecurringCategoryDefaults.representativeMcc[payment.category] ?: return null
        disclosures.add(RecurringDisclosure.MccAssumed(representative))
        return representative
    }
}
