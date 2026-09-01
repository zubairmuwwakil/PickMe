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

    func testAnOlderUploadCompletionCannotDeleteANewerQueuedWallet() throws {
        let queue = OwnerStateUploadQueue(defaults: defaults, key: "uploads")
        let uploaded = try owner(defaultCardID: "amex-cobalt")
        let newer = try owner(defaultCardID: "wealthsimple-vip")
        try queue.enqueue(uploaded, forUserID: "user-one")
        try queue.enqueue(newer, forUserID: "user-one")

        XCTAssertFalse(queue.removeIfMatching(uploaded, forUserID: "user-one"))
        XCTAssertEqual(queue.pending(forUserID: "user-one"), newer)
        XCTAssertTrue(queue.removeIfMatching(newer, forUserID: "user-one"))
        XCTAssertNil(queue.pending(forUserID: "user-one"))
    }

    func testFirstRunWalletSavesLocallyWhenSignedInAccountBindingWasNotPrepared() throws {
        let accountStore = AccountOwnerStateStore(defaults: defaults, profilesKey: "profiles",
                                                  activeUserKey: "bound", activeStore: activeStore)
        let uploadQueue = OwnerStateUploadQueue(defaults: defaults, key: "uploads")
        let cardRequests = CardRequestQueue(defaults: defaults, key: "guest-requests",
                                            accountKey: "account-requests")
        let saver = WalletSetupPersistence(accountStore: accountStore, uploadQueue: uploadQueue,
                                           cardRequestQueue: cardRequests)
        let wallet = try owner(defaultCardID: "amex-platinum")

        let outcome = try saver.save(wallet, signedInUserID: "user-one", preparedSetupUserID: nil)

        XCTAssertEqual(outcome, .savedLocallyAwaitingAccountBinding(userID: "user-one"))
        XCTAssertEqual(activeStore.load(), wallet)
        XCTAssertNil(accountStore.activeUserID)
        XCTAssertNil(uploadQueue.pending(forUserID: "user-one"))
    }

    func testPreparedFirstRunAccountBindsWalletAndQueuesUpload() throws {
        let accountStore = AccountOwnerStateStore(defaults: defaults, profilesKey: "profiles",
                                                  activeUserKey: "bound", activeStore: activeStore)
        let uploadQueue = OwnerStateUploadQueue(defaults: defaults, key: "uploads")
        let cardRequests = CardRequestQueue(defaults: defaults, key: "guest-requests",
                                            accountKey: "account-requests")
        let pendingRequest = PendingCardRequest(issuer: "Issuer", cardName: "Pending Card")
        cardRequests.enqueue(pendingRequest)
        let saver = WalletSetupPersistence(accountStore: accountStore, uploadQueue: uploadQueue,
                                           cardRequestQueue: cardRequests)
        let wallet = try owner(defaultCardID: "amex-platinum")

        let outcome = try saver.save(wallet, signedInUserID: "user-one",
                                     preparedSetupUserID: "user-one")

        XCTAssertEqual(outcome, .savedAndQueued(userID: "user-one"))
        XCTAssertEqual(accountStore.activeUserID, "user-one")
        XCTAssertEqual(accountStore.state(forUserID: "user-one"), wallet)
        XCTAssertEqual(uploadQueue.pending(forUserID: "user-one"), wallet)
        XCTAssertEqual(cardRequests.pending(forUserID: "user-one"), [pendingRequest])
        XCTAssertTrue(cardRequests.pending().isEmpty)
    }

    func testEditingBoundWalletUpdatesProfileAndQueuesLatestValue() throws {
        let accountStore = AccountOwnerStateStore(defaults: defaults, profilesKey: "profiles",
                                                  activeUserKey: "bound", activeStore: activeStore)
        let uploadQueue = OwnerStateUploadQueue(defaults: defaults, key: "uploads")
        let cardRequests = CardRequestQueue(defaults: defaults, key: "guest-requests",
                                            accountKey: "account-requests")
        let saver = WalletSetupPersistence(accountStore: accountStore, uploadQueue: uploadQueue,
                                           cardRequestQueue: cardRequests)
        try accountStore.activate(try owner(defaultCardID: "amex-cobalt"), forUserID: "user-one")
        let editedWallet = try owner(defaultCardID: "amex-platinum")

        let outcome = try saver.save(editedWallet, signedInUserID: "user-one",
                                     preparedSetupUserID: nil)

        XCTAssertEqual(outcome, .savedAndQueued(userID: "user-one"))
        XCTAssertEqual(activeStore.load(), editedWallet)
        XCTAssertEqual(accountStore.state(forUserID: "user-one"), editedWallet)
        XCTAssertEqual(uploadQueue.pending(forUserID: "user-one"), editedWallet)
    }

    func testDifferentSignedInAccountCannotOverwriteBoundWallet() throws {
        let accountStore = AccountOwnerStateStore(defaults: defaults, profilesKey: "profiles",
                                                  activeUserKey: "bound", activeStore: activeStore)
        let uploadQueue = OwnerStateUploadQueue(defaults: defaults, key: "uploads")
        let cardRequests = CardRequestQueue(defaults: defaults, key: "guest-requests",
                                            accountKey: "account-requests")
        let saver = WalletSetupPersistence(accountStore: accountStore, uploadQueue: uploadQueue,
                                           cardRequestQueue: cardRequests)
        let originalWallet = try owner(defaultCardID: "amex-cobalt")
        try accountStore.activate(originalWallet, forUserID: "user-one")

        let outcome = try saver.save(try owner(defaultCardID: "amex-platinum"),
                                     signedInUserID: "user-two", preparedSetupUserID: nil)

        XCTAssertEqual(outcome, .accountMismatch(activeUserID: "user-one",
                                                 signedInUserID: "user-two"))
        XCTAssertEqual(activeStore.load(), originalWallet)
        XCTAssertEqual(accountStore.state(forUserID: "user-one"), originalWallet)
        XCTAssertNil(accountStore.state(forUserID: "user-two"))
        XCTAssertNil(uploadQueue.pending(forUserID: "user-one"))
        XCTAssertNil(uploadQueue.pending(forUserID: "user-two"))
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
