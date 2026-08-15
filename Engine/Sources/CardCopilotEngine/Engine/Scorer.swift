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
                           grossRewardCad: 0, fxCostCad: 0, netValueCad: 0,
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
                              warnings: warnings, excluded: false, exclusionReason: nil)
    }

    static func earnUnits(_ earn: Earn, amountCad: Double) -> Double {
        switch earn {
        case .points(let p): return amountCad * p
        case .cashback(let r, _): return amountCad * r
        case .centsPerLitre: return 0
        }
    }

    static func valueCad(units: Double, program: String,
                         valuations: Valuations, state: CardState) -> Double {
        switch program {
        case "amexMembershipRewards": return units * valuations.amexMembershipRewards.centsPerPoint / 100
        case "marriottBonvoy": return units * valuations.marriottBonvoy.centsPerPoint / 100
        case "mbnaRewards": return units * valuations.mbnaRewards.centsPerPoint / 100
        case "ctMoney":
            let v = valuations.ctMoney
            return units * v.cadPerUnit * (v.usabilityFactorApplied ? v.optionalUsabilityFactor : 1)
        case "cro":
            let factor = state.croHandling == "autoSell"
                ? valuations.cro.faceValueFactorIfAutoSold
                : valuations.cro.defaultHeldRiskFactor
            return units * factor
        default: return units * valuations.cashBack.cadPerDollar
        }
    }
}
