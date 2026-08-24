import Foundation
import CardCopilotEngine
import CardCopilotStore
import CardCopilotCapture
import ClerkKit
import Observation
import WidgetKit

/// Coordinates remote synchronization with Inunity, durable queues, and account binding.
/// Keeps network and sync concerns isolated from SwiftUI checkout flow views.
@Observable
@MainActor
public final class SyncCoordinator {
    public var lastSyncedAt: Date?
    public var syncIssue: SyncStatusIssue?
    public var isSyncing = false
    public var isPreparingAccount = false
    public var readySyncUserID: String?
    public var accountSetupUserID: String?
    public var walletFeedback: [WalletFeedback] = []
    public var walletInstallations: [WalletInstallation] = []

    public let ownerStateLocalStore: OwnerStateLocalStore
    public let accountOwnerStateStore: AccountOwnerStateStore
    public let ownerStateUploadQueue: OwnerStateUploadQueue
    public let syncMetadataStore: SyncMetadataStore
    public let cardRequestQueue: CardRequestQueue

    public init(
        ownerStateLocalStore: OwnerStateLocalStore = OwnerStateLocalStore(),
        accountOwnerStateStore: AccountOwnerStateStore = AccountOwnerStateStore(),
        ownerStateUploadQueue: OwnerStateUploadQueue = OwnerStateUploadQueue(),
        syncMetadataStore: SyncMetadataStore = SyncMetadataStore(),
        cardRequestQueue: CardRequestQueue = CardRequestQueue()
    ) {
        self.ownerStateLocalStore = ownerStateLocalStore
        self.accountOwnerStateStore = accountOwnerStateStore
        self.ownerStateUploadQueue = ownerStateUploadQueue
        self.syncMetadataStore = syncMetadataStore
        self.cardRequestQueue = cardRequestQueue
    }

    /// Automatically syncs if signed in, configured, and last synced longer than `maxAge` ago.
    @discardableResult
    public func autoSyncIfStale(
        ownerState: OwnerState,
        catalogue: Catalogue,
        maxAge: TimeInterval = 15 * 60
    ) async -> OwnerStateSyncResult? {
        guard MoneyTalksConfiguration.isConfigured,
              !isSyncing,
              let userID = Clerk.shared.user?.id,
              readySyncUserID == userID,
              accountOwnerStateStore.activeUserID == userID else {
            return nil
        }

        if let last = lastSyncedAt, Date().timeIntervalSince(last) < maxAge {
            return nil
        }

        return await syncCapsSilently(ownerState: ownerState, catalogue: catalogue)
    }

    /// Silently syncs caps, pulls feedback, and flushes durable outboxes without interrupting checkout.
    @discardableResult
    public func syncCapsSilently(
        ownerState: OwnerState,
        catalogue: Catalogue
    ) async -> OwnerStateSyncResult? {
        guard MoneyTalksConfiguration.isConfigured,
              !isSyncing,
              let baseURL = MoneyTalksConfiguration.apiBaseURL,
              let userID = Clerk.shared.user?.id,
              readySyncUserID == userID,
              accountOwnerStateStore.activeUserID == userID else {
            return nil
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
            try await flushQueuedOwnerState(forUserID: userID, using: client)
            let result = try await OwnerStateSyncService(client: client).sync(ownerState: ownerState, catalogue: catalogue)

            walletFeedback = result.feedback
            let aliasStore = WalletCardAliasStore()
            for item in result.feedback { aliasStore.merge(raw: item.cardRaw, cardID: item.resolvedCardId) }
            if let installations = result.installations {
                walletInstallations = installations
            }
            lastSyncedAt = result.lastSyncedAt
            syncMetadataStore.save(lastSyncedAt: result.lastSyncedAt, forUserID: userID)

            var warnings: [String] = []
            if result.installationRefreshError != nil {
                warnings.append("Connected Wallet tokens could not be refreshed.")
            }
            do {
                try await flushQueuedCardRequests(forUserID: userID, using: client)
            } catch {
                warnings.append("A queued card request could not be sent yet.")
            }
            await drainWalletCaptures(forUserID: userID)

            if warnings.isEmpty {
                clearSyncIssue(forUserID: userID)
            } else {
                saveSyncIssue(
                    kind: .warning,
                    message: "Caps and feedback synced, but \(warnings.joined(separator: " "))",
                    forUserID: userID
                )
            }

            // Reload widgets so on-device caps and shortcuts reflect new sync
            WidgetCenter.shared.reloadAllTimelines()

            return result
        } catch {
            // A1: existing local state is usable; connectivity must never interrupt checkout.
            saveSyncFailure(error, forUserID: userID)
            return nil
        }
    }

    public func flushQueuedCardRequests(forUserID userID: String,
                                        using client: MoneyTalksAPIClient) async throws {
        for request in cardRequestQueue.pending(forUserID: userID) {
            try await client.createCardRequest(request)
            cardRequestQueue.remove(request, forUserID: userID)
        }
    }

    public func flushQueuedOwnerState(forUserID userID: String,
                                      using client: MoneyTalksAPIClient) async throws {
        guard let pending = ownerStateUploadQueue.pending(forUserID: userID) else { return }
        try await client.updateOwnerState(pending)
        ownerStateUploadQueue.remove(forUserID: userID)
    }

    public func createInstallation(label: String) async throws -> String {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              let userID = Clerk.shared.user?.id, readySyncUserID == userID,
              accountOwnerStateStore.activeUserID == userID else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        let installation = try await client.createWalletInstallation(label: label)
        guard let token = installation.token else { throw MoneyTalksAPIError.unexpectedResponse(-1) }
        if let previous = WalletCaptureCredentialStore().load(), previous.installationID != installation.id {
            let revoked = await WalletCaptureHTTPUploader(baseURL: baseURL, token: previous.token).revokeInstallation()
            if !revoked {
                try? await client.revokeWalletInstallation(id: installation.id)
                throw MoneyTalksAPIError.unexpectedResponse(409, detail: "The previous Wallet Capture connection could not be safely replaced.")
            }
        }
        try WalletCaptureCredentialStore().save(.init(token: token,
                                                      installationID: installation.id,
                                                      boundUserID: userID))
        let captureUploader = WalletCaptureHTTPUploader(baseURL: baseURL, token: token)
        if await captureUploader.testConnection() {
            WalletCaptureSettingsStore().markConnectionVerified(boundUserID: userID)
        }
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let outbox = try? WalletOutboxStore(root: root) {
            try await outbox.releaseAuthenticationBlocks()
        }
        WalletCaptureSettingsStore().setEnabled(true)
        // The one-time raw token belongs only in Keychain. Do not retain a
        // second copy in observable UI state for the lifetime of the screen.
        walletInstallations.insert(.init(id: installation.id, label: installation.label,
                                         createdAt: installation.createdAt, revokedAt: installation.revokedAt), at: 0)
        return token
    }

    public func revokeWalletInstallation(id: String) async throws {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              let userID = Clerk.shared.user?.id, readySyncUserID == userID,
              accountOwnerStateStore.activeUserID == userID else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        try await client.revokeWalletInstallation(id: id)
        let revokedAt = Date()
        walletInstallations = walletInstallations.map { item in
            item.id == id ? .init(id: item.id, label: item.label, createdAt: item.createdAt,
                                  revokedAt: revokedAt) : item
        }
        if WalletCaptureCredentialStore().load()?.installationID == id {
            WalletCaptureCredentialStore().remove()
            WalletCaptureSettingsStore().clearConnection()
        }
    }

    public func drainWalletCaptures(forUserID userID: String? = nil) async {
        guard let credential = WalletCaptureCredentialStore().load(),
              userID == nil || credential.boundUserID == userID,
              let baseURL = MoneyTalksConfiguration.apiBaseURL else { return }
        if let signedInUserID = Clerk.shared.user?.id, signedInUserID != credential.boundUserID { return }
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let outbox = try? WalletOutboxStore(root: root) else { return }
        let diagnostics = try? WalletCaptureDiagnosticsStore(root: root)
        let coordinator = WalletCaptureCoordinator(outbox: outbox,
            uploader: WalletCaptureHTTPUploader(baseURL: baseURL, token: credential.token),
            diagnostics: diagnostics,
            drainObserver: { summary in await WalletCaptureNotificationCoordinator.publishDrain(summary) },
            isOffline: { WalletCaptureNetworkMonitor.shared.isOffline })
        await coordinator.drain()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let diagnostics, let runLogs = try? WalletCaptureShortcutRunLogStore(documentsDirectory: documents),
           let records = try? await diagnostics.records() {
            for record in records { try? await runLogs.refreshDelivery(eventID: record.eventID, diagnostic: record) }
        }
    }

    public func testWalletCaptureConnection() async -> Bool {
        guard let credential = WalletCaptureCredentialStore().load(),
              Clerk.shared.user?.id == credential.boundUserID,
              let baseURL = MoneyTalksConfiguration.apiBaseURL else { return false }
        let valid = await WalletCaptureHTTPUploader(baseURL: baseURL, token: credential.token).testConnection()
        if valid { WalletCaptureSettingsStore().markConnectionVerified(boundUserID: credential.boundUserID) }
        return valid
    }

    public func assignUnassignedCaptures() async throws {
        guard let credential = WalletCaptureCredentialStore().load(),
              let signedInUserID = Clerk.shared.user?.id,
              credential.boundUserID == signedInUserID else {
            throw URLError(.userAuthenticationRequired)
        }
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outbox = try WalletOutboxStore(root: root)
        let assigned = try await outbox.captures(in: .unassigned)
        try await outbox.assignUnassignedToPending()
        if let diagnostics = try? WalletCaptureDiagnosticsStore(root: root) {
            for var capture in assigned {
                capture.deliveryState = .pending
                try? await diagnostics.update(eventID: capture.event.eventId, capture: capture)
            }
        }
        await drainWalletCaptures(forUserID: Clerk.shared.user?.id)
    }

    public func deleteUnassignedCaptures() async throws {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outbox = try WalletOutboxStore(root: root)
        let diagnostics = try? WalletCaptureDiagnosticsStore(root: root)
        for capture in try await outbox.captures(in: .unassigned) {
            try await outbox.delete(eventID: capture.event.eventId, from: .unassigned)
            try? await diagnostics?.delete(eventID: capture.event.eventId)
        }
    }

    public func disableWalletCapture(deleteUnsent: Bool) async throws {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let credential = WalletCaptureCredentialStore().load()
        if !deleteUnsent, let credential { await drainWalletCaptures(forUserID: credential.boundUserID) }
        var explicitlyDeletedIDs: [String] = []
        var unsentCount = 0
        if let outbox = try? WalletOutboxStore(root: root) {
            let pending = (try? await outbox.captures(in: .pending)) ?? []
            let inflight = (try? await outbox.captures(in: .inflight)) ?? []
            let unassigned = (try? await outbox.captures(in: .unassigned)) ?? []
            let quarantined = (try? await outbox.captures(in: .quarantined)) ?? []
            let unsent = pending + inflight + unassigned + quarantined
            unsentCount = unsent.count
            if !deleteUnsent && !unsent.isEmpty {
                throw URLError(.cannotConnectToHost)
            }
            explicitlyDeletedIDs = unsent.map(\.event.eventId)
        }
        if let credential {
            guard let baseURL = MoneyTalksConfiguration.apiBaseURL,
                  await WalletCaptureHTTPUploader(baseURL: baseURL, token: credential.token).revokeInstallation() else {
                throw URLError(.userAuthenticationRequired)
            }
        } else if !deleteUnsent && unsentCount > 0 {
            throw URLError(.userAuthenticationRequired)
        }
        if deleteUnsent, let outbox = try? WalletOutboxStore(root: root) {
            try await outbox.deleteAllUnsent()
            if let diagnostics = try? WalletCaptureDiagnosticsStore(root: root) {
                for eventID in explicitlyDeletedIDs { try? await diagnostics.delete(eventID: eventID) }
            }
        }
        WalletCaptureCredentialStore().remove(); WalletCaptureSettingsStore().setEnabled(false)
        WalletCaptureSettingsStore().clearConnection()
    }

    public func submitDiagnostic(_ report: WalletCaptureDiagnosticReport) async throws -> WalletSubmittedDiagnostic {
        guard let baseURL = MoneyTalksConfiguration.apiBaseURL else { throw MoneyTalksAPIError.unavailableConfiguration }
        return try await WalletCaptureDiagnosticsHTTPClient(baseURL: baseURL) {
            try await Clerk.shared.auth.getToken()
        }.submit(report)
    }

    public func deleteSubmittedDiagnostic(id: String) async throws {
        guard let baseURL = MoneyTalksConfiguration.apiBaseURL else { throw MoneyTalksAPIError.unavailableConfiguration }
        try await WalletCaptureDiagnosticsHTTPClient(baseURL: baseURL) {
            try await Clerk.shared.auth.getToken()
        }.delete(id: id)
    }

    public func listSubmittedDiagnostics() async throws -> [WalletSubmittedDiagnostic] {
        guard let baseURL = MoneyTalksConfiguration.apiBaseURL else { throw MoneyTalksAPIError.unavailableConfiguration }
        return try await WalletCaptureDiagnosticsHTTPClient(baseURL: baseURL) {
            try await Clerk.shared.auth.getToken()
        }.list()
    }

    public func restoreSyncMetadata(forUserID userID: String?) {
        lastSyncedAt = userID.flatMap { syncMetadataStore.lastSyncedAt(forUserID: $0) }
        syncIssue = userID.flatMap { syncMetadataStore.issue(forUserID: $0) }
    }

    public func resetSyncedState() {
        lastSyncedAt = nil
        syncIssue = nil
        walletFeedback = []
        walletInstallations = []
        readySyncUserID = nil
        accountSetupUserID = nil
    }

    public func saveSyncFailure(_ error: Error, forUserID userID: String) {
        #if DEBUG
        print("❌ PickMe sync error: \(error)")
        #endif
        let message: String
        if let apiError = error as? MoneyTalksAPIError {
            switch apiError {
            case .unauthenticated:
                message = "Your sign-in expired. Sign in again, then retry sync."
            case .unavailableConfiguration:
                message = "Sync is not configured in this build. Your on-device wallet is still available."
            case .unexpectedResponse:
                message = "Inunity could not finish the sync. Your on-device wallet is still available."
            }
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost:
                message = "Could not reach Inunity. Check your connection and retry."
            default:
                message = "Sync could not finish. Your on-device wallet is still available."
            }
        } else {
            message = "Sync could not finish. Your on-device wallet is still available."
        }
        saveSyncIssue(kind: .error, message: message, forUserID: userID)
    }

    public func saveSyncIssue(kind: SyncStatusIssue.Kind, message: String, forUserID userID: String) {
        let issue = SyncStatusIssue(kind: kind, message: message)
        syncMetadataStore.save(issue: issue, forUserID: userID)
        if Clerk.shared.user?.id == userID { syncIssue = issue }
    }

    public func clearSyncIssue(forUserID userID: String) {
        syncMetadataStore.clearIssue(forUserID: userID)
        if Clerk.shared.user?.id == userID { syncIssue = nil }
    }
}
