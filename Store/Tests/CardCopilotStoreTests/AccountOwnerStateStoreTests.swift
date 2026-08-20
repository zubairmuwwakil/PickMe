import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class AccountOwnerStateStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var activeStore: OwnerStateLocalStore!

    override func setUp() {
        super.setUp()
        suiteName = "AccountOwnerStateStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        activeStore = OwnerStateLocalStore(defaults: defaults, key: "active")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        activeStore = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func owner(defaultCardID: String) throws -> OwnerState {
        var state = try SeedLoader.loadOwnerState()
        state.defaultCardId = defaultCardID
        return state
    }

    func testSwitchingAccountsRestoresEachCachedWalletAndChangesTheExtensionFacingStore() throws {
        let store = AccountOwnerStateStore(defaults: defaults, profilesKey: "profiles",
                                           activeUserKey: "bound", activeStore: activeStore)
        let first = try owner(defaultCardID: "amex-cobalt")
        let second = try owner(defaultCardID: "wealthsimple-vip")

        try store.activate(first, forUserID: "user-one")
        try store.activate(second, forUserID: "user-two")

        XCTAssertEqual(store.activeUserID, "user-two")
        XCTAssertEqual(activeStore.load(), second)
        XCTAssertEqual(store.state(forUserID: "user-one"), first)
        XCTAssertEqual(store.state(forUserID: "user-two"), second)
    }

    func testUpdatingActiveWalletDoesNotOverwriteAnotherAccount() throws {
        let store = AccountOwnerStateStore(defaults: defaults, profilesKey: "profiles",
                                           activeUserKey: "bound", activeStore: activeStore)
        let first = try owner(defaultCardID: "amex-cobalt")
        let second = try owner(defaultCardID: "wealthsimple-vip")
        try store.activate(first, forUserID: "user-one")
        try store.activate(second, forUserID: "user-two")

        var editedSecond = second
        editedSecond.switchThreshold.minAdvantageCad = 9
        try store.updateActive(editedSecond)

        XCTAssertEqual(store.state(forUserID: "user-one"), first)
        XCTAssertEqual(store.state(forUserID: "user-two"), editedSecond)
    }

    func testDeletingAccountProfilePreservesTheDeviceWalletButClearsBinding() throws {
        let store = AccountOwnerStateStore(defaults: defaults, profilesKey: "profiles",
                                           activeUserKey: "bound", activeStore: activeStore)
        let state = try owner(defaultCardID: "amex-cobalt")
        try store.activate(state, forUserID: "user-one")

        store.removeProfile(forUserID: "user-one")

        XCTAssertNil(store.activeUserID)
        XCTAssertNil(store.state(forUserID: "user-one"))
        XCTAssertEqual(activeStore.load(), state)
    }

    func testUploadQueueKeepsLatestWalletPerAccount() throws {
        let queue = OwnerStateUploadQueue(defaults: defaults, key: "uploads")
        let first = try owner(defaultCardID: "amex-cobalt")
        let replacement = try owner(defaultCardID: "wealthsimple-vip")
        let other = try owner(defaultCardID: "amex-platinum")

        try queue.enqueue(first, forUserID: "user-one")
        try queue.enqueue(replacement, forUserID: "user-one")
        try queue.enqueue(other, forUserID: "user-two")

        XCTAssertEqual(queue.pending(forUserID: "user-one"), replacement)
        XCTAssertEqual(queue.pending(forUserID: "user-two"), other)

        queue.remove(forUserID: "user-one")
        XCTAssertNil(queue.pending(forUserID: "user-one"))
        XCTAssertEqual(queue.pending(forUserID: "user-two"), other)
    }

    func testCardRequestsStayWithTheirAccountAndUnscopedRequestsAreClaimedOnce() {
        let queue = CardRequestQueue(defaults: defaults, key: "guest-requests",
                                     accountKey: "account-requests")
        let guest = PendingCardRequest(issuer: "Issuer G", cardName: "Guest Card")
        let first = PendingCardRequest(issuer: "Issuer A", cardName: "First Card")
        let second = PendingCardRequest(issuer: "Issuer B", cardName: "Second Card")
        queue.enqueue(guest)
        queue.enqueue(first, forUserID: "user-one")
        queue.enqueue(second, forUserID: "user-two")

        queue.claimUnscopedRequests(forUserID: "user-one")

        XCTAssertEqual(queue.pending(forUserID: "user-one").count, 2)
        XCTAssertTrue(queue.pending(forUserID: "user-one").contains(guest))
        XCTAssertTrue(queue.pending(forUserID: "user-one").contains(first))
        XCTAssertEqual(queue.pending(forUserID: "user-two"), [second])
        XCTAssertTrue(queue.pending().isEmpty)

        queue.removeAll(forUserID: "user-one")
        XCTAssertTrue(queue.pending(forUserID: "user-one").isEmpty)
        XCTAssertEqual(queue.pending(forUserID: "user-two"), [second])
    }
}
