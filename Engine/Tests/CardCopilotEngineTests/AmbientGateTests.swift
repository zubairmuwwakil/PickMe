import XCTest
@testable import CardCopilotEngine

final class AmbientGateTests: XCTestCase {
    private let both = SwitchThreshold(minAdvantagePercentagePoints: 1, minAdvantageCad: 1,
                                       semantics: "both")

    private func passingInput(threshold: SwitchThreshold? = nil) -> AmbientGateInput {
        AmbientGateInput(merchantConfidence: .verified,
                         recommendedCardId: "amex-cobalt",
                         defaultCardId: "wealthsimple-vip",
                         advantage: AmbientAdvantage(percentagePoints: 1.5, cad: 2),
                         switchThreshold: threshold ?? both,
                         isMuted: false)
    }

    func testFiresOnlyWhenEveryConjunctPasses() {
        XCTAssertTrue(AmbientGate.evaluate(passingInput()).fires)
    }

    func testSuppressesWhenMerchantConfidenceIsUnknown() {
        var input = passingInput()
        input.merchantConfidence = .unknown
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
        // `.brandMatched` rather than `.unknown`: an unknown merchant short-circuits the
        // advantage conjunct on purpose, so it can never demonstrate the all-failures property.
        var input = passingInput()
        input.merchantConfidence = .brandMatched
        input.recommendedCardId = input.defaultCardId
        input.advantage = AmbientAdvantage(percentagePoints: 0, cad: 0)
        input.isMuted = true
        let suppressed = AmbientGate.evaluate(input)
        XCTAssertEqual(suppressed.suppressionReasons,
                       [.recommendedDefaultCard, .advantageBelowUnverifiedThreshold, .merchantMuted])

        var log = SuppressionLog()
        log.record(AmbientGate.evaluate(passingInput()))
        log.record(suppressed)
        XCTAssertEqual(log.fired, 1)
        XCTAssertEqual(log.suppressed, 1)
        for reason in suppressed.suppressionReasons {
            XCTAssertEqual(log.suppressedByReason[reason], 1)
        }
        // Reasons that did not apply are absent, not zero — the counter records observations.
        XCTAssertNil(log.suppressedByReason[.advantageBelowSwitchThreshold])
        XCTAssertNil(log.suppressedByReason[.merchantConfidenceLow])
    }

    /// The two advantage reasons are mutually exclusive: a decision is measured against exactly
    /// one threshold, so a counter total can never double-count the same miss.
    func testAdvantageReasonsAreMutuallyExclusive() {
        for confidence: AmbientMerchantConfidence in [.verified, .brandMatched, .unknown] {
            var input = passingInput()
            input.merchantConfidence = confidence
            input.advantage = AmbientAdvantage(percentagePoints: 0, cad: 0)
            let reasons = AmbientGate.evaluate(input).suppressionReasons
            XCTAssertFalse(reasons.contains(.advantageBelowSwitchThreshold)
                           && reasons.contains(.advantageBelowUnverifiedThreshold))
        }
    }
}

// MARK: - Three-tier confidence (ambient capture design §5)

extension AmbientGateTests {
    private func tierInput(_ confidence: AmbientMerchantConfidence,
                           advantage: AmbientAdvantage) -> AmbientGateInput {
        AmbientGateInput(merchantConfidence: confidence,
                         recommendedCardId: "amex-cobalt",
                         defaultCardId: "wealthsimple-vip",
                         advantage: advantage,
                         switchThreshold: both,
                         isMuted: false)
    }

    /// `.verified` is the old `.high`: the owner's own threshold, unscaled.
    func testVerifiedMerchantFiresAtTheOwnersOwnThreshold() {
        let decision = AmbientGate.evaluate(tierInput(.verified,
                                                      advantage: AmbientAdvantage(percentagePoints: 1, cad: 1)))
        XCTAssertTrue(decision.fires)
    }

    /// A bare POI pin never earns an interruption, however large the advantage looks — the
    /// advantage is computed from a category we are guessing at.
    func testUnknownMerchantNeverFiresRegardlessOfAdvantage() {
        let decision = AmbientGate.evaluate(tierInput(.unknown,
                                                      advantage: AmbientAdvantage(percentagePoints: 99, cad: 99)))
        XCTAssertEqual(decision.suppressionReasons, [.merchantConfidenceLow])
    }

    /// A brand-matched guess buys an interruption only at twice the owner's floor.
    func testBrandMatchedMerchantRequiresTwiceTheOwnersThreshold() {
        let justUnder = AmbientGate.evaluate(tierInput(.brandMatched,
                                                       advantage: AmbientAdvantage(percentagePoints: 2, cad: 1.99)))
        XCTAssertEqual(justUnder.suppressionReasons, [.advantageBelowUnverifiedThreshold])

        let exactly = AmbientGate.evaluate(tierInput(.brandMatched,
                                                     advantage: AmbientAdvantage(percentagePoints: 2, cad: 2)))
        XCTAssertTrue(exactly.fires)
    }

    /// The scaled threshold must respect `either` semantics rather than silently becoming `both`.
    func testBrandMatchedHonoursEitherSemanticsAtTheScaledFloor() {
        let either = SwitchThreshold(minAdvantagePercentagePoints: 1, minAdvantageCad: 1,
                                     semantics: "either")
        var input = tierInput(.brandMatched, advantage: AmbientAdvantage(percentagePoints: 2, cad: 0))
        input.switchThreshold = either
        XCTAssertTrue(AmbientGate.evaluate(input).fires)

        input.advantage = AmbientAdvantage(percentagePoints: 1.99, cad: 1.99)
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons,
                       [.advantageBelowUnverifiedThreshold])
    }
}

// MARK: - Patronage tier (frequented merchants)

extension AmbientGateTests {
    private func frequentedInput(_ advantage: AmbientAdvantage) -> AmbientGateInput {
        AmbientGateInput(merchantConfidence: .frequented,
                         recommendedCardId: "amex-cobalt",
                         defaultCardId: "wealthsimple-vip",
                         advantage: advantage,
                         switchThreshold: both,
                         isMuted: false)
    }

    /// Patronage removes the two doubts the unverified multiplier exists to cover — whether this
    /// is really that merchant, and whether the owner is shopping rather than walking past. The
    /// category is still a brand prior, which is why this earns its own tunable multiplier rather
    /// than being folded into `.verified`.
    func testFrequentedMerchantFiresAtTheOwnersOwnThreshold() {
        // Clears the owner's floor (1 / 1) but not the doubled floor a brand-matched guess faces.
        let decision = AmbientGate.evaluate(frequentedInput(
            AmbientAdvantage(percentagePoints: 1.5, cad: 1.5)))
        XCTAssertTrue(decision.fires)
    }

    /// The same advantage at the same merchant, without the patronage evidence, stays silent.
    /// This is the whole delta the tier buys, so it is pinned directly rather than inferred.
    func testTheSameAdvantageIsSuppressedWithoutPatronage() {
        var input = frequentedInput(AmbientAdvantage(percentagePoints: 1.5, cad: 1.5))
        input.merchantConfidence = .brandMatched
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons,
                       [.advantageBelowUnverifiedThreshold])
    }

    /// Its own counter, for the reason `advantageBelowUnverifiedThreshold` has one: it is the
    /// only evidence that can say whether the multiplier is set right, and mixing it with the
    /// verified tier's misses would make both totals useless for that question.
    func testFrequentedAdvantageMissIsCountedUnderItsOwnReason() {
        let decision = AmbientGate.evaluate(frequentedInput(
            AmbientAdvantage(percentagePoints: 0.5, cad: 0.5)))
        XCTAssertEqual(decision.suppressionReasons, [.advantageBelowFrequentedThreshold])
    }
}
