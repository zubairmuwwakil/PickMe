package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.AcceptanceScope
import com.cardcopilot.engine.models.CandidateScore
import com.cardcopilot.engine.models.CapMeasure
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Currency
import com.cardcopilot.engine.models.Earn
import com.cardcopilot.engine.models.EarnRule
import com.cardcopilot.engine.models.CashBackValuation
import com.cardcopilot.engine.models.CroValuation
import com.cardcopilot.engine.models.CtMoneyValuation
import com.cardcopilot.engine.models.MerchantCreditValuation
import com.cardcopilot.engine.models.NoRewardsValuation
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PointValuation
import com.cardcopilot.engine.models.Money
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.ReportingCurrency
import com.cardcopilot.engine.models.Valuations
import com.cardcopilot.engine.models.Warning

object Scorer {
    const val FALLBACK_CAD_TO_USD = 0.73

    enum class ValuationBand { DECLARED, FLOOR, ASPIRATIONAL }

    /**
     * The purchase amount expressed in a card's own `billingCurrency` — 'points per currency
     * unit' means per unit of that currency, not per CAD unconditionally. For a CAD-billing card
     * (every card in this catalogue until the multi-market import) this is exactly
     * `purchase.amountCad`, unchanged. A USD-billing card reuses `usdEquivalent`, the same field
     * `spendUsdEquivalent` caps already relied on, falling back to the same pinned
     * `FALLBACK_CAD_TO_USD` approximation when the caller supplied no converted amount.
     *
     * Shared with `PortfolioAnalyzer.accrueCapProgress` so a `.SPEND_NATIVE` cap is always
     * compared and accrued in the same currency `score` uses — the two must never independently
     * decide what "native" means for the same card.
     */
    fun nativeAmount(purchase: PurchaseContext, billingCurrency: Currency): Double {
        return if (billingCurrency == Currency.USD) {
            purchase.usdEquivalent ?: (purchase.amountCad * FALLBACK_CAD_TO_USD)
        } else {
            purchase.amountCad
        }
    }

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

        if (!card.isScoreable(asOf)) {
            return excludedScore(Warning.PRODUCT_WITHDRAWN, "product withdrawn")
        }

        if (!card.isPublished) {
            return excludedScore(Warning.DRAFT_PRODUCT, "draft catalogue record, not yet issuer-verified")
        }

        // Two acceptance mechanisms, not one. An open-loop card is accepted because the merchant
        // takes its network; a closed-loop card is accepted because the merchant IS its issuer's
        // store. Forcing the second through a network check is what made private-label cards
        // unrepresentable without guessing `network`, which rule 3 forbids — and the guess is not
        // harmless: a Kohl's card recorded as visa is recommended at a gas station and declined at
        // the till. Absent `acceptance` coalesces to OPEN_LOOP, so every pre-2.5 card takes the
        // identical path it always did. Mirrors the Swift twin.
        when (card.acceptance?.scope ?: AcceptanceScope.OPEN_LOOP) {
            AcceptanceScope.OPEN_LOOP ->
                if (!purchase.acceptedNetworks.contains(card.network)) {
                    return excludedScore(
                        Warning.NETWORK_NOT_ACCEPTED,
                        "${card.network.rawValue} not accepted"
                    )
                }
            AcceptanceScope.CLOSED_LOOP -> {
                // Unresolved merchantBrand excludes rather than admits. These cards are only ever
                // as good as brand resolution, and silence beats recommending one that is declined.
                val merchants = card.acceptance?.merchants ?: emptyList()
                if (purchase.merchantBrand == null || !merchants.contains(purchase.merchantBrand)) {
                    return excludedScore(
                        Warning.MERCHANT_NOT_ACCEPTED,
                        "accepted only at ${merchants.joinToString(", ")}"
                    )
                }
            }
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

        // The purchase amount expressed in THIS card's own billingCurrency — 'points per currency
        // unit' means per unit of that currency, not per CAD unconditionally. For a CAD-billing
        // card (every card in this catalogue until the multi-market import) this is exactly
        // `purchase.amountCad`, unchanged.
        val nativeAmount = nativeAmount(purchase, card.billingCurrency)

        var inCapAmount = nativeAmount
        var overCapAmount = 0.0

        if (rule.capId != null) {
            val cap = card.caps.firstOrNull { it.capId == rule.capId }
            if (cap != null) {
                val usage = state.capProgress?.get(rule.capId) ?: 0.0
                val measureAmount = if (cap.measure == CapMeasure.SPEND_USD_EQUIVALENT) {
                    purchase.usdEquivalent ?: (purchase.amountCad * FALLBACK_CAD_TO_USD)
                } else {
                    nativeAmount
                }
                val split = CapMath.split(measureAmount, cap.limit, usage)
                val inFraction = if (measureAmount > 0) split.inCap / measureAmount else 1.0
                inCapAmount = nativeAmount * inFraction
                overCapAmount = nativeAmount - inCapAmount
                if (usage >= cap.limit * 0.9) {
                    warnings.add(Warning.CAP_NEARLY_EXHAUSTED)
                }
            }
        }

        // Cashback earns real money in the card's own billing currency — unlike points, which are
        // a currency-agnostic token whose count does not depend on what currency was spent, a
        // cashback "unit" IS a dollar amount and must be converted to the CAD reporting currency
        // before valueCad's cashback case (units * cadPerDollar) treats it as one. Converted per
        // portion, not once at the end, in case a straddling purchase's post-cap earn is ever a
        // different type than its in-cap earn.
        fun unitsInReportingCurrency(earn: Earn, amount: Double): Double {
            val raw = earnUnits(earn, amount)
            return if (earn is Earn.Cashback) {
                ReportingCurrency.toReporting(Money(raw, card.billingCurrency))
            } else {
                raw
            }
        }

        val postCapEarn = rule.capId?.let { id -> card.caps.firstOrNull { it.capId == id }?.postCapEarn }
        val units = unitsInReportingCurrency(rule.earn, inCapAmount) +
            unitsInReportingCurrency(postCapEarn ?: rule.earn, overCapAmount)

        // Non-null asserted, not `?: 0.0`: the check above proves a valuation exists, and a zero
        // fallback would quietly reinstate the zero-scoring bug if a refactor ever moved it.
        val gross = valueCad(units, card.program.programId, ownerState.valuationsCad, state, ValuationBand.DECLARED)!!
        val grossFloor = valueCad(units, card.program.programId, ownerState.valuationsCad, state, ValuationBand.FLOOR)!!
        val grossAspirational = valueCad(units, card.program.programId, ownerState.valuationsCad, state, ValuationBand.ASPIRATIONAL)!!

        var fxCost = 0.0
        // Compares against THIS card's billing currency, not a hardcoded "CAD".
        if (purchase.currency != card.billingCurrency.rawValue) {
            val fx = RuleMatcher.activeFxRule(card, asOf)
            if (fx != null) {
                if (fx.freeAllowanceCadPerCalendarMonth != null) {
                    warnings.add(Warning.FX_ALLOWANCE_ASSUMED)
                } else {
                    // The spread is charged in the card's own billing currency, then converted to
                    // the CAD reporting figure. For a CAD-billing card this is the identity.
                    fxCost = ReportingCurrency.toReporting(Money(nativeAmount * fx.rate, card.billingCurrency))
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

    /** [amount] is already expressed in the card's own `billingCurrency` — the caller converts. */
    fun earnUnits(earn: Earn, amount: Double): Double {
        return when (earn) {
            is Earn.Points -> amount * earn.pointsPerUnit
            is Earn.Cashback -> amount * earn.rate
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
            is MerchantCreditValuation ->
                units * valuation.cadPerUnit *
                    (if (valuation.usabilityFactorApplied) valuation.optionalUsabilityFactor else 1.0)
            is CroValuation -> units * (
                if (state.croHandling == "autoSell") valuation.faceValueFactorIfAutoSold
                else valuation.defaultHeldRiskFactor
                )
            is CashBackValuation -> units * valuation.cadPerDollar
            // 0.0, never null. null means "unvalued" and excludes the card; this card IS valued,
            // and what it earns is nothing.
            is NoRewardsValuation -> 0.0
        }
    }
}
