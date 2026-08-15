import XCTest
import SwiftData
@testable import CardCopilotStore

/// The prediction log is the experiment's evidence base. Its one non-negotiable property:
/// a correction never rewrites what the app actually said at the time. Accuracy measured
/// against a mutable log would be measuring nothing.
final class PredictionLogTests: XCTestCase {
    var container: ModelContainer!
    var log: PredictionLog!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredObservation.self, StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        log = PredictionLog(context: ModelContext(container))
    }

    private func samplePrediction() -> StoredPrediction {
        StoredPrediction(
            merchantName: "Loblaws", merchantIdentifier: "poi-123",
            predictedCategory: "grocery", confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt", winnerValueCad: 7.00, winnerRuleId: "cobalt-eats-5x",
            runnerUpCardId: "mbna-rewards-we", runnerUpValueCad: 7.00,
            amountCad: 140, valuationCentsPerPoint: 1.0,
            headline: "Use American Express Cobalt Card — about $7.00 back on this $140.00 purchase.",
            recordedAt: Date(timeIntervalSince1970: 1_786_000_000))
    }

    func testPredictionRoundTrips() throws {
        let saved = try log.record(samplePrediction())
        let all = try log.allPredictions()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, saved.id)
        XCTAssertEqual(all.first?.winnerCardId, "amex-cobalt")
        XCTAssertEqual(all.first?.predictedCategory, "grocery")
    }

    func testConfirmingLeavesThePredictionUntouched() throws {
        let prediction = try log.record(samplePrediction())
        let originalCategory = prediction.predictedCategory
        let originalWinner = prediction.winnerCardId
        let originalHeadline = prediction.headline

        try log.confirm(prediction, cardUsed: "wealthsimple-vip",
                        observedCategory: "wholesaleClub", missClass: .wrongCategory,
                        note: "coded as warehouse club, not grocery")

        let reloaded = try XCTUnwrap(try log.allPredictions().first)
        XCTAssertEqual(reloaded.predictedCategory, originalCategory,
                       "a correction must never rewrite the prediction")
        XCTAssertEqual(reloaded.winnerCardId, originalWinner)
        XCTAssertEqual(reloaded.headline, originalHeadline)

        let observation = try XCTUnwrap(reloaded.observation)
        XCTAssertEqual(observation.observedCategory, "wholesaleClub")
        XCTAssertEqual(observation.missClass, .wrongCategory)
        XCTAssertEqual(observation.cardUsed, "wealthsimple-vip")
    }

    func testAccuracyCountsOnlyConfirmedPredictions() throws {
        let a = try log.record(samplePrediction())
        let b = try log.record(samplePrediction())
        _ = try log.record(samplePrediction())          // left unconfirmed
        try log.confirm(a, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        missClass: nil, note: nil)
        try log.confirm(b, cardUsed: "wealthsimple-vip", observedCategory: "wholesaleClub",
                        missClass: .wrongCategory, note: nil)

        let metrics = try log.metrics()
        XCTAssertEqual(metrics.confirmedCount, 2, "unconfirmed predictions are not evidence")
        XCTAssertEqual(metrics.categoryCorrectCount, 1)
        XCTAssertEqual(metrics.categoryAccuracy ?? .nan, 0.5, accuracy: 0.001)
        XCTAssertEqual(metrics.progressToTarget, 2)
    }

    func testMetricsAreNilRatherThanZeroWithNoEvidence() throws {
        let metrics = try log.metrics()
        XCTAssertEqual(metrics.confirmedCount, 0)
        XCTAssertNil(metrics.categoryAccuracy,
                     "no confirmations means unknown accuracy, not 0% accuracy")
    }

    func testUnconfirmedPredictionsDriveTheReconcileQueue() throws {
        let a = try log.record(samplePrediction())
        _ = try log.record(samplePrediction())
        try log.confirm(a, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        missClass: nil, note: nil)
        XCTAssertEqual(try log.awaitingConfirmation().count, 1)
    }

    func testMissBreakdownGroupsByClass() throws {
        let a = try log.record(samplePrediction())
        let b = try log.record(samplePrediction())
        try log.confirm(a, cardUsed: "x", observedCategory: "other", missClass: .wrongCategory, note: nil)
        try log.confirm(b, cardUsed: "x", observedCategory: "other", missClass: .wrongCategory, note: nil)
        XCTAssertEqual(try log.metrics().missBreakdown[.wrongCategory], 2)
    }
}
