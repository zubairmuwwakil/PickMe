import XCTest
import CardCopilotStore
@testable import CardCopilot

/// A background region wake is short, so the arrival fix is a race the arrival must be allowed to
/// lose. These pin all three outcomes — it lands, it never lands, it lands too late — because the
/// only unacceptable one is an arrival that never resolves at all.
@MainActor
final class ArrivalFixRequesterTests: XCTestCase {
    private func fix(_ latitude: Double) -> ArrivalFix {
        ArrivalFix(latitude: latitude, longitude: -75, horizontalAccuracyMeters: 12,
                   capturedAt: Date(timeIntervalSince1970: 0))
    }

    func testTheFixIsReturnedWhenItLandsBeforeTheTimeout() async {
        let requester = ArrivalFixRequester(timeout: .seconds(30), start: {})
        async let awaited = requester.fix()
        await Task.yield()
        requester.deliver(fix(45))
        let result = await awaited
        XCTAssertEqual(result, fix(45))
    }

    /// The arrival still has to resolve. Nil means "no fix", and every caller falls back to the
    /// pre-fix behaviour on it.
    func testNilIsReturnedWhenTheTimeoutExpires() async {
        let requester = ArrivalFixRequester(timeout: .milliseconds(20), start: {})
        let result = await requester.fix()
        XCTAssertNil(result)
        XCTAssertEqual(requester.timeouts, 1)
    }

    /// iOS can deliver a fix long after a background wake has been answered. That late fix must
    /// not resolve anything — the arrival was already decided — and must not crash.
    func testAFixArrivingAfterTheTimeoutResolvesNothing() async {
        let requester = ArrivalFixRequester(timeout: .milliseconds(20), start: {})
        let result = await requester.fix()
        XCTAssertNil(result)

        requester.deliver(fix(45))
        XCTAssertEqual(requester.timeouts, 1)
    }

    /// A CoreLocation failure is the same answer as a timeout — no fix — and must not leave the
    /// arrival waiting out the full window for a fix that is never coming.
    func testAFailureResolvesImmediatelyAsNoFix() async {
        let requester = ArrivalFixRequester(timeout: .seconds(30), start: {})
        async let awaited = requester.fix()
        await Task.yield()
        requester.fail()
        let result = await awaited
        XCTAssertNil(result)
    }

    /// One plaza can queue several arrivals in one wake. They share the single outstanding
    /// request rather than each asking iOS for its own fix.
    func testConcurrentArrivalsShareOneRequest() async {
        var starts = 0
        let requester = ArrivalFixRequester(timeout: .seconds(30), start: { starts += 1 })
        async let first = requester.fix()
        async let second = requester.fix()
        await Task.yield()
        await Task.yield()
        requester.deliver(fix(45))
        let results = await [first, second]
        XCTAssertEqual(results, [fix(45), fix(45)])
        XCTAssertEqual(starts, 1)
    }
}
