import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// Serves canned responses per path so a sync can be driven without a network or a Clerk session.
/// Unmatched paths fail the request rather than hanging, so a route this suite forgot to stub
/// shows up as a decisive failure instead of a timeout.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var routes: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requestedPaths: [String] = []

    static func reset() {
        routes = [:]
        requestedPaths = []
    }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.requestedPaths.append(path)
        let methodPath = "\(request.httpMethod ?? "GET") \(path)"
        guard let (status, body) = Self.routes[methodPath] ?? Self.routes[path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class SyncCoordinatorQueueIsolationTests: XCTestCase {
    private let baseURL = URL(string: "https://example.test/")!
    private let userID = "user_queue_isolation"

    private func ownerState() -> OwnerState {
        OwnerState(ownerStateVersion: "wallet-setup-1",
                   ownedCardIds: ["amex-cobalt"],
                   defaultCardId: "amex-cobalt",
                   switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                   carry: Carry(drawerCards: []),
                   cardStates: [:],
                   valuationsCad: Valuations())
    }

    private func coordinator(queueKey: String) -> SyncCoordinator {
        let defaults = UserDefaults(suiteName: queueKey)!
        defaults.removePersistentDomain(forName: queueKey)
        let localStore = OwnerStateLocalStore(defaults: defaults, key: "active")
        return SyncCoordinator(
            ownerStateLocalStore: localStore,
            accountOwnerStateStore: AccountOwnerStateStore(defaults: defaults,
                                                           profilesKey: "profiles",
                                                           activeUserKey: "active-user",
                                                           activeStore: localStore),
            ownerStateUploadQueue: OwnerStateUploadQueue(defaults: defaults, key: "pending"),
            syncMetadataStore: SyncMetadataStore(defaults: defaults,
                                                key: "metadata", issueKey: "issues"))
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        // The three routes OwnerStateSyncService.sync pulls. Empty bodies are enough: this suite
        // asserts that the sync RAN, not what it merged.
        StubURLProtocol.routes["/api/spine/caps"] = (200, Data(#"{"caps":{}}"#.utf8))
        StubURLProtocol.routes["/api/spine/feedback"] = (200, Data(#"{"feedback":[]}"#.utf8))
        StubURLProtocol.routes["/api/v1/wallet-installations"] = (200, Data("[]".utf8))
    }

    /// The regression that card-contracts@2.8 shipped: the hub's `.strict()` cardState schema
    /// 400'd every owner state carrying the new `flags` dictionary, and because this flush sat
    /// unguarded at the top of the sync, that 400 cancelled caps, feedback, card requests and
    /// wallet captures too — on every attempt, permanently, since a 400 is not a status a client
    /// retries out of.
    func testARejectedOwnerStateUploadDoesNotCancelTheRestOfTheSync() async throws {
        StubURLProtocol.routes["/api/spine/owner-state"] = (400, Data(#"{"error":"invalid owner state"}"#.utf8))
        let sync = coordinator(queueKey: "ca.pickme.tests.isolation-\(UUID().uuidString)")
        try sync.ownerStateUploadQueue.enqueue(ownerState(), forUserID: userID)
        let client = MoneyTalksAPIClient(baseURL: baseURL, tokenProvider: { "jwt" },
                                         session: StubURLProtocol.session)

        let result = await sync.performSync(ownerState: ownerState(), catalogue: .empty,
                                            userID: userID, client: client)

        XCTAssertNotNil(result, "caps and feedback must still sync when the wallet upload is refused")
        XCTAssertTrue(StubURLProtocol.requestedPaths.contains("/api/spine/caps"))
        XCTAssertTrue(StubURLProtocol.requestedPaths.contains("/api/spine/feedback"))
        // Read through the store, not the observable property: saveSyncIssue only mirrors into
        // `syncIssue` when Clerk reports the same signed-in user, and there is no Clerk session here.
        XCTAssertEqual(sync.syncMetadataStore.issue(forUserID: userID)?.kind, .warning,
                       "the refusal must be reported, not swallowed")
        XCTAssertTrue(sync.syncMetadataStore.issue(forUserID: userID)?.message.contains("wallet format") == true,
                      "the warning must tell the owner why this class of upload was refused")
    }

    /// The queued wallet is the owner's only unsynced answer set, and a 400 is frequently the
    /// SERVER's bug — this one was. Discarding it would have destroyed exactly the wallets that
    /// the hub-side schema fix went on to recover, so the entry is retained for the next attempt.
    func testARejectedOwnerStateUploadStaysQueuedForTheNextAttempt() async throws {
        StubURLProtocol.routes["/api/spine/owner-state"] = (400, Data(#"{"error":"invalid owner state"}"#.utf8))
        let sync = coordinator(queueKey: "ca.pickme.tests.retain-\(UUID().uuidString)")
        try sync.ownerStateUploadQueue.enqueue(ownerState(), forUserID: userID)
        let client = MoneyTalksAPIClient(baseURL: baseURL, tokenProvider: { "jwt" },
                                         session: StubURLProtocol.session)

        _ = await sync.performSync(ownerState: ownerState(), catalogue: .empty,
                                   userID: userID, client: client)

        XCTAssertNotNil(sync.ownerStateUploadQueue.pending(forUserID: userID))
    }

    /// The success path still clears the queue, so the guard above cannot be satisfied by simply
    /// never removing anything.
    func testAnAcceptedOwnerStateUploadLeavesTheQueueEmpty() async throws {
        StubURLProtocol.routes["/api/spine/owner-state"] = (200, Data(#"{"ownerState":null}"#.utf8))
        let sync = coordinator(queueKey: "ca.pickme.tests.accepted-\(UUID().uuidString)")
        try sync.ownerStateUploadQueue.enqueue(ownerState(), forUserID: userID)
        let client = MoneyTalksAPIClient(baseURL: baseURL, tokenProvider: { "jwt" },
                                         session: StubURLProtocol.session)

        let result = await sync.performSync(ownerState: ownerState(), catalogue: .empty,
                                            userID: userID, client: client)

        XCTAssertNotNil(result)
        XCTAssertNil(sync.ownerStateUploadQueue.pending(forUserID: userID))
    }

    func testSuccessfulSyncPersistsDownloadedCapProgress() async throws {
        let sync = coordinator(queueKey: "ca.pickme.tests.persist-\(UUID().uuidString)")
        var owner = try SeedLoader.loadOwnerState()
        owner.ownedCardIds = ["amex-cobalt"]
        owner.defaultCardId = "amex-cobalt"
        owner.cardStates = ["amex-cobalt": CardState()]
        try sync.accountOwnerStateStore.activate(owner, forUserID: userID)
        let response = try JSONEncoder().encode(["ownerState": owner])
        StubURLProtocol.routes["/api/spine/owner-state"] = (200, response)
        StubURLProtocol.routes["/api/spine/caps"] = (200, Data(#"{"caps":{"cobalt-eats-monthly":{"usedMinor":12345,"periodKey":"2026-09"}}}"#.utf8))
        let client = MoneyTalksAPIClient(baseURL: baseURL, tokenProvider: { "jwt" },
                                         session: StubURLProtocol.session)

        let result = await sync.performSync(ownerState: owner,
                                            catalogue: try SeedLoader.loadCatalogue(),
                                            userID: userID, client: client)

        XCTAssertEqual(result?.ownerState.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"], 123.45)
        XCTAssertEqual(sync.accountOwnerStateStore.state(forUserID: userID)?
            .cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"], 123.45)
        XCTAssertEqual(sync.ownerStateLocalStore.load()?
            .cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"], 123.45)
    }

    func testRemoteWalletReadFailureIsVisibleWhileCapsStillSync() async throws {
        let sync = coordinator(queueKey: "ca.pickme.tests.remote-read-\(UUID().uuidString)")
        StubURLProtocol.routes["GET /api/spine/owner-state"] = (500, Data(#"{"error":"offline"}"#.utf8))
        StubURLProtocol.routes["PUT /api/spine/owner-state"] = (200, Data())
        let client = MoneyTalksAPIClient(baseURL: baseURL, tokenProvider: { "jwt" },
                                         session: StubURLProtocol.session)

        let result = await sync.performSync(ownerState: ownerState(), catalogue: .empty,
                                            userID: userID, client: client)

        XCTAssertNotNil(result)
        XCTAssertTrue(sync.syncMetadataStore.issue(forUserID: userID)?.message
            .contains("other devices could not be downloaded") == true)
    }
}
