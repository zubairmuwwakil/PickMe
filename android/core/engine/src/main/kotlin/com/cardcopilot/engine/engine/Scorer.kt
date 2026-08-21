package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.CandidateScore
import com.cardcopilot.engine.models.CapMeasure
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.CashBackValuation
import com.cardcopilot.engine.models.CroValuation
import com.cardcopilot.engine.models.CtMoneyValuation
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PointValuation
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.Valuations
import com.cardcopilot.engine.models.Warning

object Scorer {
    const val FALLBACK_CAD_TO_USD = 0.73

    enum class ValuationBand { DECLARED, FLOOR, ASPIRATIONAL }

    fun score(
        card: CardProduct,
        purchase: PurchaseContext,
        ownerState: OwnerState,
        asOf: String
    ): CandidateScore {
        fun excludedScore(warning: Warning, reason: String): CandidateScore {
            return CandidateScore(
                cardId = card.cardId,
                appliedRuleId = null,
                rewardUnits = 0.0,
                grossRewardCad = 0.0,
                fxCostCad = 0.0,
                netValueCad = 0.0,
                floorNetValueCad = 0.0,
                aspirationalNetValueCad = 0.0,
                warnings = listOf(warning),
                excluded = true,
                exclusionReason = reason
            )
        }

        if (!purchase.acceptedNetworks.contains(card.network)) {
            return excludedScore(Warning.NETWORK_NOT_ACCEPTED, "${card.network.rawValue} not accepted")
        }

        val (rule: EarnRule, capabilityGaps: List<String>) =
            when (val resolution = RuleMatcher.resolve(card, purchase, ownerState, asOf)) {
                is RuleResolution.CardExcluded -> return excludedScore(resolution.warning, resolution.reason)
                is RuleResolution.Applied -> resolution.rule to resolution.unsupportedCapabilities
            }

        val warnings = mutableListOf<Warning>()
        // A better rule matched this purchase and this build could not run it. The card keeps the
        // number it can defend, and the owner is told the number is not the whole story.
        if (capabilityGaps.isNotEmpty()) warnings.add(Warning.UNSUPPORTED_CAPABILITY)
        val state = ownerState.cardStates[card.cardId] ?: CardState()

        // Ask before earning, not after: a program with no valuation cannot produce an honest
        // number, and the honest answer is a refusal that names the gap. `units = 0` makes this a
        // pure presence check — no model here can turn a missing valuation into a value.
        if (valueCad(0.0, card.program.programId, ownerState.valuationsCad, state) == null) {
            return excludedScore(
                Warning.UNSUPPORTED_PROGRAM,
                "no valuation for program ${card.program.programId}"
            )
        }

        var inCapCad = purchase.amountCad
        var overCapCad = 0.0

        if (rule.capId != null) {
            val cap = card.caps.firstOrNull { it.capId == rule.capId }
            if (cap != null) {
                val usage = state.capProgress?.get(rule.capId) ?: 0.0
                val measureAmount = if (cap.measure == CapMeasure.SPEND_USD_EQUIVALENT) {
                    purchase.usdEquivalent ?: (purchase.amountCad * FALLBACK_CAD_TO_USD)
                } else {
                    purchase.amountCad
                }
                val split = CapMath.split(measureAmount, cap.limit, usage)
                val inFraction = if (measureAmount > 0) split.inCap / measureAmount else 1.0
                inCapCad = purchase.amountCad * inFraction
                overCapCad = purchase.amountCad - inCapCad
                if (usage >= cap.limit * 0.9) {
                    warnings.add(Warning.CAP_NEARLY_EXHAUSTED)
                }
            }
        }

        val postCapEarn = rule.capId?.let { id -> card.caps.firstOrNull { it.capId == id }?.postCapEarn }
        val units = earnUnits(rule.earn, inCapCad) + earnUnits(postCapEarn ?: rule.earn, overCapCad)

        // Non-null asserted, not `?: 0.0`: the check above proves a valuation exists, and a zero
        // fallback would quietly reinstate the zero-scoring bug if a refactor ever moved it.
        val gross = valueCad(units, card.program.programId, ownerState.valuationsCad, state, ValuationBand.DECLARED)!!
        val grossFloor = valueCad(units, card.program.programId, ownerState.valuationsCad, state, ValuationBand.FLOOR)!!
        val grossAspirational = valueCad(units, card.program.programId, ownerState.valuationsCad, state, ValuationBand.ASPIRATIONAL)!!

        var fxCost = 0.0
        if (purchase.currency != "CAD") {
            val fx = RuleMatcher.activeFxRule(card, asOf)
            if (fx != null) {
                if (fx.freeAllowanceCadPerCalendarMonth != null) {
                    warnings.add(Warning.FX_ALLOWANCE_ASSUMED)
                } else {
                    fxCost = purchase.amountCad * fx.rate
                }
            }
        }

        val net = gross - fxCost
        if (net < 0) {
            warnings.add(Warning.NEGATIVE_NET_VALUE)
        }
        if (ownerState.carry.drawerCards.contains(card.cardId)) {
            warnings.add(Warning.DRAWER_CARD)
        }
        if (rule.ruleId == "tangerine-selected-2pct" && state.treatAsAllSelected == true) {
            warnings.add(Warning.HYPOTHETICAL_SELECTION)
        }

        return CandidateScore(
            cardId = card.cardId,
            appliedRuleId = rule.ruleId,
            rewardUnits = units,
            grossRewardCad = gross,
            fxCostCad = fxCost,
            netValueCad = net,
            floorNetValueCad = grossFloor - fxCost,
            aspirationalNetValueCad = grossAspirational - fxCost,
            warnings = warnings,
            excluded = false,
            exclusionReason = null
        )
    }

    fun earnUnits(earn: Earn, amountCad: Double): Double {
        return when (earn) {
            is Earn.Points -> amountCad * earn.pointsPerCad
            is Earn.Cashback -> amountCad * earn.rate
            is Earn.CentsPerLitre -> 0.0
        }
    }

    /**
     * Null means the program has no valuation — the card cannot be scored. Zero means the
     * program is valued and this earn is worth nothing. Conflating them is how ten programs
     * silently ranked last for four release batches.
     *
     * A pure function of the [valuations] passed in: catalogue defaults are merged into owner
     * state up in `RecommendationEngine`'s constructor, deliberately not here, so a caller
     * holding an empty [Valuations] gets null rather than a value it never declared.
     */
    fun valueCad(
        units: Double,
        program: String,
        valuations: Valuations,
        state: CardState,
        band: ValuationBand = ValuationBand.DECLARED
    ): Double? {
        fun cents(v: PointValuation): Double {
            return when (band) {
                ValuationBand.DECLARED -> v.centsPerPoint
                ValuationBand.FLOOR -> v.floorCentsPerPoint ?: v.centsPerPoint
                ValuationBand.ASPIRATIONAL -> maxOf(v.aspirationalCentsPerPoint ?: v.centsPerPoint, v.centsPerPoint)
            }
        }
        // Dispatch on the valuation's model, not on the program's name. The name-keyed `when`
        // this replaced could only ever value the six programs it listed, so a program gaining a
        // valuation still had to gain a Kotlin branch — which is the coupling this refactor
        // exists to remove.
        return when (val valuation = valuations[program]) {
            null -> null
            is PointValuation -> units * cents(valuation) / 100.0
            is CtMoneyValuation ->
                units * valuation.cadPerUnit *
                    (if (valuation.usabilityFactorApplied) valuation.optionalUsabilityFactor else 1.0)
            is CroValuation -> units * (
                if (state.croHandling == "autoSell") valuation.faceValueFactorIfAutoSold
                else valuation.defaultHeldRiskFactor
                )
            is CashBackValuation -> units * valuation.cadPerDollar
        }
    }
}
