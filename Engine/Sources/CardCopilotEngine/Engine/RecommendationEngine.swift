import Foundation

public struct Recommendation: Equatable, Sendable {
    public let winner: CandidateScore
    public let runnerUp: CandidateScore?
    public let switchedFromDefault: Bool
    public let advantageOverDefaultCad: Double?
    public let defaultNotAccepted: Bool
    /// A card that beat the default but not by enough to be worth digging out the wallet.
    public let suppressedBetterCard: CandidateScore?
    public let allCandidates: [CandidateScore]
}

public struct RecommendationEngine {
    let catalogue: Catalogue
    let ownerState: OwnerState

    public init(catalogue: Catalogue, ownerState: OwnerState) {
        self.catalogue = catalogue
        self.ownerState = ownerState
    }

    public func recommend(_ purchase: PurchaseContext, asOf: String) -> Recommendation {
        let defaultId = ownerState.defaultCardId
        let ranked = catalogue.cards
            .map { Scorer.score(card: $0, purchase: purchase, ownerState: ownerState, asOf: asOf) }
            .filter { !$0.excluded }
            .sorted { a, b in
                if a.netValueCad != b.netValueCad { return a.netValueCad > b.netValueCad }
                if a.cardId == defaultId { return true }
                if b.cardId == defaultId { return false }
                return a.cardId < b.cardId
            }
        precondition(!ranked.isEmpty, "no scorable card — catalogue misconfigured")

        let best = ranked[0]
        let runnerUp = ranked.count > 1 ? ranked[1] : nil

        guard let defaultScore = ranked.first(where: { $0.cardId == defaultId }) else {
            return Recommendation(winner: best, runnerUp: runnerUp, switchedFromDefault: true,
                                  advantageOverDefaultCad: nil, defaultNotAccepted: true,
                                  suppressedBetterCard: nil, allCandidates: ranked)
        }

        let advantage = best.netValueCad - defaultScore.netValueCad
        let advantagePP = purchase.amountCad > 0 ? advantage / purchase.amountCad * 100 : 0
        let threshold = ownerState.switchThreshold
        let cadOk = advantage >= threshold.minAdvantageCad
        let ppOk = advantagePP >= threshold.minAdvantagePercentagePoints
        let clearsThreshold = threshold.semantics == "either" ? (cadOk || ppOk) : (cadOk && ppOk)

        if best.cardId != defaultId && clearsThreshold {
            return Recommendation(winner: best, runnerUp: runnerUp, switchedFromDefault: true,
                                  advantageOverDefaultCad: advantage, defaultNotAccepted: false,
                                  suppressedBetterCard: nil, allCandidates: ranked)
        }

        let suppressed = (best.cardId != defaultId && advantage > 0) ? best : nil
        return Recommendation(winner: defaultScore,
                              runnerUp: ranked.first { $0.cardId != defaultId },
                              switchedFromDefault: false,
                              advantageOverDefaultCad: 0, defaultNotAccepted: false,
                              suppressedBetterCard: suppressed, allCandidates: ranked)
    }
}
