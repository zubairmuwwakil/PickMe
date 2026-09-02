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

    // MARK: - Delivery tier

    func testClearArrivalInterrupts() {
        XCTAssertEqual(AmbientGate.evaluate(passingInput()).tier, .interrupt)
    }

    func testDefaultCardWinConfirmsRatherThanSilencing() {
        var input = passingInput()
        input.recommendedCardId = input.defaultCardId
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .confirm)
    }

    func testAdvantageBelowThresholdConfirms() {
        var input = passingInput()
        input.advantage = AmbientAdvantage(percentagePoints: 0.99, cad: 2)
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .confirm)
    }

    func testUnknownMerchantGetsPresenceWithoutAdvice() {
        var input = passingInput()
        input.merchantConfidence = .unknown
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .presence)
    }

    func testMutedMerchantIsSilent() {
        var input = passingInput()
        input.isMuted = true
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .silent)
    }

    /// Consent outranks a correctness stop, which outranks a volume judgement.
    func testMutePrecedesEveryOtherReason() {
        var input = passingInput()
        input.isMuted = true
        input.merchantConfidence = .unknown
        input.recommendedCardId = input.defaultCardId
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .silent)
    }

    func testUnknownMerchantPrecedesVolumeReasons() {
        var input = passingInput()
        input.merchantConfidence = .unknown
        input.recommendedCardId = input.defaultCardId
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .presence)
    }

    /// The TestFlight A3 criterion and `SuppressionLog` both read `fires`. It must keep
    /// meaning "PickMe interrupted", not "PickMe was visible".
    func testFiresStillMeansInterrupt() {
        for input in [passingInput(), mutedInput(), unknownInput(), defaultWinInput()] {
            let decision = AmbientGate.evaluate(input)
            XCTAssertEqual(decision.fires, decision.tier == .interrupt)
            XCTAssertEqual(decision.fires, decision.suppressionReasons.isEmpty)
        }
    }

    private func mutedInput() -> AmbientGateInput {
        var input = passingInput(); input.isMuted = true; return input
    }

    private func unknownInput() -> AmbientGateInput {
        var input = passingInput(); input.merchantConfidence = .unknown; return input
    }

    private func defaultWinInput() -> AmbientGateInput {
        var input = passingInput(); input.recommendedCardId = input.defaultCardId; return input
    }
}

// MARK: - Place-type tier (category known, merchant not)

extension AmbientGateTests {
    private func categoryInput(_ advantage: AmbientAdvantage) -> AmbientGateInput {
        AmbientGateInput(merchantConfidence: .categoryMatched,
                         recommendedCardId: "amex-cobalt",
                         defaultCardId: "wealthsimple-vip",
                         advantage: advantage,
                         switchThreshold: both,
                         isMuted: false)
    }

    /// The tier this replaces was `.unknown`, which is a hard stop no multiplier can reach. Apple
    /// classifying a POI as a pharmacy is evidence about the *category*, which is the only thing
    /// the card actually depends on, and it must be able to reach the advantage conjunct at all.
    func testCategoryMatchedMerchantIsNotAHardStop() {
        let decision = AmbientGate.evaluate(categoryInput(
            AmbientAdvantage(percentagePoints: 2, cad: 2)))
        XCTAssertTrue(decision.fires)
        XCTAssertFalse(decision.suppressionReasons.contains(.merchantConfidenceLow))
    }

    /// Its multiplier starts equal to the unverified one, so introducing the tier changes which
    /// bar a place-type arrival is judged against but never moves the bar itself.
    func testCategoryMatchedStartsAtTheSameBarAsABrandMatchedGuess() {
        let justUnder = AmbientGate.evaluate(categoryInput(
            AmbientAdvantage(percentagePoints: 2, cad: 1.99)))
        XCTAssertFalse(justUnder.fires)

        let exactly = AmbientGate.evaluate(categoryInput(
            AmbientAdvantage(percentagePoints: 2, cad: 2)))
        XCTAssertTrue(exactly.fires)
    }

    /// Its own counter, for exactly the reason `advantageBelowUnverifiedThreshold` has one: Group
    /// B makes this multiplier separately tunable, and a multiplier with no counter of its own
    /// can only be tuned against evidence that belongs to a different tier.
    func testCategoryMatchedMissIsCountedUnderItsOwnReason() {
        let decision = AmbientGate.evaluate(categoryInput(
            AmbientAdvantage(percentagePoints: 0.5, cad: 0.5)))
        XCTAssertEqual(decision.suppressionReasons, [.advantageBelowCategoryThreshold])
    }

    /// A volume judgement, not a correctness stop: the owner sees the advice and is not
    /// interrupted for it. `.presence` — showing up while naming no card — is reserved for the
    /// arrivals where nothing at all is known.
    func testCategoryMatchedMissConfirmsRatherThanFallingBackToPresence() {
        let decision = AmbientGate.evaluate(categoryInput(
            AmbientAdvantage(percentagePoints: 0.5, cad: 0.5)))
        XCTAssertEqual(decision.tier, .confirm)
    }

    /// Every tier is measured against exactly one threshold, so no counter can double-count one
    /// miss. Extended to cover the new tier rather than left pinned to the original three.
    func testEveryTierMissesAgainstExactlyOneThreshold() {
        let advantageReasons: Set<AmbientSuppressionReason> = [
            .advantageBelowSwitchThreshold, .advantageBelowUnverifiedThreshold,
            .advantageBelowFrequentedThreshold, .advantageBelowCategoryThreshold,
        ]
        for confidence in [AmbientMerchantConfidence.verified, .brandMatched, .frequented,
                           .categoryMatched, .unknown] {
            var input = passingInput()
            input.merchantConfidence = confidence
            input.advantage = AmbientAdvantage(percentagePoints: 0, cad: 0)
            let reasons = AmbientGate.evaluate(input).suppressionReasons
            XCTAssertLessThanOrEqual(reasons.intersection(advantageReasons).count, 1,
                                     "\(confidence) was measured against more than one threshold")
        }
    }
}

// MARK: - Multipliers as inputs (adjustable alert policy)

extension AmbientGateTests {
    /// The whole point of moving these onto the input is that they can be changed at runtime, so
    /// the one thing that must never change is what happens when nobody changes them. An omitted
    /// argument has to reproduce the shipped policy exactly.
    func testOmittedMultipliersReproduceTheShippedPolicy() {
        let input = passingInput()
        XCTAssertEqual(input.unverifiedAdvantageMultiplier, 2.0)
        XCTAssertEqual(input.frequentedAdvantageMultiplier, 1.0)
        XCTAssertEqual(input.categoryAdvantageMultiplier, 2.0)
    }

    /// Decoded from a payload written before the multipliers existed — a field-log record
    /// persisted by an earlier build. Missing values must fall back to the shipped policy rather
    /// than failing the decode and taking a week of records with them.
    func testAPayloadWithoutMultipliersDecodesToTheShippedPolicy() throws {
        let legacy = """
        {"merchantConfidence":"verified","recommendedCardId":"amex-cobalt",
         "defaultCardId":"wealthsimple-vip",
         "advantage":{"percentagePoints":1.5,"cad":2},
         "switchThreshold":{"minAdvantagePercentagePoints":1,"minAdvantageCad":1,
                            "semantics":"both"},
         "isMuted":false}
        """
        let decoded = try JSONDecoder().decode(AmbientGateInput.self,
                                               from: Data(legacy.utf8))
        XCTAssertEqual(decoded, passingInput())
    }

    func testTheUnverifiedMultiplierIsReadFromTheInput() {
        var input = passingInput()
        input.merchantConfidence = .brandMatched
        input.advantage = AmbientAdvantage(percentagePoints: 1, cad: 1)
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons,
                       [.advantageBelowUnverifiedThreshold])

        input.unverifiedAdvantageMultiplier = 1.0
        XCTAssertTrue(AmbientGate.evaluate(input).fires)
    }

    func testTheFrequentedMultiplierIsReadFromTheInput() {
        var input = passingInput()
        input.merchantConfidence = .frequented
        input.advantage = AmbientAdvantage(percentagePoints: 1, cad: 1)
        XCTAssertTrue(AmbientGate.evaluate(input).fires)

        input.frequentedAdvantageMultiplier = 2.0
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons,
                       [.advantageBelowFrequentedThreshold])
    }

    func testTheCategoryMultiplierIsReadFromTheInput() {
        var input = passingInput()
        input.merchantConfidence = .categoryMatched
        input.advantage = AmbientAdvantage(percentagePoints: 1, cad: 1)
        XCTAssertEqual(AmbientGate.evaluate(input).suppressionReasons,
                       [.advantageBelowCategoryThreshold])

        input.categoryAdvantageMultiplier = 1.0
        XCTAssertTrue(AmbientGate.evaluate(input).fires)
    }

    /// Each multiplier reaches exactly its own tier. Without this, a debug screen that lowers one
    /// dial and watches a different tier start firing would be measuring the wrong thing.
    func testEachMultiplierReachesOnlyItsOwnTier() {
        var input = passingInput()
        input.advantage = AmbientAdvantage(percentagePoints: 1, cad: 1)
        input.unverifiedAdvantageMultiplier = 100
        input.frequentedAdvantageMultiplier = 100
        input.categoryAdvantageMultiplier = 100
        XCTAssertTrue(AmbientGate.evaluate(input).fires,
                      "the verified tier is measured against the owner's own floor, unscaled")
    }
}
