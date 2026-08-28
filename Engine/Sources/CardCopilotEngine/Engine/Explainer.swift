import Foundation

public struct Explanation: Equatable, Sendable {
    public let headline: String
    public let why: String
    public let runnerUpLine: String?
    /// Present only when the winner depends on the owner's declared point valuation.
    /// Discloses the assumption and the value at which the advice would change.
    public let valuationLine: String?
    public let warningLines: [String]
}

/// Turns scoring evidence into the sentences the recommendation screen shows.
/// Every recommendation must be explainable — it is a product principle and, under
/// pending federal privacy reform, likely a legal one for automated decisions.
public struct RecommendationExplainer {
    let namesById: [String: String]

    public init(catalogue: Catalogue) {
        namesById = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0.officialName) })
    }

    public func explain(_ recommendation: Recommendation, purchase: PurchaseContext) -> Explanation {
        let name = displayName(recommendation.winner.cardId)
        let verb = recommendation.switchedFromDefault || recommendation.defaultNotAccepted
            ? "Use" : "Stay on"
        let headline = "\(verb) \(name) — about \(money(recommendation.winner.netValueCad)) back on this \(money(purchase.amountCad)) purchase."

        let why: String
        if let rule = recommendation.winner.appliedRuleId {
            let fxClause = recommendation.winner.fxCostCad > 0
                ? " minus \(money(recommendation.winner.fxCostCad)) foreign-transaction fee."
                : "."
            why = "Applied rule \(rule): \(money(recommendation.winner.grossRewardCad)) in rewards\(fxClause)"
        } else {
            why = "No earn rule applied."
        }

        var runnerUpLine: String?
        if let suppressed = recommendation.suppressedBetterCard {
            let delta = suppressed.netValueCad - recommendation.winner.netValueCad
            runnerUpLine = "\(displayName(suppressed.cardId)) is marginally better (+\(money(delta))) — not worth the wallet dig."
        } else if let runnerUp = recommendation.runnerUp {
            let delta = recommendation.winner.netValueCad - runnerUp.netValueCad
            runnerUpLine = "Next best: \(displayName(runnerUp.cardId)) (\(money(runnerUp.netValueCad))) — you'd give up \(money(delta))."
        }

        var valuationLine: String?
        if recommendation.valuationSensitive,
           let declared = recommendation.declaredCentsPerPoint,
           let breakeven = recommendation.breakevenCentsPerPoint,
           let alternate = recommendation.alternateWinnerCardId,
           let direction = recommendation.valuationDirection {
            let side = direction == .below ? "Below" : "Above"
            valuationLine = "Assumes your points are worth \(cents(declared)) each. "
                + "\(side) about \(cents(breakeven)), \(displayName(alternate)) wins instead."
        }

        return Explanation(headline: headline, why: why, runnerUpLine: runnerUpLine,
                           valuationLine: valuationLine,
                           warningLines: recommendation.winner.warnings.map(line(for:)))
    }

    private func line(for warning: Warning) -> String {
        switch warning {
        case .drawerCard: return "This card is in your drawer — bring it or take the runner-up."
        case .capNearlyExhausted: return "Category cap nearly used up — the winner may flip soon."
        case .negativeNetValue: return "This card would LOSE money here after fees."
        case .networkNotAccepted: return "Card network not accepted at this merchant."
        // Excluded-only, like .productWithdrawn and .draftProduct below: a card the
        // merchant does not accept is never the winner, so this never travels with a
        // Recommendation. Worded as a fact about where the card works rather than an
        // instruction, because the only action available is the pick already named.
        case .merchantNotAccepted: return "This is a store card and only works at its own merchant."
        case .unresolvedOwnerState: return "Card skipped — account state not set up yet."
        case .fxAllowanceAssumed: return "Assumed within this card's monthly FX-free allowance."
        case .hypotheticalSelection: return "Assumes this is one of your selected 2% categories — check your selections."
        case .unsupportedProgram: return "Card skipped — you haven't set what this card's rewards are worth."
        // Reachable on a card that WON: the excluded case never reaches an explanation, because
        // an excluded card is never the winner. Worded for the case the owner can actually see.
        case .unsupportedCapability: return "This card has a better rule here that this app can't check yet — it may be worth more than shown."
        // Also excluded-only, for the same reason. Worded as a fact about the product rather than
        // an instruction, because there is no action the owner can take on a discontinued card.
        case .productWithdrawn: return "This card has been discontinued and is no longer recommended."
        // Never reachable on a winner: a draft card is excluded before scoring, so this warning
        // never travels with a Recommendation. Listed for exhaustiveness only.
        case .draftProduct: return "This card is a research-grade catalogue entry and should not have been scorable."
        }
    }

    private func displayName(_ cardId: String) -> String { namesById[cardId] ?? cardId }

    private func money(_ value: Double) -> String { String(format: "$%.2f", value) }

    private func cents(_ value: Double) -> String { String(format: "%.2f¢", value) }
}
