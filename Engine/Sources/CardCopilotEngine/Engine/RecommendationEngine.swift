import Foundation

public struct Recommendation: Equatable, Sendable {
    public let winner: CandidateScore
    public let runnerUp: CandidateScore?
    public let switchedFromDefault: Bool
    public let advantageOverDefaultCad: Double?
    public let defaultNotAccepted: Bool
    /// A card that beat the default but not by enough to be worth digging out the wallet.
    public let suppressedBetterCard: CandidateScore?
    /// True when the winner depends on the owner's declared point valuation — valuing points
    /// lower (or higher) would pick a different card.
    public let valuationSensitive: Bool
    /// Which way the declared valuation would have to move to change the advice.
    public let valuationDirection: ValuationDirection?
    /// The card that wins on the other side of the breakeven.
    public let alternateWinnerCardId: String?
    /// The cents-per-point at which the recommendation flips to `alternateWinnerCardId`.
    public let breakevenCentsPerPoint: Double?
    /// The declared cents-per-point the winning score assumed, when valuation-sensitive.
    public let declaredCentsPerPoint: Double?
    public let allCandidates: [CandidateScore]
}

/// Which direction the point valuation would have to move for the advice to change.
public enum ValuationDirection: Sendable, Equatable { case below, above }

public struct RecommendationEngine {
    let catalogue: Catalogue
    let ownerState: OwnerState

    /// Catalogue valuation defaults are merged in here, beneath anything the owner has declared.
    /// This is the single funnel every scoring path reaches — including owner states restored
    /// from a device, which never touch SeedLoader. Without it contracts/programs.json would be
    /// data nothing reads.
    public init(catalogue: Catalogue, ownerState: OwnerState) {
        self.catalogue = catalogue
        self.ownerState = ownerState.applyingCatalogueValuationDefaults()
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
        let candidateCards = ownerState.ownedCardIds.isEmpty
            ? catalogue.cards
            : catalogue.cards.filter { ownerState.ownedCardIds.contains($0.cardId) }
        let scores = candidateCards
            .map { Scorer.score(card: $0, purchase: purchase, ownerState: ownerState, asOf: asOf) }
            .filter { !$0.excluded }
        precondition(!scores.isEmpty, "no scorable card — catalogue misconfigured")

        let declared = rank(scores, purchase: purchase, value: { $0.netValueCad })
        let floor = rank(scores, purchase: purchase, value: { $0.floorNetValueCad })
        let aspirational = rank(scores, purchase: purchase, value: { $0.aspirationalNetValueCad })

        var sensitive = false
        var direction: ValuationDirection?
        var alternateId: String?
        var breakeven: Double?
        var declaredCents: Double?

        // Downside: the winner is a points card that only wins because points are declared
        // above their guaranteed floor.
        if declared.winner.cardId != floor.winner.cardId,
           abs(declared.winner.floorNetValueCad - declared.winner.netValueCad) > 0.0001,
           declared.winner.rewardUnits > 0 {
            sensitive = true
            direction = .below
            alternateId = floor.winner.cardId
            breakeven = breakevenCents(pointsCard: declared.winner,
                                       incumbent: floor.winner,
                                       ranked: declared.ranked, purchase: purchase)
            declaredCents = centsPerUnit(declared.winner)
        }
        // Upside: a points card would overtake the winner if points were worth more. Only
        // disclosed when the flip happens within the published benchmark — past that it is
        // noise, not information.
        else if aspirational.winner.cardId != declared.winner.cardId,
                aspirational.winner.rewardUnits > 0,
                abs(aspirational.winner.aspirationalNetValueCad
                    - aspirational.winner.netValueCad) > 0.0001,
                let challenger = declared.ranked.first(where: { $0.cardId == aspirational.winner.cardId }) {
            let flip = breakevenCents(pointsCard: challenger,
                                      incumbent: declared.winner,
                                      ranked: declared.ranked, purchase: purchase)
            let benchmarkCents = (challenger.aspirationalNetValueCad + challenger.fxCostCad)
                * 100 / challenger.rewardUnits
            if flip <= benchmarkCents + 0.0001 {
                sensitive = true
                direction = .above
                alternateId = challenger.cardId
                breakeven = flip
                // The disclosed value is the challenger's currency — that is the number the
                // owner would be revising, not the cash-back winner's notional "unit" value.
                declaredCents = centsPerUnit(challenger)
            }
        }

        return Recommendation(winner: declared.winner,
                              runnerUp: declared.runnerUp,
                              switchedFromDefault: declared.switched,
                              advantageOverDefaultCad: declared.advantage,
                              defaultNotAccepted: declared.defaultNotAccepted,
                              suppressedBetterCard: declared.suppressed,
                              valuationSensitive: sensitive,
                              valuationDirection: direction,
                              alternateWinnerCardId: alternateId,
                              breakevenCentsPerPoint: breakeven,
                              declaredCentsPerPoint: declaredCents,
                              allCandidates: declared.ranked)
    }

    private func centsPerUnit(_ score: CandidateScore) -> Double {
        score.rewardUnits > 0 ? (score.grossRewardCad / score.rewardUnits) * 100 : 0
    }

    /// The cents-per-point at which `pointsCard` and `incumbent` swap places, accounting for
    /// the switch threshold that applies against the default card. Cross-validated against
    /// bisection over the full engine in BreakevenCrossValidationTests.
    private func breakevenCents(pointsCard: CandidateScore, incumbent: CandidateScore,
                                ranked: [CandidateScore], purchase: PurchaseContext) -> Double {
        let t = ownerState.switchThreshold
        let ppFloorCad = t.minAdvantagePercentagePoints * purchase.amountCad / 100
        let requiredAdvantage = t.semantics == "either"
            ? min(t.minAdvantageCad, ppFloorCad)
            : max(t.minAdvantageCad, ppFloorCad)
        let defaultId = ownerState.defaultCardId

        // The points card must clear the incumbent, plus the switch threshold over the default.
        var needed = incumbent.netValueCad
            + (incumbent.cardId == defaultId ? requiredAdvantage : 0)
        if incumbent.cardId != defaultId, pointsCard.cardId != defaultId,
           let defaultScore = ranked.first(where: { $0.cardId == defaultId }) {
            needed = max(needed, defaultScore.netValueCad + requiredAdvantage)
        }
        return (needed + pointsCard.fxCostCad) * 100 / pointsCard.rewardUnits
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
