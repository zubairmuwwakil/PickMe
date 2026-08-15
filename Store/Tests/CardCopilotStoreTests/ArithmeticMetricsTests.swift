import XCTest
import SwiftData
@testable import CardCopilotStore

/// Metric #2 of the pass/fail bar (design §3): posted rewards match catalogue math on every
/// transaction where the category was right. These tests pin the eligibility rule, because a
/// metric that silently drops the rows it cannot judge — or silently judges rows it should not —
/// would report a number that means nothing.
final class ArithmeticMetricsTests: XCTestCase {
    var container: ModelContainer!
    var log: PredictionLog!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredObservation.self, StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        log = PredictionLog(context: ModelContext(container))
    }

    private func prediction(amountCad: Double? = 140,
                            winnerCardId: String = "amex-cobalt",
                            units: Double? = 700,
                            unitKind: String? = "point") -> StoredPrediction {
        StoredPrediction(
            merchantName: "Loblaws", merchantIdentifier: "poi-123",
            predictedCategory: "grocery", confidenceSource: .brandPrior,
            winnerCardId: winnerCardId, winnerValueCad: 7.00,
            predictedRewardUnits: units, predictedRewardUnitKind: unitKind,
            defaultCardValueCad: 2.80, winnerRuleId: "cobalt-grocery-5x",
            amountCad: amountCad, valuationCentsPerPoint: 1.0,
            headline: "Use American Express Cobalt Card.")
    }

    // MARK: no evidence

    func testArithmeticRateIsNilRatherThanZeroWithoutEligibleRows() throws {
        _ = try log.record(prediction())
        let metrics = try log.metrics()
        XCTAssertNil(metrics.arithmeticCorrectRate,
                     "an unchecked experiment is not a failing one")
        XCTAssertNil(metrics.meetsArithmeticBar)
        XCTAssertEqual(metrics.arithmeticEligibleCount, 0)
    }

    func testTheEmptyMetricsValueClaimsNothing() {
        // The app renders this in the window between launch and the first store read. It must
        // look like "no evidence", never like a failing experiment.
        let empty = ExperimentMetrics.empty
        XCTAssertNil(empty.categoryAccuracy)
        XCTAssertNil(empty.arithmeticCorrectRate)
        XCTAssertNil(empty.meetsCategoryBar)
        XCTAssertNil(empty.meetsArithmeticBar)
        XCTAssertEqual(empty.progressToTarget, 0)
        XCTAssertEqual(empty.targetCheckouts, PredictionLog.targetCheckouts)
        XCTAssertTrue(empty.missBreakdown.isEmpty)
    }

    // MARK: tolerance is unit-aware

    func testPointsRowInsideOneUnitCounts() throws {
        // Points post as integers, so an engine figure of 46.47 must accept a posted 46.
        let row = try log.record(prediction(amountCad: 9.99, units: 46.47))
        try log.confirm(row, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 46, missClass: nil, note: nil)
        XCTAssertEqual(try log.metrics().arithmeticCorrectRate ?? .nan, 1.0, accuracy: 0.0001)
    }

    func testPointsRowOutsideOneUnitIsAMiss() throws {
        let row = try log.record(prediction(units: 700))
        try log.confirm(row, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 350, missClass: nil, note: nil)
        XCTAssertEqual(try log.metrics().arithmeticCorrectRate ?? .nan, 0.0, accuracy: 0.0001,
                       "half the expected points is a catalogue-math failure, not rounding")
    }

    func testCashBackRowIsCheckedToTheCentNotToTheDollar() throws {
        // The whole reason the unit kind is snapshotted: a cash-back card's units ARE dollars,
        // so a 1.0 tolerance would wave through a 25% error on a $2 reward.
        let row = try log.record(prediction(amountCad: 100, winnerCardId: "wealthsimple-vip",
                                            units: 2.00, unitKind: "cad"))
        try log.confirm(row, cardUsed: "wealthsimple-vip", observedCategory: "grocery",
                        observedRewardUnits: 1.50, missClass: nil, note: nil)
        XCTAssertEqual(try log.metrics().arithmeticCorrectRate ?? .nan, 0.0, accuracy: 0.0001)
    }

    func testCashBackRowAbsorbsCentRounding() throws {
        let row = try log.record(prediction(amountCad: 100, winnerCardId: "wealthsimple-vip",
                                            units: 2.00, unitKind: "cad"))
        try log.confirm(row, cardUsed: "wealthsimple-vip", observedCategory: "grocery",
                        observedRewardUnits: 1.99, missClass: nil, note: nil)
        XCTAssertEqual(try log.metrics().arithmeticCorrectRate ?? .nan, 1.0, accuracy: 0.0001,
                       "a single cent is how the issuer rounds, not how the catalogue is wrong")
    }

    // MARK: eligibility

    func testEstimatedAmountRowNeverEntersTheCheck() throws {
        let row = try log.record(prediction(amountCad: nil))
        try log.confirm(row, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 300, missClass: nil, note: nil)
        XCTAssertEqual(try log.metrics().arithmeticEligibleCount, 0,
                       "the engine scored a guessed amount — the posted units cannot disagree with it meaningfully")
    }

    func testRowsMissingEitherRewardUnitAreExcluded() throws {
        let legacy = try log.record(prediction(units: nil, unitKind: nil))
        try log.confirm(legacy, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 700, missClass: nil, note: nil)
        let unreadStatement = try log.record(prediction())
        try log.confirm(unreadStatement, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        missClass: nil, note: nil)
        XCTAssertEqual(try log.metrics().arithmeticEligibleCount, 0,
                       "a missing unit is unknown evidence, never assumed-correct evidence")
    }

    func testWrongCategoryRowIsExcludedFromTheArithmeticCheck() throws {
        let row = try log.record(prediction())
        try log.confirm(row, cardUsed: "amex-cobalt", observedCategory: "wholesaleClub",
                        observedRewardUnits: 140, missClass: .wrongCategory, note: nil)
        XCTAssertEqual(try log.metrics().arithmeticEligibleCount, 0,
                       "metric #2 is measured only where metric #1 succeeded — otherwise one failure counts twice")
    }

    func testCapExceededRowWithTheRightCategoryStillEntersTheCheck() throws {
        // The category was right and the math was wrong: exactly what metric #2 exists to catch.
        // Excluding every row that carries a miss class would make the cap bug invisible.
        let row = try log.record(prediction())
        try log.confirm(row, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 140, missClass: .capExceeded,
                        note: "monthly Cobalt cap was already spent")
        let metrics = try log.metrics()
        XCTAssertEqual(metrics.arithmeticEligibleCount, 1)
        XCTAssertEqual(metrics.arithmeticCorrectRate ?? .nan, 0.0, accuracy: 0.0001)
    }

    func testRowWhereADifferentCardWasTappedIsExcluded() throws {
        let row = try log.record(prediction())
        try log.confirm(row, cardUsed: "wealthsimple-vip", observedCategory: "grocery",
                        observedRewardUnits: 2.80, missClass: nil, note: "left the Cobalt at home")
        XCTAssertEqual(try log.metrics().arithmeticEligibleCount, 0,
                       "the predicted units belong to the recommended card — another card's posting is not a catalogue error")
    }

    // MARK: the bar itself

    func testArithmeticBarDemandsEveryEligibleRow() throws {
        let good = try log.record(prediction())
        let bad = try log.record(prediction())
        try log.confirm(good, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 700, missClass: nil, note: nil)
        try log.confirm(bad, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 690, missClass: nil, note: nil)

        let metrics = try log.metrics()
        XCTAssertEqual(metrics.arithmeticEligibleCount, 2)
        XCTAssertEqual(metrics.arithmeticCorrectCount, 1)
        XCTAssertEqual(metrics.arithmeticCorrectRate ?? .nan, 0.5, accuracy: 0.0001)
        XCTAssertEqual(metrics.meetsArithmeticBar, false, "the bar is 100%, not 85%")
    }

    func testArithmeticBarIsMetWhenEveryEligibleRowMatches() throws {
        let row = try log.record(prediction())
        try log.confirm(row, cardUsed: "amex-cobalt", observedCategory: "grocery",
                        observedRewardUnits: 700, missClass: nil, note: nil)
        XCTAssertEqual(try log.metrics().meetsArithmeticBar, true)
    }
}
