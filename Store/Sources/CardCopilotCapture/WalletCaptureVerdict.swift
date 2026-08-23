import CardCopilotEngine
import Foundation

public struct WalletCaptureVerdict: Sendable, Equatable {
    public let usedCardID: String
    public let recommendedCardID: String
    public let advantageCad: Double
}

public enum WalletCaptureVerdictEvaluator {
    /// Conservative by design: no FX guess and no card-string guess enters a user-facing warning.
    public static func evaluate(event: WalletCaptureEvent, catalogue: Catalogue, ownerState: OwnerState,
                                usedCardID: String?, category: String) -> WalletCaptureVerdict? {
        guard let usedCardID,
              event.transaction.currencyRaw?.uppercased() == "CAD",
              let amountText = event.transaction.amountDecimal,
              let amount = Double(amountText), amount > 0,
              case .advised(let recommendation) = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
                .recommend(.init(amountCad: amount, currency: "CAD", category: category,
                                 merchantBrand: event.transaction.merchantRaw),
                           asOf: event.capturedAt.formatted(.iso8601.year().month().day())),
              recommendation.winner.cardId != usedCardID,
              let used = recommendation.allCandidates.first(where: { $0.cardId == usedCardID }) else { return nil }
        let advantage = recommendation.winner.netValueCad - used.netValueCad
        let advantagePP = amount > 0 ? advantage / amount * 100 : 0
        let threshold = ownerState.switchThreshold
        let clearsCad = advantage >= threshold.minAdvantageCad
        let clearsPercentage = advantagePP >= threshold.minAdvantagePercentagePoints
        let clearsThreshold = threshold.semantics == "either"
            ? (clearsCad || clearsPercentage)
            : (clearsCad && clearsPercentage)
        guard advantage > 0, clearsThreshold else { return nil }
        return .init(usedCardID: usedCardID, recommendedCardID: recommendation.winner.cardId,
                     advantageCad: advantage)
    }
}
