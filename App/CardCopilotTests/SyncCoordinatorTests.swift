import XCTest
import CardCopilotEngine
import CardCopilotStore
import CardCopilotCapture
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

        // Placeholders only: the recency guard returns before either is read. Built through the
        // real initialisers rather than convenience stubs so this test keeps failing loudly if
        // OwnerState's shape changes — which is how it silently stopped compiling in the first place.
        let owner = OwnerState(ownerStateVersion: "1",
                               ownedCardIds: [],
                               defaultCardId: "",
                               switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0,
                                                                minAdvantageCad: 0,
                                                                semantics: "either"),
                               carry: Carry(drawerCards: []),
                               cardStates: [:],
                               valuationsCad: Valuations())
        let catalogue = Catalogue.empty

        let result = await coordinator.autoSyncIfStale(ownerState: owner, catalogue: catalogue, maxAge: 900)
        XCTAssertNil(result)
    }

    func testDisableWalletCaptureDeletesUnsentAndClearsCredentialsLocallyEvenIfRemoteFails() async throws {
        let coordinator = SyncCoordinator()
        let credentialStore = WalletCaptureCredentialStore(service: "ca.pickme.tests.disable-\(UUID().uuidString)")
        let settingsStore = WalletCaptureSettingsStore(suiteName: "ca.pickme.tests.disable-settings-\(UUID().uuidString)")

        do {
            try credentialStore.save(.init(token: "invalid-or-unreachable-token", installationID: "inst_123", boundUserID: "user_123"))
        } catch {
            // Keychain save may fail in unsigned test runners without Keychain entitlement (-34018)
        }
        settingsStore.markConnectionVerified(boundUserID: "user_123")
        XCTAssertTrue(settingsStore.load().isEnabled)

        // Calling disableWalletCapture with deleteUnsent: true must succeed locally without throwing URLError -1013
        try await coordinator.disableWalletCapture(deleteUnsent: true)

        XCTAssertNil(WalletCaptureCredentialStore().load())
        XCTAssertFalse(WalletCaptureSettingsStore().load().isEnabled)
        XCTAssertNil(WalletCaptureSettingsStore().load().connectionVerifiedAt)
    }
}
