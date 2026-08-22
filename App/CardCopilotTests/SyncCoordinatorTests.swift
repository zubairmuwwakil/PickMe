import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    func testInitialState() {
        let coordinator = SyncCoordinator()
        XCTAssertNil(coordinator.lastSyncedAt)
        XCTAssertNil(coordinator.syncIssue)
        XCTAssertFalse(coordinator.isSyncing)
        XCTAssertFalse(coordinator.isPreparingAccount)
        XCTAssertNil(coordinator.readySyncUserID)
        XCTAssertNil(coordinator.accountSetupUserID)
        XCTAssertTrue(coordinator.walletFeedback.isEmpty)
        XCTAssertTrue(coordinator.walletInstallations.isEmpty)
    }

    func testSaveAndClearSyncIssue() {
        let defaults = UserDefaults(suiteName: "ca.pickme.tests.sync-\(UUID().uuidString)")!
        let metadataStore = SyncMetadataStore(defaults: defaults, key: "meta", issueKey: "issues")
        let coordinator = SyncCoordinator(syncMetadataStore: metadataStore)

        coordinator.saveSyncIssue(kind: .warning, message: "Sync warning", forUserID: "user_123")
        XCTAssertEqual(metadataStore.issue(forUserID: "user_123")?.message, "Sync warning")
        XCTAssertEqual(metadataStore.issue(forUserID: "user_123")?.kind, .warning)

        coordinator.clearSyncIssue(forUserID: "user_123")
        XCTAssertNil(metadataStore.issue(forUserID: "user_123"))
    }

    func testRestoreSyncMetadata() {
        let defaults = UserDefaults(suiteName: "ca.pickme.tests.sync-\(UUID().uuidString)")!
        let metadataStore = SyncMetadataStore(defaults: defaults, key: "meta", issueKey: "issues")
        let date = Date(timeIntervalSince1970: 1000)
        metadataStore.save(lastSyncedAt: date, forUserID: "user_123")
        metadataStore.save(issue: SyncStatusIssue(kind: .error, message: "Failed", occurredAt: date), forUserID: "user_123")

        let coordinator = SyncCoordinator(syncMetadataStore: metadataStore)
        coordinator.restoreSyncMetadata(forUserID: "user_123")

        XCTAssertEqual(coordinator.lastSyncedAt, date)
        XCTAssertEqual(coordinator.syncIssue?.message, "Failed")
    }

    func testResetSyncedState() {
        let coordinator = SyncCoordinator()
        coordinator.lastSyncedAt = Date()
        coordinator.syncIssue = SyncStatusIssue(kind: .warning, message: "Warning")
        coordinator.readySyncUserID = "user_123"
        coordinator.accountSetupUserID = "user_123"

        coordinator.resetSyncedState()

        XCTAssertNil(coordinator.lastSyncedAt)
        XCTAssertNil(coordinator.syncIssue)
        XCTAssertNil(coordinator.readySyncUserID)
        XCTAssertNil(coordinator.accountSetupUserID)
    }

    func testAutoSyncSkipsWhenRecentlySynced() async {
        let coordinator = SyncCoordinator()
        coordinator.lastSyncedAt = Date() // Fresh sync right now
        coordinator.readySyncUserID = "user_123"

        let owner = OwnerState()
        let catalogue = Catalogue(cards: [], programs: [])

        let result = await coordinator.autoSyncIfStale(ownerState: owner, catalogue: catalogue, maxAge: 900)
        XCTAssertNil(result)
    }
}
