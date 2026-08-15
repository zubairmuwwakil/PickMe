import Foundation

public struct Recommendation: Equatable, Sendable {
    public let winner: CandidateScore
    public let runnerUp: CandidateScore?
    public let switchedFromDefault: Bool
    public let advantageOverDefaultCad: Double?
    public let defaultNotAccepted: Bool
    /// A card that beat the default but not by enough to be worth digging out the wallet.
    public let suppressedBetterCard: CandidateScore?
    /// True when the winner depends on the owner's declared point valuation: ranking by the
    /// guaranteed cash floor instead would pick a different card.
    public let valuationSensitive: Bool
    /// The card that wins under floor valuation, when that differs from the winner.
    public let floorWinnerCardId: String?
    /// The declared cents-per-point below which the recommendation flips to the floor winner.
    public let breakevenCentsPerPoint: Double?
    /// The declared cents-per-point the winning score assumed, when valuation-sensitive.
    public let declaredCentsPerPoint: Double?
    public let allCandidates: [CandidateScore]
}

public struct RecommendationEngine {
    let catalogue: Catalogue
    let ownerState: OwnerState

    public init(catalogue: Catalogue, ownerState: OwnerState) {
        self.catalogue = catalogue
        self.ownerState = ownerState
    }

    private struct Verdict {
        let winner: CandidateScore
        let runnerUp: CandidateScore?
        let switched: Bool
        let advantage: Double?
        let defaultNotAccepted: Bool
        let suppressed: CandidateScore?
        let ranked: [CandidateScore]
    }

    public func recommend(_ purchase: PurchaseContext, asOf: String) -> Recommendation {
        let scores = catalogue.cards
            .map { Scorer.score(card: $0, purchase: purchase, ownerState: ownerState, asOf: asOf) }
            .filter { !$0.excluded }
        precondition(!scores.isEmpty, "no scorable card — catalogue misconfigured")

        let declared = rank(scores, purchase: purchase, value: { $0.netValueCad })
        let floor = rank(scores, purchase: purchase, value: { $0.floorNetValueCad })

        var sensitive = false
        var floorWinnerId: String?
        var breakeven: Double?
        var declaredCents: Double?
        // Sensitivity exists only when the declared-value winner is a floor-distinct points
        // card and floor-ranking would pick someone else.
        if declared.winner.cardId != floor.winner.cardId,
           abs(declared.winner.floorNetValueCad - declared.winner.netValueCad) > 0.0001,
           declared.winner.rewardUnits > 0 {
            sensitive = true
            floorWinnerId = floor.winner.cardId
            breakeven = breakevenCents(for: declared, floorWinner: floor.winner, purchase: purchase)
            declaredCents = (declared.winner.grossRewardCad / declared.winner.rewardUnits) * 100
        }

        return Recommendation(winner: declared.winner,
                              runnerUp: declared.runnerUp,
                              switchedFromDefault: declared.switched,
                              advantageOverDefaultCad: declared.advantage,
                              defaultNotAccepted: declared.defaultNotAccepted,
                              suppressedBetterCard: declared.suppressed,
                              valuationSensitive: sensitive,
                              floorWinnerCardId: floorWinnerId,
                              breakevenCentsPerPoint: breakeven,
                              declaredCentsPerPoint: declaredCents,
                              allCandidates: declared.ranked)
    }

    /// The declared cents-per-point at which the winner's net value stops beating both the
    /// floor winner and (with the switch threshold applied) the default card. Verified against
    /// bisection over the full engine in BreakevenValuationTests.
    private func breakevenCents(for declared: Verdict, floorWinner: CandidateScore,
                                purchase: PurchaseContext) -> Double {
        let t = ownerState.switchThreshold
        let ppFloorCad = t.minAdvantagePercentagePoints * purchase.amountCad / 100
        let requiredAdvantage = t.semantics == "either"
            ? min(t.minAdvantageCad, ppFloorCad)
            : max(t.minAdvantageCad, ppFloorCad)
        let defaultId = ownerState.defaultCardId

        var needed = floorWinner.netValueCad
            + (floorWinner.cardId == defaultId ? requiredAdvantage : 0)
        if floorWinner.cardId != defaultId,
           let defaultScore = declared.ranked.first(where: { $0.cardId == defaultId }) {
            needed = max(needed, defaultScore.netValueCad + requiredAdvantage)
        }
        return (needed + declared.winner.fxCostCad) * 100 / declared.winner.rewardUnits
    }

    private func rank(_ scores: [CandidateScore], purchase: PurchaseContext,
                      value: (CandidateScore) -> Double) -> Verdict {
        let defaultId = ownerState.defaultCardId
        let ranked = scores.sorted { a, b in
            if value(a) != value(b) { return value(a) > value(b) }
            if a.cardId == defaultId { return true }
            if b.cardId == defaultId { return false }
            return a.cardId < b.cardId
        }

        let best = ranked[0]
        let runnerUp = ranked.count > 1 ? ranked[1] : nil

        guard let defaultScore = ranked.first(where: { $0.cardId == defaultId }) else {
            return Verdict(winner: best, runnerUp: runnerUp, switched: true, advantage: nil,
                           defaultNotAccepted: true, suppressed: nil, ranked: ranked)
        }

        let advantage = value(best) - value(defaultScore)
        let advantagePP = purchase.amountCad > 0 ? advantage / purchase.amountCad * 100 : 0
        let t = ownerState.switchThreshold
        let cadOk = advantage >= t.minAdvantageCad
        let ppOk = advantagePP >= t.minAdvantagePercentagePoints
        let clearsThreshold = t.semantics == "either" ? (cadOk || ppOk) : (cadOk && ppOk)

        if best.cardId != defaultId && clearsThreshold {
            return Verdict(winner: best, runnerUp: runnerUp, switched: true, advantage: advantage,
                           defaultNotAccepted: false, suppressed: nil, ranked: ranked)
        }

        let suppressed = (best.cardId != defaultId && advantage > 0) ? best : nil
        return Verdict(winner: defaultScore,
                       runnerUp: ranked.first { $0.cardId != defaultId },
                       switched: false, advantage: 0,
                       defaultNotAccepted: false, suppressed: suppressed, ranked: ranked)
    }
}
