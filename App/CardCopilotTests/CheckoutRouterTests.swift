import XCTest
import CardCopilotEngine
@testable import CardCopilot

@MainActor
final class CheckoutRouterTests: XCTestCase {

    func testStartsAtIdleWithAnEmptyPath() {
        let router = CheckoutRouter()
        XCTAssertTrue(router.path.isEmpty)
        guard case .idle = router.step else { return XCTFail("expected .idle") }
    }

    func testPushAndPopAreSymmetric() {
        let router = CheckoutRouter()
        router.push(.dashboard)
        router.push(.settings)
        XCTAssertEqual(router.path, [.dashboard, .settings])
        router.pop()
        XCTAssertEqual(router.path, [.dashboard])
    }

    /// Popping an empty path must be a no-op rather than a crash. The old code could not hit
    /// this because it had no stack; with a real one, a double-tap on a back button can.
    func testPopOnEmptyPathIsSafe() {
        let router = CheckoutRouter()
        router.pop()
        XCTAssertTrue(router.path.isEmpty)
    }

    /// Switching tabs must not leave the previous tab's stack behind, or the owner taps
    /// Wallet and lands on a Settings screen pushed from the Copilot tab.
    func testSwitchingTabsClearsThePath() {
        let router = CheckoutRouter()
        router.push(.dashboard)
        router.selectTab(.wallet)
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertEqual(router.selectedTab, .wallet)
    }

    /// Deep links and ambient notifications previously set `stage = .sync` directly. Under a
    /// navigation stack the equivalent is an append, and it must survive being triggered while
    /// another screen is already pushed.
    func testDeepLinkToSyncAppendsRatherThanReplacing() {
        let router = CheckoutRouter()
        router.push(.dashboard)
        router.push(.sync)
        XCTAssertEqual(router.path, [.dashboard, .sync])
    }

    func testPopToRootClearsEverythingButKeepsTheTab() {
        let router = CheckoutRouter()
        router.selectTab(.you)
        router.push(.settings)
        router.push(.sync)
        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertEqual(router.selectedTab, .you)
    }

    /// `.sync` is reached from three places — the toolbar, a capture deep link, and a
    /// connectivity notification — and two of them can fire in the same launch. The predecessor's
    /// `stage = .sync` was a replace, so it could not stack; `push` can, and a doubled entry
    /// makes the back button appear dead.
    func testShowingTheSameDestinationTwiceDoesNotStackIt() {
        let router = CheckoutRouter()
        router.show(.sync)
        router.show(.sync)
        XCTAssertEqual(router.path, [.sync])
    }

    /// Only the top is deduplicated. Returning to a screen the owner has already been through
    /// is a legitimate push, not a repeat.
    func testShowingADestinationAgainBelowTheTopStillPushes() {
        let router = CheckoutRouter()
        router.show(.sync)
        router.show(.finish)
        router.show(.sync)
        XCTAssertEqual(router.path, [.sync, .finish, .sync])
    }
}
