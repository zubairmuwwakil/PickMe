import XCTest
@testable import CardCopilotEngine

final class AmbientGateTests: XCTestCase {
    private let both = SwitchThreshold(minAdvantagePercentagePoints: 1, minAdvantageCad: 1,
                                       semantics: "both")

    private func passingInput(threshold: SwitchThreshold? = nil) -> AmbientGateInput {
        AmbientGateInput(merchantConfidence: .high,
                         recommendedCardId: "amex-cobalt",
                         defaultCardId: "wealthsimple-vip",
                         advantage: AmbientAdvantage(percentagePoints: 1.5, cad: 2),
                         switchThreshold: threshold ?? both,
                         isMuted: false)
    }

    func testFiresOnlyWhenEveryConjunctPasses() {
        XCTAssertTrue(AmbientGate.evaluate(passingInput()).fires)
    }

    func testSuppressesWhenMerchantConfidenceIsNotHigh() {
        var input = passingInput()
        input.merchantConfidence = .low
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons, [.merchantConfidenceLow])
    }

    func testSuppressesWhenRecommendationIsTheDefaultCard() {
        var input = passingInput()
        input.recommendedCardId = input.defaultCardId
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons, [.recommendedDefaultCard])
    }

    func testSuppressesWhenAdvantageDoesNotClearThreshold() {
        var input = passingInput()
        input.advantage = AmbientAdvantage(percentagePoints: 0.99, cad: 2)
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons,
                       [.advantageBelowSwitchThreshold])
    }

    func testSuppressesWhenMerchantIsMuted() {
        var input = passingInput()
        input.isMuted = true
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons, [.merchantMuted])
    }

    func testBothSemanticsRequiresBothThresholdsAndAllowsExactBoundary() {
        var input = passingInput()
        input.advantage = AmbientAdvantage(percentagePoints: 1, cad: 1)
        XCTAssertTrue(AmbientGate.evaluate(input).fires)

        input.advantage = AmbientAdvantage(percentagePoints: 1, cad: 0.999)
        XCTAssertFalse(AmbientGate.evaluate(input).fires)
        input.advantage = AmbientAdvantage(percentagePoints: 0.999, cad: 1)
        XCTAssertFalse(AmbientGate.evaluate(input).fires)
    }

    func testEitherSemanticsRequiresOneThresholdAndAllowsExactBoundary() {
        let either = SwitchThreshold(minAdvantagePercentagePoints: 1, minAdvantageCad: 1,
                                     semantics: "either")
        var input = passingInput(threshold: either)
        input.advantage = AmbientAdvantage(percentagePoints: 1, cad: 0)
        XCTAssertTrue(AmbientGate.evaluate(input).fires)

        input.advantage = AmbientAdvantage(percentagePoints: 0, cad: 1)
        XCTAssertTrue(AmbientGate.evaluate(input).fires)
        input.advantage = AmbientAdvantage(percentagePoints: 0.999, cad: 0.999)
        XCTAssertFalse(AmbientGate.evaluate(input).fires)
    }

    func testDecisionReportsAllFailuresAndCounterKeepsDecisionAndReasonTotals() {
        var input = passingInput()
        input.merchantConfidence = .low
        input.recommendedCardId = input.defaultCardId
        input.advantage = AmbientAdvantage(percentagePoints: 0, cad: 0)
        input.isMuted = true
        let suppressed = AmbientGate.evaluate(input)
        XCTAssertEqual(suppressed.suppressionReasons, Set(AmbientSuppressionReason.allCases))

        var log = SuppressionLog()
        log.record(AmbientGate.evaluate(passingInput()))
        log.record(suppressed)
        XCTAssertEqual(log.fired, 1)
        XCTAssertEqual(log.suppressed, 1)
        for reason in AmbientSuppressionReason.allCases {
            XCTAssertEqual(log.suppressedByReason[reason], 1)
        }
    }
}
