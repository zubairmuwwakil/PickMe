import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// The adjustable half of alert policy, and the arithmetic that makes finding 3 of the
/// 2026-09-02 design derivable at runtime rather than from a table in a document.
final class AmbientAlertPolicyTests: XCTestCase {
    /// The owner's shipped default: 0.5pp AND $0.25.
    private let ownerThreshold = SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                                 minAdvantageCad: 0.25, semantics: "both")

    // MARK: - Defaults

    /// A policy nobody has touched must be the shipped policy exactly. Everything below is a
    /// deviation from this, and a debug build that quietly starts from somewhere else would make
    /// every field-log record uninterpretable.
    func testTheShippedPolicyIsTodaysConstants() {
        let policy = AmbientAlertPolicy.shipped
        XCTAssertNil(policy.switchThresholdOverride)
        XCTAssertEqual(policy.unverifiedAdvantageMultiplier, 2.0)
        XCTAssertEqual(policy.frequentedAdvantageMultiplier, 1.0)
        XCTAssertEqual(policy.categoryAdvantageMultiplier, 2.0)
        XCTAssertEqual(policy.amountEstimate, .perCategory)
    }

    func testAnUnsetOverrideLeavesTheOwnersThresholdAlone() {
        XCTAssertEqual(AmbientAlertPolicy.shipped.threshold(ownerThreshold: ownerThreshold),
                       ownerThreshold)
    }

    func testAnOverrideReplacesTheOwnersThreshold() {
        var policy = AmbientAlertPolicy.shipped
        let override = SwitchThreshold(minAdvantagePercentagePoints: 2, minAdvantageCad: 1,
                                       semantics: "either")
        policy.switchThresholdOverride = override
        XCTAssertEqual(policy.threshold(ownerThreshold: ownerThreshold), override)
    }

    /// The verified tier is measured against the owner's own floor, unscaled, and no dial on this
    /// screen may change that — it is the one tier whose bar was actually earned.
    func testEachTierReadsItsOwnMultiplierAndVerifiedIsNeverScaled() {
        var policy = AmbientAlertPolicy.shipped
        policy.unverifiedAdvantageMultiplier = 3
        policy.frequentedAdvantageMultiplier = 4
        policy.categoryAdvantageMultiplier = 5
        XCTAssertEqual(policy.multiplier(for: .verified), 1)
        XCTAssertEqual(policy.multiplier(for: .brandMatched), 3)
        XCTAssertEqual(policy.multiplier(for: .frequented), 4)
        XCTAssertEqual(policy.multiplier(for: .categoryMatched), 5)
    }

    // MARK: - The estimate

    func testPerCategoryEstimatesAreTodaysTable() {
        XCTAssertEqual(ambientEstimatedAmountCad(category: "drugStore", estimate: .perCategory), 25)
        XCTAssertEqual(ambientEstimatedAmountCad(category: "wholesaleClub", estimate: .perCategory), 150)
        XCTAssertEqual(ambientEstimatedAmountCad(category: "other", estimate: .perCategory), 50,
                       "an uncategorised arrival falls back to the shipped $50")
    }

    /// The dial that answers finding 3 directly: one amount for every category removes the
    /// category dependence of the CAD floor rather than arguing about which guess is best.
    func testAFixedEstimateIgnoresTheCategory() {
        XCTAssertEqual(ambientEstimatedAmountCad(category: "drugStore", estimate: .fixed(amountCad: 40)), 40)
        XCTAssertEqual(ambientEstimatedAmountCad(category: "wholesaleClub", estimate: .fixed(amountCad: 40)), 40)
    }

    // MARK: - The effective bar

    /// The incident, reproduced from the code rather than from the write-up. Shoppers is
    /// `drugStore` at $25; a brand-matched guess doubles both floors to 1.0pp AND $0.50; and
    /// $0.50 on a $25 basket is 2.0pp — so the bar an arrival there actually faces is 2.0pp,
    /// not the 1.0pp anyone reading the threshold would expect. Nobody chose 2pp for drugstores.
    func testTheCadFloorTurnsIntoACategoryDependentPercentageBar() {
        let bar = effectiveAlertBar(category: "drugStore", ownerThreshold: ownerThreshold,
                                    policy: .shipped, confidence: .brandMatched)
        XCTAssertEqual(bar.estimatedAmountCad, 25)
        XCTAssertEqual(bar.scaledMinAdvantageCad, 0.50, accuracy: 1e-9)
        XCTAssertEqual(bar.scaledMinAdvantagePercentagePoints, 1.0, accuracy: 1e-9)
        XCTAssertEqual(bar.cadFloorAsPercentagePoints, 2.0, accuracy: 1e-9)
        XCTAssertEqual(bar.effectivePercentagePoints, 2.0, accuracy: 1e-9)
    }

    /// The observed gap was $0.51 on $33.90 — 1.50pp. Over the intended 1.0pp bar, under the
    /// accidental 2.0pp one. This is the arithmetic that produced the reported silence.
    func testTheObservedIncidentSitsBetweenTheIntendedBarAndTheAccidentalOne() {
        let bar = effectiveAlertBar(category: "drugStore", ownerThreshold: ownerThreshold,
                                    policy: .shipped, confidence: .brandMatched)
        let observed = 0.51 / 33.90 * 100
        XCTAssertGreaterThan(observed, bar.scaledMinAdvantagePercentagePoints)
        XCTAssertLessThan(observed, bar.effectivePercentagePoints)
    }

    /// A basket big enough for the CAD floor to cost less than the percentage floor leaves the
    /// percentage floor in charge, which is what the threshold was written to mean.
    func testALargeBasketLeavesThePercentageFloorInCharge() {
        let bar = effectiveAlertBar(category: "wholesaleClub", ownerThreshold: ownerThreshold,
                                    policy: .shipped, confidence: .brandMatched)
        XCTAssertEqual(bar.cadFloorAsPercentagePoints, 0.5 / 150 * 100, accuracy: 1e-9)
        XCTAssertEqual(bar.effectivePercentagePoints, 1.0, accuracy: 1e-9)
    }

    /// `either` semantics means the easier floor wins, so the effective bar is the smaller of the
    /// two rather than the larger. Getting this backwards would report a bar the gate never uses.
    func testEitherSemanticsTakesTheEasierFloor() {
        var policy = AmbientAlertPolicy.shipped
        policy.switchThresholdOverride = SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                                         minAdvantageCad: 0.25,
                                                         semantics: "either")
        let bar = effectiveAlertBar(category: "drugStore", ownerThreshold: ownerThreshold,
                                    policy: policy, confidence: .brandMatched)
        XCTAssertEqual(bar.effectivePercentagePoints, 1.0, accuracy: 1e-9)
    }

    /// The verified tier faces the owner's own floor: half the percentage bar of a guess.
    func testTheVerifiedTierIsMeasuredUnscaled() {
        let bar = effectiveAlertBar(category: "drugStore", ownerThreshold: ownerThreshold,
                                    policy: .shipped, confidence: .verified)
        XCTAssertEqual(bar.scaledMinAdvantageCad, 0.25, accuracy: 1e-9)
        XCTAssertEqual(bar.effectivePercentagePoints, 1.0, accuracy: 1e-9)
    }

    /// A zero or negative estimate cannot be divided by. It reports the percentage floor rather
    /// than an infinity, because a debug screen showing `inf` teaches nothing.
    func testAZeroEstimateDoesNotProduceAnInfiniteBar() {
        var policy = AmbientAlertPolicy.shipped
        policy.amountEstimate = .fixed(amountCad: 0)
        let bar = effectiveAlertBar(category: "drugStore", ownerThreshold: ownerThreshold,
                                    policy: policy, confidence: .brandMatched)
        XCTAssertEqual(bar.cadFloorAsPercentagePoints, 0, accuracy: 1e-9)
        XCTAssertEqual(bar.effectivePercentagePoints, 1.0, accuracy: 1e-9)
    }

    /// The whole of finding 3's table, derived at runtime. Ordered by basket size so the
    /// relationship the table exists to show — smaller basket, higher bar — is the reading order.
    func testTheWholeTableIsDerivableAndOrderedByBasketSize() {
        let bars = effectiveAlertBars(ownerThreshold: ownerThreshold, policy: .shipped,
                                      confidence: .brandMatched)
        XCTAssertEqual(bars.map(\.estimatedAmountCad), bars.map(\.estimatedAmountCad).sorted(by: >))
        XCTAssertTrue(bars.contains { $0.category == "drugStore" && $0.effectivePercentagePoints == 2.0 })
        XCTAssertTrue(bars.contains { $0.category == "grocery" },
                      "every category carrying an estimate appears")
    }
}
