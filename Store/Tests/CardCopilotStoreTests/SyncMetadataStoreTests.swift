import XCTest
@testable import CardCopilotStore

final class SyncMetadataStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SyncMetadataStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripsLastSyncTime() {
        let store = SyncMetadataStore(defaults: defaults, key: "sync", issueKey: "issues")
        let date = Date(timeIntervalSince1970: 1_787_108_760)

        store.save(lastSyncedAt: date, forUserID: "user-one")

        XCTAssertEqual(store.lastSyncedAt(forUserID: "user-one"), date)
    }

    func testKeepsAccountsSeparateAndRemovesOnlyRequestedAccount() {
        let store = SyncMetadataStore(defaults: defaults, key: "sync", issueKey: "issues")
        let first = Date(timeIntervalSince1970: 1_787_108_760)
        let second = Date(timeIntervalSince1970: 1_787_109_000)
        store.save(lastSyncedAt: first, forUserID: "user-one")
        store.save(lastSyncedAt: second, forUserID: "user-two")

        XCTAssertEqual(store.lastSyncedAt(forUserID: "user-one"), first)
        XCTAssertEqual(store.lastSyncedAt(forUserID: "user-two"), second)

        store.remove(forUserID: "user-one")

        XCTAssertNil(store.lastSyncedAt(forUserID: "user-one"))
        XCTAssertEqual(store.lastSyncedAt(forUserID: "user-two"), second)
    }

    func testIssuePersistsUntilClearedWithoutChangingLastSuccess() {
        let store = SyncMetadataStore(defaults: defaults, key: "sync", issueKey: "issues")
        let success = Date(timeIntervalSince1970: 1_787_108_760)
        let failed = Date(timeIntervalSince1970: 1_787_109_000)
        let issue = SyncStatusIssue(kind: .error, message: "Couldn't reach Inunity.", occurredAt: failed)
        store.save(lastSyncedAt: success, forUserID: "user-one")

        store.save(issue: issue, forUserID: "user-one")

        XCTAssertEqual(store.lastSyncedAt(forUserID: "user-one"), success)
        XCTAssertEqual(store.issue(forUserID: "user-one"), issue)

        store.clearIssue(forUserID: "user-one")
        XCTAssertNil(store.issue(forUserID: "user-one"))
        XCTAssertEqual(store.lastSyncedAt(forUserID: "user-one"), success)
    }
}
