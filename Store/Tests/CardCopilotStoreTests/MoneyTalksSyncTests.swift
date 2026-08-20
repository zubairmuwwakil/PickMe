import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class MoneyTalksSyncTests: XCTestCase {
    private let baseURL = URL(string: "https://example.test/")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func client() -> MoneyTalksAPIClient {
        MoneyTalksAPIClient(baseURL: baseURL, tokenProvider: { "session-jwt" },
                            session: StubURLProtocol.session)
    }

    func testMergeConvertsMinorUnitsIntoTheExistingOwnerStateCapUnits() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()

        let merged = OwnerStateSyncService.merging(
            ["cobalt-eats-monthly": SpineCap(usedMinor: 249_975, periodKey: "2026-08")],
            into: owner, catalogue: catalogue)

        XCTAssertEqual(merged.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"], 2499.75)
    }

    func testMergeKeepsExistingCapProgressWhenTheResponseDoesNotContainThatCap() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let before = owner.cardStates["amex-cobalt"]?.capProgress

        let merged = OwnerStateSyncService.merging([:], into: owner, catalogue: catalogue)

        XCTAssertEqual(merged.cardStates["amex-cobalt"]?.capProgress, before)
    }

    func testWalletInstallationDecodesCorrectly() throws {
        let json = """
        {
            "id": "inst_123",
            "label": "My iPhone",
            "createdAt": "2026-08-19T12:00:00Z",
            "revokedAt": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let installation = try decoder.decode(WalletInstallation.self, from: json)

        XCTAssertEqual(installation.id, "inst_123")
        XCTAssertEqual(installation.label, "My iPhone")
        XCTAssertNil(installation.revokedAt)
        XCTAssertNil(installation.token)
    }

    func testSyncResultCarriesInstallations() throws {
        let owner = try SeedLoader.loadOwnerState()
        let now = Date()
        let inst = WalletInstallation(id: "inst_1", label: "My Phone", createdAt: now)
        let result = OwnerStateSyncResult(ownerState: owner, feedback: [], installations: [inst], lastSyncedAt: now)
        let installations = try XCTUnwrap(result.installations)

        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installations.first?.id, "inst_1")
        XCTAssertEqual(installations.first?.label, "My Phone")
        XCTAssertNil(result.installationRefreshError)
    }

    func testFailedInstallationRefreshIsDistinctFromConfirmedEmptyList() throws {
        let owner = try SeedLoader.loadOwnerState()
        let now = Date()
        let result = OwnerStateSyncResult(ownerState: owner, feedback: [], installations: nil,
                                          installationRefreshError: "offline", lastSyncedAt: now)

        XCTAssertNil(result.installations)
        XCTAssertEqual(result.installationRefreshError, "offline")
    }

    func testOwnerStateUploadSendsTheCompleteWallet() async throws {
        let owner = try SeedLoader.loadOwnerState()

        try await client().updateOwnerState(owner)

        let request = try XCTUnwrap(StubURLProtocol.capturedRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/spine/owner-state")
        let uploaded = try JSONDecoder().decode(OwnerState.self,
                                                from: try XCTUnwrap(StubURLProtocol.capturedBody))
        XCTAssertEqual(uploaded, owner)
    }

    func testFetchOwnerStateReturnsTheAccountWallet() async throws {
        struct Response: Encodable { let ownerState: OwnerState }
        let owner = try SeedLoader.loadOwnerState()
        StubURLProtocol.reset(responseData: try JSONEncoder().encode(Response(ownerState: owner)))

        let fetched = try await client().fetchOwnerState()

        XCTAssertEqual(fetched, owner)
        XCTAssertEqual(StubURLProtocol.capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(StubURLProtocol.capturedRequest?.url?.path, "/api/spine/owner-state")
    }
}
