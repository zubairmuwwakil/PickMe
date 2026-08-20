import Foundation

public enum Warning: String, Codable, Equatable, Sendable {
    case drawerCard, unresolvedOwnerState, networkNotAccepted,
         capNearlyExhausted, negativeNetValue, fxAllowanceAssumed, hypotheticalSelection
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

    public static func score(card: CardProduct, purchase: PurchaseContext,
                             ownerState: OwnerState, asOf: String) -> CandidateScore {
        func excludedScore(_ warning: Warning, _ reason: String) -> CandidateScore {
            CandidateScore(cardId: card.cardId, appliedRuleId: nil, rewardUnits: 0,
                           grossRewardCad: 0, fxCostCad: 0, netValueCad: 0, floorNetValueCad: 0,
                           aspirationalNetValueCad: 0,
                           warnings: [warning], excluded: true, exclusionReason: reason)
        }

        guard purchase.acceptedNetworks.contains(card.network) else {
            return excludedScore(.networkNotAccepted, "\(card.network.rawValue) not accepted")
        }

        let rule: EarnRule
        switch RuleMatcher.resolve(card: card, purchase: purchase, ownerState: ownerState, asOf: asOf) {
        case .cardExcluded(let reason): return excludedScore(.unresolvedOwnerState, reason)
        case .applied(let matched): rule = matched
        }

        var warnings: [Warning] = []
        let state = ownerState.cardStates[card.cardId] ?? CardState()

        var inCapCad = purchase.amountCad
        var overCapCad = 0.0
        if let capId = rule.capId, let cap = card.caps.first(where: { $0.capId == capId }) {
            let usage = state.capProgress?[capId] ?? 0
            let measureAmount = cap.measure == .spendUsdEquivalent
                ? (purchase.usdEquivalent ?? purchase.amountCad * fallbackCadToUsd)
                : purchase.amountCad
            let split = CapMath.split(amount: measureAmount, capLimit: cap.limit, usage: usage)
            let inFraction = measureAmount > 0 ? split.inCap / measureAmount : 1
            inCapCad = purchase.amountCad * inFraction
            overCapCad = purchase.amountCad - inCapCad
            if usage >= cap.limit * 0.9 { warnings.append(.capNearlyExhausted) }
        }

        let postCapEarn = rule.capId.flatMap { id in card.caps.first { $0.capId == id }?.postCapEarn }
        let units = earnUnits(rule.earn, amountCad: inCapCad)
            + earnUnits(postCapEarn ?? rule.earn, amountCad: overCapCad)
        let gross = valueCad(units: units, program: card.program.programId,
                             valuations: ownerState.valuationsCad, state: state)
        let grossFloor = valueCad(units: units, program: card.program.programId,
                                  valuations: ownerState.valuationsCad, state: state,
                                  band: .floor)
        let grossAspirational = valueCad(units: units, program: card.program.programId,
                                         valuations: ownerState.valuationsCad, state: state,
                                         band: .aspirational)

        var fxCost = 0.0
        if purchase.currency != "CAD", let fx = RuleMatcher.activeFxRule(for: card, asOf: asOf) {
            if fx.freeAllowanceCadPerCalendarMonth != nil {
                warnings.append(.fxAllowanceAssumed)
            } else {
                fxCost = purchase.amountCad * fx.rate
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

    static func earnUnits(_ earn: Earn, amountCad: Double) -> Double {
        switch earn {
        case .points(let p): return amountCad * p
        case .cashback(let r, _): return amountCad * r
        case .centsPerLitre: return 0
        }
    }

    /// Which point of a program's plausible valuation range to use.
    enum ValuationBand { case declared, floor, aspirational }

    static func valueCad(units: Double, program: String,
                         valuations: Valuations, state: CardState,
                         band: ValuationBand = .declared) -> Double {
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
        // to remove. A program with no valuation still yields 0.0 here; excluding the card
        // instead is Scorer's next change, not this one.
        switch valuations[program] {
        case .points(let v):
            return units * cents(v) / 100
        case .ctMoney(let v):
            return units * v.cadPerUnit * (v.usabilityFactorApplied ? v.optionalUsabilityFactor : 1)
        case .cro(let v):
            return units * (state.croHandling == "autoSell"
                            ? v.faceValueFactorIfAutoSold : v.defaultHeldRiskFactor)
        case .cashback(let v):
            return units * v.cadPerDollar
        case nil:
            return 0.0
        }
    }
}
