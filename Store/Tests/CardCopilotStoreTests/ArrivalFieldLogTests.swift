import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// The record model and the one metric that needs no receipt.
///
/// The margin is the ceiling metric: it says whether an arrival was resolvable *at all* on this
/// hardware, independently of whether the app resolved it. An arrival whose two nearest
/// storefronts are 12 m apart, seen through a fix good to ±65 m, is not a resolution failure —
/// it is a question no algorithm on this device can answer, and the design has to handle
/// ambiguity rather than get better at guessing.
final class ArrivalDiscriminabilityTests: XCTestCase {
    private func site(_ metresNorth: Double) -> ArrivalSite {
        // ~111 km per degree of latitude, so this is metres.
        ArrivalSite(latitude: 45 + metresNorth / 111_000, longitude: -75)
    }

    private func fix(accuracy: Double) -> ArrivalFix {
        ArrivalFix(latitude: 45, longitude: -75, horizontalAccuracyMeters: accuracy,
                   capturedAt: Date(timeIntervalSince1970: 0))
    }

    func testTheMarginIsTheGapBetweenTheNearestAndTheRunnerUp() throws {
        let margin = try XCTUnwrap(discriminability(candidates: [site(120), site(20), site(300)],
                                                    fix: fix(accuracy: 10)))
        XCTAssertEqual(margin.nearestDistanceMeters, 20, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(margin.runnerUpDistanceMeters), 120, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(margin.marginMeters), 100, accuracy: 1)
    }

    /// A gap wider than the fix's own error circle: the nearest candidate really is the nearest.
    func testAGapWiderThanTheFixAccuracyIsResolvable() throws {
        let margin = try XCTUnwrap(discriminability(candidates: [site(20), site(200)],
                                                    fix: fix(accuracy: 10)))
        XCTAssertTrue(margin.isResolvable)
    }

    /// The finding this metric exists to produce. Two storefronts 12 m apart, a fix good to
    /// ±65 m: the ordering is noise, and no amount of better ranking fixes it.
    func testAGapInsideTheFixAccuracyIsNotResolvableByAnyAlgorithm() throws {
        let margin = try XCTUnwrap(discriminability(candidates: [site(20), site(32)],
                                                    fix: fix(accuracy: 65)))
        XCTAssertFalse(margin.isResolvable)
    }

    /// One candidate is unambiguous: there is nothing to confuse it with. Reporting it as
    /// ambiguous would inflate the very number the rework decision turns on.
    func testASingleCandidateIsResolvableWithNoRunnerUp() throws {
        let margin = try XCTUnwrap(discriminability(candidates: [site(20)], fix: fix(accuracy: 65)))
        XCTAssertNil(margin.runnerUpDistanceMeters)
        XCTAssertNil(margin.marginMeters)
        XCTAssertTrue(margin.isResolvable)
    }

    func testAnArrivalWithNoCandidatesHasNoMargin() {
        XCTAssertNil(discriminability(candidates: [], fix: fix(accuracy: 10)))
    }

    /// A margin accrues on every arrival, purchase or not — it is the one metric that needs no
    /// receipt — but it does need a fix, since it is measured against the fix's own accuracy.
    func testAnArrivalWithNoFixHasNoMargin() {
        XCTAssertNil(discriminability(candidates: [site(20), site(200)], fix: nil))
    }

    /// CoreLocation reports a negative accuracy for an invalid fix. Treating that as "accurate to
    /// −1 m" would mark every ambiguous arrival resolvable.
    func testAnInvalidAccuracyIsNeverTreatedAsPrecise() throws {
        let margin = try XCTUnwrap(discriminability(candidates: [site(20), site(32)],
                                                    fix: fix(accuracy: -1)))
        XCTAssertFalse(margin.isResolvable)
    }
}
