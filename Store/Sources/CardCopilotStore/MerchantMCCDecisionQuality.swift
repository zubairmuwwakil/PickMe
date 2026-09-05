import Foundation
import CardCopilotEngine

/// Aggregate-only answer to the two product questions the MCC graph exists to improve:
///
/// 1. Does MCC uncertainty actually change which card wins?
/// 2. Did runtime evidence change the decision relative to the shipped/static baseline?
///
/// No merchant, MCC, category, card id, coordinate, or timestamp is retained by the metrics store.
struct MerchantMCCDecisionQualityAssessment: Equatable, Sendable {
    let hasMultiplePlausibleMCCs: Bool
    /// nil when fewer than two plausible branches can be scored. `false` means all scoreable
    /// plausible MCC branches chose the same card; `true` means better MCC evidence can matter.
    let winnerSensitiveToMCC: Bool?
    let hasRuntimeEvidence: Bool
    let runtimeEvidenceChangedTopMCC: Bool
    /// nil when the baseline/current top-MCC branches cannot both be scored.
    let runtimeEvidenceChangedWinner: Bool?
}

enum MerchantMCCDecisionQuality {
    /// Tiny posterior tails should not make a checkout look decision-sensitive. A 10% floor keeps
    /// the metric focused on MCC branches PickMe could reasonably act on while preserving genuine
    /// two-way uncertainty. This is an evaluation threshold, not a graph/promotion threshold.
    static let plausibleShareFloor = 0.10

    static func assess(
        snapshot: MerchantMCCGraphRuntimeSnapshot,
        winnerForMCC: (Int) -> String?
    ) -> MerchantMCCDecisionQualityAssessment {
        let plausible = snapshot.graph.candidates.filter { $0.share >= plausibleShareFloor }
        let hasMultiple = plausible.count >= 2

        let scoreableWinners = plausible.compactMap { winnerForMCC($0.mcc) }
        let winnerSensitive: Bool?
        if hasMultiple, scoreableWinners.count >= 2 {
            winnerSensitive = Set(scoreableWinners).count > 1
        } else {
            winnerSensitive = nil
        }

        let changedTop = snapshot.hasRuntimeEvidence
            && snapshot.baseline.bestMCC != snapshot.graph.bestMCC

        let changedWinner: Bool?
        if snapshot.hasRuntimeEvidence,
           let baselineMCC = snapshot.baseline.bestMCC,
           let currentMCC = snapshot.graph.bestMCC,
           let baselineWinner = winnerForMCC(baselineMCC),
           let currentWinner = winnerForMCC(currentMCC) {
            changedWinner = baselineWinner != currentWinner
        } else {
            changedWinner = nil
        }

        return MerchantMCCDecisionQualityAssessment(
            hasMultiplePlausibleMCCs: hasMultiple,
            winnerSensitiveToMCC: winnerSensitive,
            hasRuntimeEvidence: snapshot.hasRuntimeEvidence,
            runtimeEvidenceChangedTopMCC: changedTop,
            runtimeEvidenceChangedWinner: changedWinner)
    }

    /// Returns a classification-validated outcome for a decision whose learned MCC evidence
    /// changed the winning card. `nil` deliberately means that this observation cannot answer
    /// that question: it may predate provenance, lack an exact MCC, or be a decision where
    /// learning did not change the winner.
    ///
    /// This validates the MCC premise of the recommendation, not every fact that affects the
    /// card's value (for example an issuer posting adjustment or a benefit the owner did not
    /// use). It is the strongest outcome this local MCC signal can honestly establish.
    static func runtimeEvidenceWinnerWasValidated(
        prediction: StoredPrediction,
        observedMerchantCategoryCode: Int
    ) -> Bool? {
        guard prediction.rawCategory?.hasPrefix("merchantMccGraph:") == true,
              let predictedMCC = prediction.merchantCategoryCode,
              let data = prediction.frozenInputs,
              let snapshot = try? JSONDecoder().decode(ScoredRuleSnapshot.self, from: data),
              snapshot.mccRuntimeEvidenceChangedWinner == true
        else { return nil }

        return predictedMCC == observedMerchantCategoryCode
    }
}
