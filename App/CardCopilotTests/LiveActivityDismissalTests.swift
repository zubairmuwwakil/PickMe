import XCTest
import ActivityKit
@testable import CardCopilot

/// `Activity` cannot be constructed in a test process, so the *decision* — is this state change
/// the owner saying "not now", or is it our own cleanup? — is extracted from the observer and
/// tested here as a pure function over the state sequence.
final class LiveActivityDismissalTests: XCTestCase {
    func testASwipeIsAnOwnerDismissal() {
        XCTAssertTrue(LiveActivityDismissalPolicy.isOwnerDismissal(after: [], observing: .dismissed))
    }

    /// The defect this exists to prevent. `.ended` and `.dismissed` are sequential states, not
    /// alternatives: `.ended` means "over but still on screen", `.dismissed` means "no longer on
    /// screen". Our own `endActivity(dismissalPolicy: .immediate)` therefore drives
    /// `.active → .ended → .dismissed` within about a second, and a filter that watches only for
    /// `.dismissed` records every geofence exit and every activity swap as an owner swipe.
    func testOurOwnEndIsNotAnOwnerDismissal() {
        XCTAssertFalse(LiveActivityDismissalPolicy.isOwnerDismissal(after: [.ended],
                                                                   observing: .dismissed))
    }

    /// A system expiry — the staleness window or the eight-hour Live Activity limit — also runs
    /// through `.ended`, and is not the owner saying anything either.
    func testASystemExpiryIsNotAnOwnerDismissal() {
        XCTAssertFalse(LiveActivityDismissalPolicy.isOwnerDismissal(after: [.active, .stale, .ended],
                                                                   observing: .dismissed))
    }

    func testStatesBeforeADismissalDoNotThemselvesReportOne() {
        for state in [ActivityState.active, .stale, .ended] {
            XCTAssertFalse(LiveActivityDismissalPolicy.isOwnerDismissal(after: [], observing: state),
                           "\(state) is not a dismissal")
        }
    }

    /// Being wrong in the generous direction: an owner who swipes an activity that already
    /// reported `.ended` is not recorded. Suppressing a card we should have shown is a worse
    /// failure than showing one the owner had finished with, and this branch is unobservable
    /// anyway once iOS has terminated the process.
    func testASwipeAfterAnEndIsTreatedAsOurOwnCleanup() {
        XCTAssertFalse(LiveActivityDismissalPolicy.isOwnerDismissal(after: [.active, .ended],
                                                                   observing: .dismissed))
    }
}
