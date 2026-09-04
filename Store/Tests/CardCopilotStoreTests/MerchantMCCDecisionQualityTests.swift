import XCTest
@testable import CardCopilotStore

final class MerchantMCCDecisionQualityTests: XCTestCase {
    private func candidate(_ mcc: Int, share: Double) -> MerchantMCCCandidate {
        MerchantMCCCandidate(mcc: mcc, score: share, share: share,
                             directObservationCount: 0, externalObservationCount: 0)
    }

    private func prediction(best: Int, candidates: [MerchantMCCCandidate]) -> MerchantMCCPrediction {
        MerchantMCCPrediction(bestMCC: best, confidence: candidates.first?.share ?? 0,
                              candidates: candidates,
                              directObservationCount: 0,
                              externalObservationCount: 0,
                              categoryEvidenceCount: 0)
    }

    func testPlausibleMCCForkThatKeepsOneWinnerIsStable() {
        let graph = prediction(best: 5411, candidates: [
            candidate(5411, share: 0.65), candidate(5499, share: 0.35),
        ])
        let snapshot = MerchantMCCGraphRuntimeSnapshot(
            baseline: graph, graph: graph, seedConfidence: 0.4,
            rewardObservationCount: 0, relevantCommunityCount: 0)

        let result = MerchantMCCDecisionQuality.assess(snapshot: snapshot) { _ in "same-card" }

        XCTAssertTrue(result.hasMultiplePlausibleMCCs)
        XCTAssertEqual(result.winnerSensitiveToMCC, false)
        XCTAssertFalse(result.hasRuntimeEvidence)
    }

    func testPlausibleMCCForkThatChangesWinnerIsSensitive() {
        let graph = prediction(best: 5411, candidates: [
            candidate(5411, share: 0.6), candidate(5912, share: 0.4),
        ])
        let snapshot = MerchantMCCGraphRuntimeSnapshot(
            baseline: graph, graph: graph, seedConfidence: 0.4,
            rewardObservationCount: 0, relevantCommunityCount: 0)

        let result = MerchantMCCDecisionQuality.assess(snapshot: snapshot) { mcc in
            mcc == 5411 ? "grocery-card" : "pharmacy-card"
        }

        XCTAssertEqual(result.winnerSensitiveToMCC, true)
    }

    func testTinyPosteriorTailDoesNotCreateFalseDecisionSensitivity() {
        let graph = prediction(best: 5411, candidates: [
            candidate(5411, share: 0.95), candidate(5912, share: 0.05),
        ])
        let snapshot = MerchantMCCGraphRuntimeSnapshot(
            baseline: graph, graph: graph, seedConfidence: 0.4,
            rewardObservationCount: 0, relevantCommunityCount: 0)

        let result = MerchantMCCDecisionQuality.assess(snapshot: snapshot) { mcc in "card-\(mcc)" }

        XCTAssertFalse(result.hasMultiplePlausibleMCCs)
        XCTAssertNil(result.winnerSensitiveToMCC)
    }

    func testRuntimeEvidenceCanBeSeparatedFromSeedMovementAndWinnerMovement() {
        let baseline = prediction(best: 5411, candidates: [
            candidate(5411, share: 0.8), candidate(5912, share: 0.2),
        ])
        let learned = prediction(best: 5912, candidates: [
            candidate(5912, share: 0.75), candidate(5411, share: 0.25),
        ])
        let snapshot = MerchantMCCGraphRuntimeSnapshot(
            baseline: baseline, graph: learned, seedConfidence: 0.4,
            rewardObservationCount: 1, relevantCommunityCount: 0)

        let result = MerchantMCCDecisionQuality.assess(snapshot: snapshot) { mcc in
            mcc == 5411 ? "grocery-card" : "pharmacy-card"
        }

        XCTAssertTrue(result.hasRuntimeEvidence)
        XCTAssertTrue(result.runtimeEvidenceChangedTopMCC)
        XCTAssertEqual(result.runtimeEvidenceChangedWinner, true)
    }

    func testAggregateMetricStoreKeepsOnlyCountsAndDerivedShares() throws {
        let suite = "MerchantMCCDecisionQualityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CategoryResolutionMetricsStore(defaults: defaults, key: "metrics")

        store.record(.mccGraphDecisionEvaluated(multiplePlausibleMCCs: true,
                                                winnerSensitive: false))
        store.record(.mccGraphDecisionEvaluated(multiplePlausibleMCCs: true,
                                                winnerSensitive: true))
        store.record(.mccRuntimeEvidenceEvaluated(changedTopMCC: true,
                                                  changedWinner: true))
        store.record(.mccRuntimeEvidenceEvaluated(changedTopMCC: false,
                                                  changedWinner: false))

        let metrics = store.snapshot
        XCTAssertEqual(metrics.mccGraphDecisionEvaluations, 2)
        XCTAssertEqual(metrics.mccGraphMultiplePlausibleMCCs, 2)
        XCTAssertEqual(metrics.mccGraphStableWinnerAcrossMCCs, 1)
        XCTAssertEqual(metrics.mccGraphSensitiveWinnerAcrossMCCs, 1)
        XCTAssertEqual(try XCTUnwrap(metrics.mccWinnerSensitivityShare), 0.5, accuracy: 0.0001)
        XCTAssertEqual(metrics.mccRuntimeEvidenceEvaluations, 2)
        XCTAssertEqual(metrics.mccRuntimeEvidenceChangedTopMCC, 1)
        XCTAssertEqual(metrics.mccRuntimeEvidenceWinnerComparisons, 2)
        XCTAssertEqual(metrics.mccRuntimeEvidenceChangedWinner, 1)
        XCTAssertEqual(try XCTUnwrap(metrics.mccRuntimeEvidenceWinnerChangeShare), 0.5,
                       accuracy: 0.0001)
    }
}
