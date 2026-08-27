import Foundation

public enum Warning: String, Codable, Equatable, Sendable {
    case drawerCard, unresolvedOwnerState, networkNotAccepted,
         capNearlyExhausted, negativeNetValue, fxAllowanceAssumed, hypotheticalSelection,
         /// This card's rewards program has no valuation. The card cannot be scored at all —
         /// distinct from being scored and losing.
         unsupportedProgram,
         /// An earn rule requires an engine capability this build does not have. The rule is
         /// skipped; the card is still scored on its remaining rules.
         unsupportedCapability,
         /// The issuer has discontinued this product as of the scored date. Its own case rather
         /// than borrowing `drawerCard`: that one means "you left it at home", which is advice a
         /// withdrawn card cannot act on. Warnings are frozen into the append-only prediction log
         /// now, so a borrowed one would be a wrong record that can never be corrected.
         productWithdrawn,
         /// `card.status == .draft` — a research-grade catalogue record that has not cleared D3's
         /// issuer-confirmed sourcing bar. Excluded outright, never merely scored with a caveat:
         /// a draft record must never produce a checkout pick, even if it somehow appears in
         /// `ownedCardIds`.
         draftProduct
}

public struct CandidateScore: Equatable, Sendable {
    public let cardId: String
    public let appliedRuleId: String?
    public let rewardUnits: Double
    public let grossRewardCad: Double
    public let fxCostCad: Double
    public let netValueCad: Double
    /// Net value if points are redeemed at their guaranteed cash floor rather than the
    /// owner's declared value. Equal to `netValueCad` for cash-back and floorless programs.
    public let floorNetValueCad: Double
    /// Net value at the program's published benchmark valuation, when one is set.
    public let aspirationalNetValueCad: Double
    public let warnings: [Warning]
    public let excluded: Bool
    public let exclusionReason: String?
}

/// Turns one card's matched earn rule into a net CAD value for this purchase.
public enum Scorer {

    /// Fallback CAD-to-USD rate, used only when a USD-measured cap must be checked and the
    /// caller supplied no converted amount. Only Crypto.com's monthly cap uses this measure.
    static let fallbackCadToUsd = 0.73

    /// The purchase amount expressed in a card's own `billingCurrency` — 'points per currency
    /// unit' means per unit of that currency, not per CAD unconditionally. For a CAD-billing
    /// card (every card in this catalogue until the multi-market import) this is exactly
    /// `purchase.amountCad`, unchanged. A USD-billing card reuses `usdEquivalent`, the same
    /// field `spendUsdEquivalent` caps already relied on, falling back to the same pinned
    /// `fallbackCadToUsd` approximation when the caller supplied no converted amount.
    ///
    /// Shared with `PortfolioAnalyzer.accrueCapProgress` so a `.spendNative` cap is always
    /// compared and accrued in the same currency `score(card:purchase:ownerState:asOf:)` uses —
    /// the two must never independently decide what "native" means for the same card.
    static func nativeAmount(for purchase: PurchaseContext, billingCurrency: Currency) -> Double {
        billingCurrency == .usd
            ? (purchase.usdEquivalent ?? purchase.amountCad * fallbackCadToUsd)
            : purchase.amountCad
    }

    public static func score(card: CardProduct, purchase: PurchaseContext,
                             ownerState: OwnerState, asOf: String) -> CandidateScore {
        func excludedScore(_ warning: Warning, _ reason: String) -> CandidateScore {
            CandidateScore(cardId: card.cardId, appliedRuleId: nil, rewardUnits: 0,
                           grossRewardCad: 0, fxCostCad: 0, netValueCad: 0, floorNetValueCad: 0,
                           aspirationalNetValueCad: 0,
                           warnings: [warning], excluded: true, exclusionReason: reason)
        }

        // First guard of all: a discontinued product cannot win a pick regardless of what it
        // would have earned. It stays in the catalogue and stays resolvable by id — this excludes
        // it from advice, not from history.
        guard card.isScoreable(asOf: asOf) else {
            return excludedScore(.productWithdrawn, "product withdrawn")
        }

        guard card.isPublished else {
            return excludedScore(.draftProduct, "draft catalogue record, not yet issuer-verified")
        }

        guard purchase.acceptedNetworks.contains(card.network) else {
            return excludedScore(.networkNotAccepted, "\(card.network.rawValue) not accepted")
        }

        let rule: EarnRule
        let capabilityGaps: [String]
        switch RuleMatcher.resolve(card: card, purchase: purchase, ownerState: ownerState, asOf: asOf) {
        case .cardExcluded(let reason, let warning): return excludedScore(warning, reason)
        case .applied(let matched, let gaps): rule = matched; capabilityGaps = gaps
        }

        var warnings: [Warning] = []
        // A better rule matched this purchase and this build could not run it. The card keeps the
        // number it can defend, and the owner is told the number is not the whole story.
        if !capabilityGaps.isEmpty { warnings.append(.unsupportedCapability) }
        let state = ownerState.cardStates[card.cardId] ?? CardState()

        // Ask before earning, not after: a program with no valuation cannot produce an honest
        // number, and the honest answer is a refusal that names the gap. `units: 0` makes this a
        // pure presence check — no model here can turn a missing valuation into a value.
        guard valueCad(units: 0, program: card.program.programId,
                       valuations: ownerState.valuationsCad, state: state) != nil else {
            return excludedScore(.unsupportedProgram,
                                 "no valuation for program \(card.program.programId)")
        }

        let nativeAmount = nativeAmount(for: purchase, billingCurrency: card.billingCurrency)

        var inCapAmount = nativeAmount
        var overCapAmount = 0.0
        if let capId = rule.capId, let cap = card.caps.first(where: { $0.capId == capId }) {
            let usage = state.capProgress?[capId] ?? 0
            let measureAmount = cap.measure == .spendUsdEquivalent
                ? (purchase.usdEquivalent ?? purchase.amountCad * fallbackCadToUsd)
                : nativeAmount
            let split = CapMath.split(amount: measureAmount, capLimit: cap.limit, usage: usage)
            let inFraction = measureAmount > 0 ? split.inCap / measureAmount : 1
            inCapAmount = nativeAmount * inFraction
            overCapAmount = nativeAmount - inCapAmount
            if usage >= cap.limit * 0.9 { warnings.append(.capNearlyExhausted) }
        }

        // Cashback earns real money in the card's own billing currency — unlike points, which are
        // a currency-agnostic token whose *count* does not depend on what currency was spent, a
        // cashback "unit" IS a dollar amount and must be converted to the CAD reporting currency
        // before `valueCad`'s cashback case (`units * cadPerDollar`) treats it as one. Converted
        // per portion, not once at the end, in case a straddling purchase's post-cap earn is ever
        // a different type than its in-cap earn.
        func unitsInReportingCurrency(_ earn: Earn, amount: Double) -> Double {
            let raw = earnUnits(earn, amount: amount)
            if case .cashback = earn {
                return ReportingCurrency.toReporting(Money(amount: raw, currency: card.billingCurrency))
            }
            return raw
        }

        let postCapEarn = rule.capId.flatMap { id in card.caps.first { $0.capId == id }?.postCapEarn }
        let units = unitsInReportingCurrency(rule.earn, amount: inCapAmount)
            + unitsInReportingCurrency(postCapEarn ?? rule.earn, amount: overCapAmount)
        // Force-unwrapped, not `?? 0`: the guard above proves a valuation exists, and `?? 0`
        // would quietly reinstate the zero-scoring bug if a refactor ever moved that guard.
        let gross = valueCad(units: units, program: card.program.programId,
                             valuations: ownerState.valuationsCad, state: state)!
        let grossFloor = valueCad(units: units, program: card.program.programId,
                                  valuations: ownerState.valuationsCad, state: state,
                                  band: .floor)!
        let grossAspirational = valueCad(units: units, program: card.program.programId,
                                         valuations: ownerState.valuationsCad, state: state,
                                         band: .aspirational)!

        var fxCost = 0.0
        // Compares against THIS card's billing currency, not a hardcoded "CAD" — an FX spread
        // applies whenever the purchase's currency differs from what the card bills in, in
        // either direction.
        if purchase.currency != card.billingCurrency.rawValue,
           let fx = RuleMatcher.activeFxRule(for: card, asOf: asOf) {
            if fx.freeAllowanceCadPerCalendarMonth != nil {
                warnings.append(.fxAllowanceAssumed)
            } else {
                // The spread is charged in the card's own billing currency, then converted to the
                // CAD reporting figure. For a CAD-billing card this `toReporting` is the identity
                // — exactly today's `purchase.amountCad * fx.rate`.
                fxCost = ReportingCurrency.toReporting(
                    Money(amount: nativeAmount * fx.rate, currency: card.billingCurrency))
            }
        }

        let net = gross - fxCost
        if net < 0 { warnings.append(.negativeNetValue) }
        if ownerState.carry.drawerCards.contains(card.cardId) { warnings.append(.drawerCard) }
        if rule.ruleId == "tangerine-selected-2pct", state.treatAsAllSelected == true {
            warnings.append(.hypotheticalSelection)
        }

        return CandidateScore(cardId: card.cardId, appliedRuleId: rule.ruleId, rewardUnits: units,
                              grossRewardCad: gross, fxCostCad: fxCost, netValueCad: net,
                              floorNetValueCad: grossFloor - fxCost,
                              aspirationalNetValueCad: grossAspirational - fxCost,
                              warnings: warnings, excluded: false, exclusionReason: nil)
    }

    /// `amount` is already expressed in the card's own `billingCurrency` — the caller
    /// (`score(card:purchase:ownerState:asOf:)`) converts before calling this.
    static func earnUnits(_ earn: Earn, amount: Double) -> Double {
        switch earn {
        case .points(let p): return amount * p
        case .cashback(let r, _): return amount * r
        case .centsPerLitre: return 0
        }
    }

    /// Which point of a program's plausible valuation range to use.
    enum ValuationBand { case declared, floor, aspirational }

    /// Nil means the program has no valuation — the card cannot be scored. Zero means the
    /// program is valued and this earn is worth nothing. Conflating them is how ten programs
    /// silently ranked last for four release batches.
    ///
    /// A pure function of the `valuations` passed in: catalogue defaults are merged into owner
    /// state up in `RecommendationEngine.init`, deliberately not here, so a caller holding an
    /// empty `Valuations` gets nil rather than a value it never declared.
    static func valueCad(units: Double, program: String,
                         valuations: Valuations, state: CardState,
                         band: ValuationBand = .declared) -> Double? {
        func cents(_ v: PointValuation) -> Double {
            switch band {
            case .declared: return v.centsPerPoint
            case .floor: return v.floorCentsPerPoint ?? v.centsPerPoint
            case .aspirational: return max(v.aspirationalCentsPerPoint ?? v.centsPerPoint,
                                           v.centsPerPoint)
            }
        }
        // Dispatch on the valuation's model, not on the program's name. The name-keyed switch
        // this replaced could only ever value the six programs it listed, so a program gaining a
        // valuation still had to gain a Swift case — which is the coupling this refactor exists
        // to remove.
        guard let valuation = valuations[program] else { return nil }
        switch valuation {
        case .points(let v):
            return units * cents(v) / 100
        case .ctMoney(let v):
            return units * v.cadPerUnit * (v.usabilityFactorApplied ? v.optionalUsabilityFactor : 1)
        case .cro(let v):
            return units * (state.croHandling == "autoSell"
                            ? v.faceValueFactorIfAutoSold : v.defaultHeldRiskFactor)
        case .cashback(let v):
            return units * v.cadPerDollar
        case .noRewards:
            // 0.0, never nil. nil means "unvalued" and excludes the card; this card IS valued,
            // and what it earns is nothing. Collapsing the two would hide a real product from a
            // comparison it belongs in — a no-rewards card is a legitimate answer to "which card
            // should I use" when every alternative is worse for another reason.
            return 0
        }
    }
}
