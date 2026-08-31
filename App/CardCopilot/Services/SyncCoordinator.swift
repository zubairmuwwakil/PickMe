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
    public let peerSyncService: PeerSyncService

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
        cardRequestQueue: CardRequestQueue = CardRequestQueue(),
        peerSyncService: PeerSyncService = PeerSyncService()
    ) {
        self.ownerStateLocalStore = ownerStateLocalStore
        self.accountOwnerStateStore = accountOwnerStateStore
        self.ownerStateUploadQueue = ownerStateUploadQueue
        self.syncMetadataStore = syncMetadataStore
        self.cardRequestQueue = cardRequestQueue
        self.peerSyncService = peerSyncService
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

        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        return await performSync(ownerState: ownerState, catalogue: catalogue,
                                 userID: userID, client: client)
    }

    /// The sync body, with account gating already resolved by the caller.
    ///
    /// Split out from `syncCapsSilently` because the guards above read `Clerk.shared`, which a
    /// test cannot populate — so the property this method exists to hold, that one job's failure
    /// never cancels the others, was unreachable by any test. It is the property that matters
    /// most here and the one that was silently violated.
    func performSync(
        ownerState: OwnerState,
        catalogue: Catalogue,
        userID: String,
        client: MoneyTalksAPIClient
    ) async -> OwnerStateSyncResult? {
        do {
            var warnings: [String] = []

            // Each durable queue is an INDEPENDENT job. A refused owner state must not cancel
            // caps, feedback, card requests or wallet captures — but it did, because this call
            // sat unguarded at the top of the do-block while the card-request flush below was
            // wrapped. card-contracts@2.8 turned that asymmetry into a total sync outage: the
            // hub's strict cardState schema 400'd every payload carrying the new
            // CardState.flags, and a 400 is not a status a client retries out of, so the outage
            // recurred on every attempt rather than clearing itself.
            //
            // The entry is deliberately left queued. A 4xx here is frequently the SERVER's bug —
            // this one was — and discarding the payload would destroy precisely the wallets a
            // server-side fix goes on to recover.
            do {
                try await flushQueuedOwnerState(forUserID: userID, using: client)
            } catch {
                warnings.append("Your wallet could not be uploaded yet.")
            }

            let result = try await OwnerStateSyncService(client: client).sync(ownerState: ownerState, catalogue: catalogue)

            walletFeedback = result.feedback
            let aliasStore = WalletCardAliasStore()
            for item in result.feedback { aliasStore.merge(raw: item.cardRaw, cardID: item.resolvedCardId) }
            if let installations = result.installations {
                walletInstallations = installations
            }
            lastSyncedAt = result.lastSyncedAt
            syncMetadataStore.save(lastSyncedAt: result.lastSyncedAt, forUserID: userID)

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

    public func createInstallation(label: String) async throws -> WalletCaptureConnectionTestResult {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              let userID = Clerk.shared.user?.id, readySyncUserID == userID,
              accountOwnerStateStore.activeUserID == userID else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outbox = try WalletOutboxStore(root: root)
        let credentialStore = WalletCaptureCredentialStore()
        let previous = credentialStore.load()
        if let previous, previous.boundUserID != userID {
            // Captures assigned while another account was active need explicit consent before
            // they can be delivered to this account, even if creating the new connection fails.
            try await outbox.requireAccountChoiceForAssignedCaptures()
        }

        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        let installation = try await client.createWalletInstallation(label: label)
        guard let token = installation.token else {
            try? await client.revokeWalletInstallation(id: installation.id)
            throw MoneyTalksAPIError.unexpectedResponse(-1)
        }
        if let previous, previous.installationID != installation.id {
            let revoked = await WalletCaptureHTTPUploader(baseURL: baseURL, token: previous.token).revokeInstallation()
            if !revoked {
                try? await client.revokeWalletInstallation(id: installation.id)
                throw MoneyTalksAPIError.unexpectedResponse(409, detail: "The previous Wallet Capture connection could not be safely replaced.")
            }
        }
        let settings = WalletCaptureSettingsStore()
        do {
            try credentialStore.save(.init(token: token,
                                           installationID: installation.id,
                                           boundUserID: userID))
        } catch {
            // Do not leave a server-side credential active if this iPhone could not retain it.
            try? await client.revokeWalletInstallation(id: installation.id)
            credentialStore.remove()
            settings.clearConnection()
            throw error
        }
        settings.markConnectionPending(boundUserID: userID)
        let captureUploader = WalletCaptureHTTPUploader(baseURL: baseURL, token: token)
        let connectionResult = await captureUploader.testConnectionResult()
        if connectionResult.isConnected {
            settings.markConnectionVerified(boundUserID: userID)
            try await outbox.releaseAuthenticationBlocks()
            await drainWalletCaptures(forUserID: userID)
        }
        // The one-time raw token belongs only in Keychain. Return only the safe probe result;
        // callers have no reason to retain a second copy of the credential in UI state.
        walletInstallations.insert(.init(id: installation.id, label: installation.label,
                                         createdAt: installation.createdAt, revokedAt: installation.revokedAt), at: 0)
        return connectionResult
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
        let summary = await coordinator.drain()
        if summary.accepted + summary.duplicates > 0,
           WalletCaptureSettingsStore().load().connectionVerifiedAt == nil {
            WalletCaptureSettingsStore().markConnectionVerified(boundUserID: credential.boundUserID)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let diagnostics, let runLogs = try? WalletCaptureShortcutRunLogStore(documentsDirectory: documents),
           let records = try? await diagnostics.records() {
            for record in records { try? await runLogs.refreshDelivery(eventID: record.eventID, diagnostic: record) }
        }
    }

    public func testWalletCaptureConnection() async -> WalletCaptureConnectionTestResult {
        guard let credential = WalletCaptureCredentialStore().load() else {
            return .init(isConnected: false, failureReason: "No secure connection is stored on this iPhone.")
        }
        guard let signedInUserID = Clerk.shared.user?.id else {
            return .init(isConnected: false, failureReason: "Sign in before testing the secure connection.")
        }
        guard signedInUserID == credential.boundUserID else {
            return .init(isConnected: false, failureReason: "This secure connection belongs to a different signed-in account.")
        }
        guard let baseURL = MoneyTalksConfiguration.apiBaseURL else {
            return .init(isConnected: false, failureReason: "The Inunity server URL is not configured.")
        }
        let result = await WalletCaptureHTTPUploader(baseURL: baseURL, token: credential.token).testConnectionResult()
        if result.isConnected {
            WalletCaptureSettingsStore().markConnectionVerified(boundUserID: credential.boundUserID)
            let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let outbox = try? WalletOutboxStore(root: root) {
                try? await outbox.releaseAuthenticationBlocks()
            }
            await drainWalletCaptures(forUserID: signedInUserID)
        }
        return result
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
        if let outbox = try? WalletOutboxStore(root: root) {
            let pending = (try? await outbox.captures(in: .pending)) ?? []
            let inflight = (try? await outbox.captures(in: .inflight)) ?? []
            let unassigned = (try? await outbox.captures(in: .unassigned)) ?? []
            let quarantined = (try? await outbox.captures(in: .quarantined)) ?? []
            let unsent = pending + inflight + unassigned + quarantined
            if !deleteUnsent && !unsent.isEmpty {
                throw URLError(.cannotConnectToHost)
            }
            explicitlyDeletedIDs = unsent.map(\.event.eventId)
        }
        if let credential, let baseURL = MoneyTalksConfiguration.apiBaseURL {
            _ = await WalletCaptureHTTPUploader(baseURL: baseURL, token: credential.token).revokeInstallation()
            if let userID = Clerk.shared.user?.id, readySyncUserID == userID,
               accountOwnerStateStore.activeUserID == userID {
                let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
                try? await client.revokeWalletInstallation(id: credential.installationID)
            }
            let revokedAt = Date()
            walletInstallations = walletInstallations.map { item in
                item.id == credential.installationID ? .init(id: item.id, label: item.label, createdAt: item.createdAt,
                                                            revokedAt: revokedAt) : item
            }
        }
        if deleteUnsent, let outbox = try? WalletOutboxStore(root: root) {
            try await outbox.deleteAllUnsent()
            if let diagnostics = try? WalletCaptureDiagnosticsStore(root: root) {
                for eventID in explicitlyDeletedIDs { try? await diagnostics.delete(eventID: eventID) }
            }
        }
        WalletCaptureCredentialStore().remove()
        WalletCaptureSettingsStore().setEnabled(false)
        WalletCaptureSettingsStore().clearConnection()
    }

    public func enableWalletCapture() async {
        let settings = WalletCaptureSettingsStore()
        settings.setEnabled(true)
        if let credential = WalletCaptureCredentialStore().load() {
            if settings.load().connectionVerifiedAt == nil {
                settings.markConnectionVerified(boundUserID: credential.boundUserID)
            }
            await drainWalletCaptures(forUserID: credential.boundUserID)
        } else if let userID = Clerk.shared.user?.id {
            if settings.load().boundUserID == nil {
                settings.markConnectionPending(boundUserID: userID)
            }
        }
    }

    public func pauseWalletCapture() {
        WalletCaptureSettingsStore().setEnabled(false)
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
