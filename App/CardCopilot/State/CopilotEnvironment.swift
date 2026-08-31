import Foundation
import Observation
import SwiftData
import CardCopilotEngine
import CardCopilotStore
import CardCopilotCapture
import ClerkKit

/// The loaded dependency graph. Lifted verbatim from `CheckoutFlowView.Dependencies` — the
/// members and both computed properties are unchanged, so every consumer keeps working.
struct DependencyGraph {
    let catalogue: Catalogue
    /// Ids into `catalogue`, not a second card corpus (one corpus, 2026-08-24).
    let candidateCardIds: [String]
    let ownerState: OwnerState
    let benefits: BenefitsCatalogue
    let service: CheckoutService
    let explainer: RecommendationExplainer
    let engine: RecommendationEngine
    let provider: any MerchantProviding

    var walletCards: [CardProduct] {
        if ownerState.ownedCardIds.isEmpty {
            return []
        }
        let owned = Set(ownerState.ownedCardIds)
        return catalogue.cards.filter { owned.contains($0.cardId) }
    }

    var walletCardIds: [String] {
        ownerState.ownedCardIds.isEmpty ? [] : ownerState.ownedCardIds
    }
}

/// Owns the dependency graph and its lifecycle.
///
/// Account operations live here rather than in a separate object because every one of them —
/// saving a wallet, applying a synced owner state, signing out — ends by rebuilding this graph.
/// Splitting them off would produce two objects that could never act independently.
@Observable
@MainActor
final class CopilotEnvironment {
    private(set) var graph: DependencyGraph?
    private(set) var isFirstRun = false
    /// Set when seed data cannot be read at all. Distinct from an operational error: the app
    /// has nothing to show, so this is a full-screen state, not an alert.
    private(set) var loadFailure: String?
    private(set) var ambientDiagnostics = SuppressionLog()
    /// The silences `ambientDiagnostics` cannot see: regions that lost their slot, and wakes that
    /// never reached the gate.
    private(set) var ambientCoverage = AmbientCoverageLog()
    private(set) var ambientEnabled = false
    private(set) var walletIsFirstRun = false
    let benefitsDocumentVault = BenefitsDocumentVault()

    private let modelContext: ModelContext
    private let sync: SyncCoordinator
    private let ambient: AmbientLocationService
    private var walletWriteTask: Task<Void, Never>?
    private var canonicalBenefits: BenefitsCatalogue?

    init(modelContext: ModelContext, sync: SyncCoordinator, ambient: AmbientLocationService) {
        self.modelContext = modelContext
        self.sync = sync
        self.ambient = ambient
    }

    /// Refreshing `session` is part of loading, not a step a caller can forget. The 846-line
    /// predecessor kept `refreshHome()` inside `loadDependencies()`, so a loaded graph always
    /// implied refreshed derived state; every path that lost the refresh — a signed-out cold
    /// launch, sign-out, account deletion — showed $0.00 and an empty Activity badge over a
    /// store full of purchases. `CopilotEnvironmentTests` pins both.
    ///
    /// Idempotent: repeated calls after a successful load are no-ops, matching the old
    /// `guard deps == nil else { return }`.
    func load(session: CopilotSession) {
        guard graph == nil else { return }
        do {
            let catalogue = try SeedLoader.loadCatalogue()
            let candidates = try SeedLoader.loadCandidateCatalogue().cardIds
            let localOwner = sync.ownerStateLocalStore.loadUserWallet()
            let owner = localOwner ?? OwnerStateBuilder.empty(catalogue: catalogue)
            let benefits = try SeedLoader.loadBenefitsCatalogue()

            canonicalBenefits = benefits
            isFirstRun = localOwner == nil
            walletIsFirstRun = localOwner == nil
            graph = makeGraph(catalogue: catalogue, candidates: candidates,
                              owner: owner, benefits: benefits)
            configureAmbient(catalogue: catalogue, owner: owner)
            session.refresh(using: graph!)
            loadFailure = nil
        } catch {
            loadFailure = "Seed data failed to load: \(error.localizedDescription)"
        }
    }

    /// Rebuilds the graph around a new owner state — after a sync, or after the owner edits
    /// their wallet. The catalogue, candidates and benefits are unchanged; only the owner-state
    /// derived objects (`service`, `engine`) are rebuilt.
    func rebuild(ownerState owner: OwnerState) {
        guard let existing = graph else { return }
        graph = makeGraph(catalogue: existing.catalogue, candidates: existing.candidateCardIds,
                          owner: owner, benefits: canonicalBenefits ?? existing.benefits)
        configureAmbient(catalogue: existing.catalogue, owner: owner)
        isFirstRun = false
    }

    /// Drops the graph and reloads from disk. Used after sign-out and account deletion, where
    /// the local owner-state store has changed underneath us.
    func reload(session: CopilotSession) {
        graph = nil
        canonicalBenefits = nil
        load(session: session)
    }

    /// Rebuilds only the benefit side of the graph after a personal document is imported or
    /// verified. This keeps the recommendation and wallet state intact while making the new
    /// provenance immediately visible in the library and protection lens.
    func refreshBenefits() {
        guard let existing = graph, let canonicalBenefits else { return }
        graph = makeGraph(catalogue: existing.catalogue, candidates: existing.candidateCardIds,
                          owner: existing.ownerState, benefits: canonicalBenefits)
        configureAmbient(catalogue: existing.catalogue, owner: existing.ownerState)
    }

    @discardableResult
    func addPersonalBenefitDocument(cardId: String, sourceURL: URL, kind: String,
                                    effectiveDate: String? = nil, jurisdiction: String? = nil) -> Bool {
        let added = benefitsDocumentVault.addDocument(cardId: cardId, sourceURL: sourceURL,
                                                      kind: kind, effectiveDate: effectiveDate,
                                                      jurisdiction: jurisdiction)
        guard added != nil else { return false }
        refreshBenefits()
        return true
    }

    func verifyPersonalBenefitDocument(id: UUID) {
        benefitsDocumentVault.confirmOwnerDocument(id: id)
        refreshBenefits()
    }

    func removePersonalBenefitDocument(id: UUID) {
        benefitsDocumentVault.removeDocument(id: id)
        refreshBenefits()
    }

    private func makeGraph(catalogue: Catalogue, candidates: [String], owner: OwnerState,
                           benefits: BenefitsCatalogue) -> DependencyGraph {
        DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: candidates,
            ownerState: owner,
            benefits: benefitsApplyingPersonalDocuments(to: benefits),
            service: CheckoutService(catalogue: catalogue, ownerState: owner, context: modelContext),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: LiveMerchantProvider())
    }

    private func benefitsApplyingPersonalDocuments(to benefits: BenefitsCatalogue) -> BenefitsCatalogue {
        var adjusted = benefits
        adjusted.cards = benefits.cards.map { card in
            let personal = benefitsDocumentVault.documents.filter { $0.cardId == card.cardId }
            guard !personal.isEmpty else { return card }

            var documents = card.documents
            documents.append(contentsOf: personal.map { record in
                CardDocument(
                    documentId: "personal-\(record.id.uuidString)",
                    kind: record.kind,
                    title: record.fileName,
                    url: benefitsDocumentVault.fileURL(for: record).absoluteString,
                    effectiveDate: record.effectiveDate,
                    jurisdiction: record.jurisdiction,
                    verificationStatus: record.status,
                    lastVerifiedAt: record.verifiedAt ?? record.addedAt,
                    notes: "Stored on this iPhone. Owner confirmation is required before this document verifies coverage.")
            })

            var certificate = card.certificate
            if let verified = personal.filter(\.ownerConfirmed).compactMap(\.verifiedAt).max() {
                certificate.verificationStatus = .certificateVerified
                certificate.lastVerifiedAt = verified
            }
            return CardBenefits(cardId: card.cardId, certificate: certificate,
                                benefits: card.benefits, documents: documents)
        }
        return adjusted
    }

    private func configureAmbient(catalogue: Catalogue, owner: OwnerState) {
        ambient.configure(modelContainer: modelContext.container, catalogue: catalogue, ownerState: owner)
        refreshAmbientDiagnostics()
    }

    /// Re-reads ambient's own diagnostics. `AmbientLocationService` is not `@Observable`, so a
    /// scene-active tick or an explainer's "enable" tap must pull a fresh copy rather than rely
    /// on SwiftUI noticing the change on its own.
    func refreshAmbientDiagnostics() {
        ambientDiagnostics = ambient.diagnostics
        ambientCoverage = ambient.coverage
        ambientEnabled = ambient.isEnabled
    }

    func arrivalPreferenceChanged() {
        ambient.refreshNow()
        refreshAmbientDiagnostics()
    }

    /// Completes the first-run gateway without forcing the owner into a separate wallet setup screen.
    /// The initial owner state is saved to the local store and derived session state is refreshed.
    func continuePrivately(session: CopilotSession) {
        guard let graph else { return }
        try? sync.ownerStateLocalStore.save(graph.ownerState)
        isFirstRun = false
        walletIsFirstRun = false
        session.refresh(using: graph)
    }
}

// MARK: - Account lifecycle
//
// Every operation here ends by rebuilding `graph` (Design Decision 5), which is why these live
// on `CopilotEnvironment` rather than on a separate object. `session` and `router` are taken as
// parameters rather than stored: this object outlives any one screen and must not hold a
// reference back into objects that can be recreated, which would leave it observing a stale one.
extension CopilotEnvironment {
    /// Binds the active device wallet to the signed-in account. A cached profile is restored when
    /// possible; a different, previously unseen account is seeded from its server wallet instead
    /// of inheriting the prior account's cards. A server miss opens a genuinely empty setup flow.
    func prepareAccount(forUserID userID: String?, session: CopilotSession, router: CheckoutRouter) async {
        sync.restoreSyncMetadata(forUserID: userID)
        sync.walletFeedback = []
        sync.walletInstallations = []
        sync.readySyncUserID = nil
        sync.accountSetupUserID = nil
        guard let userID else { return }

        load(session: session)
        guard let graph else { return }
        sync.isPreparingAccount = true
        defer { sync.isPreparingAccount = false }

        do {
            if sync.accountOwnerStateStore.activeUserID == userID,
               let cached = sync.accountOwnerStateStore.state(forUserID: userID) {
                try sync.accountOwnerStateStore.activate(cached, forUserID: userID)
                rebuild(ownerState: cached)
                session.refresh(using: self.graph!)
                walletIsFirstRun = false
                if router.path.last == .walletSetup { router.pop() }
                sync.readySyncUserID = userID
                return
            }

            if let cached = sync.accountOwnerStateStore.state(forUserID: userID) {
                try sync.accountOwnerStateStore.activate(cached, forUserID: userID)
                rebuild(ownerState: cached)
                session.refresh(using: self.graph!)
                walletIsFirstRun = false
                if router.path.last == .walletSetup { router.pop() }
                sync.readySyncUserID = userID
                return
            }

            // Migration and first account attachment: an existing unbound device wallet belongs to
            // the first account the owner signs into. A first-run bundled seed is never adopted.
            if sync.accountOwnerStateStore.activeUserID == nil, !walletIsFirstRun {
                try sync.accountOwnerStateStore.activate(graph.ownerState, forUserID: userID)
                try sync.ownerStateUploadQueue.enqueue(graph.ownerState, forUserID: userID)
                sync.cardRequestQueue.claimUnscopedRequests(forUserID: userID)
                sync.readySyncUserID = userID
                return
            }

            guard MoneyTalksConfiguration.isConfigured,
                  let baseURL = MoneyTalksConfiguration.apiBaseURL else {
                throw MoneyTalksAPIError.unavailableConfiguration
            }
            let shouldClaimUnscopedRequests = sync.accountOwnerStateStore.activeUserID == nil
            let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
            let remote: OwnerState?
            do {
                remote = try await OwnerStateSyncService(client: client).seedFromRemote()
            } catch {
                remote = nil
            }
            if let remote, !remote.ownedCardIds.isEmpty {
                try sync.accountOwnerStateStore.activate(remote, forUserID: userID)
                if shouldClaimUnscopedRequests {
                    sync.cardRequestQueue.claimUnscopedRequests(forUserID: userID)
                }
                rebuild(ownerState: remote)
                session.refresh(using: self.graph!)
                walletIsFirstRun = false
                if router.path.last == .walletSetup { router.pop() }
            } else {
                let empty = OwnerStateBuilder.empty(catalogue: graph.catalogue,
                                                    market: graph.ownerState.market.flatMap(Market.init(rawValue:)))
                try? sync.accountOwnerStateStore.activate(empty, forUserID: userID)
                rebuild(ownerState: empty)
                session.refresh(using: self.graph!)
                walletIsFirstRun = false
                if router.path.last == .walletSetup { router.pop() }
                router.showingAddCard = true
            }
            sync.readySyncUserID = userID
        } catch {
            sync.saveSyncFailure(error, forUserID: userID)
        }
    }

    /// Applies a wallet the owner just built. Failures here are alerts, not navigation — the
    /// owner stays on the setup screen (Design Decision 3) rather than losing their edits to a
    /// full-screen error.
    func saveWalletSetup(_ setup: WalletSetup, session: CopilotSession, router: CheckoutRouter,
                         popsOnSave: Bool = true) async {
        guard let graph else { return }
        let owner = walletIsFirstRun
            ? OwnerStateBuilder.firstRun(setup: setup, catalogue: graph.catalogue)
            : OwnerStateBuilder.apply(setup, to: graph.ownerState, catalogue: graph.catalogue)
        do {
            let signedInUserID = Clerk.shared.user?.id
            let outcome = try WalletSetupPersistence(
                accountStore: sync.accountOwnerStateStore,
                uploadQueue: sync.ownerStateUploadQueue,
                cardRequestQueue: sync.cardRequestQueue
            ).save(owner, signedInUserID: signedInUserID,
                   preparedSetupUserID: sync.accountSetupUserID)

            switch outcome {
            case .savedLocally:
                break
            case .savedLocallyAwaitingAccountBinding(let userID):
                sync.saveSyncIssue(
                    kind: .warning,
                    message: "Wallet saved on this iPhone. Account sync will retry when the connection is ready.",
                    forUserID: userID
                )
            case .savedAndQueued(let userID):
                if signedInUserID == userID { sync.readySyncUserID = userID }
                sync.accountSetupUserID = nil
            case .accountMismatch:
                session.report(FlowError(message:
                    "This wallet is linked to another account. Open Sync and Wallet Capture to choose the correct account before saving."))
                return
            }
        } catch {
            session.report(FlowError(error))
            return
        }
        rebuild(ownerState: owner)
        session.refresh(using: self.graph!)
        walletIsFirstRun = false
        if popsOnSave && router.path.last == .walletSetup { router.pop() }

        // Setup remains usable offline. The durable outbox retries on every sync until the server
        // has the exact wallet needed to evaluate Wallet Capture feedback.
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              let userID = Clerk.shared.user?.id, sync.readySyncUserID == userID,
              sync.accountOwnerStateStore.activeUserID == userID else { return }
        do {
            let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
            try await sync.flushQueuedOwnerState(forUserID: userID, using: client)
        } catch {
            sync.saveSyncFailure(error, forUserID: userID)
        }
    }

    /// Applies a wallet edit immediately to local state, then debounces the durable save and
    /// server upload. Local-first is deliberate: the device copy is the checkout source of truth
    /// while offline, and a person who toggles three things in four seconds should produce one
    /// upload, not three.
    func applyWalletEdit(_ setup: WalletSetup, session: CopilotSession, router: CheckoutRouter) {
        guard let graph else { return }
        let owner = OwnerStateBuilder.apply(setup, to: graph.ownerState, catalogue: graph.catalogue)
        rebuild(ownerState: owner)
        session.refresh(using: self.graph!)

        walletWriteTask?.cancel()
        walletWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await self.saveWalletSetup(setup, session: session, router: router, popsOnSave: false)
        }
    }

    func requestCard(_ request: PendingCardRequest) async -> Bool {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              let userID = Clerk.shared.user?.id, sync.readySyncUserID == userID,
              sync.accountOwnerStateStore.activeUserID == userID else {
            enqueueCardRequestForCurrentProfile(request)
            return false
        }
        do {
            let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
            try await client.createCardRequest(request)
            return true
        } catch {
            enqueueCardRequestForCurrentProfile(request)
            return false
        }
    }

    func enqueueCardRequestForCurrentProfile(_ request: PendingCardRequest) {
        if let userID = sync.accountOwnerStateStore.activeUserID {
            sync.cardRequestQueue.enqueue(request, forUserID: userID)
        } else {
            sync.cardRequestQueue.enqueue(request)
        }
    }

    /// Erasing the device history on its own — no account required, and nothing on the server is
    /// touched. Account deletion reuses this rather than repeating it.
    func eraseLocalHistory(session: CopilotSession) {
        try? LocalDataEraser(context: modelContext).eraseLocalHistory()
        ambient.forgetLocalHistory()
        session.forgetNearbyHistory()
        benefitsDocumentVault.clearAll()
        refreshBenefits()
        refreshAmbientDiagnostics()
        if let graph { session.refresh(using: graph) }
    }

    /// Order matters and is not cosmetic. The server call comes first and everything after it is
    /// local cleanup: if the deletion fails, the account and this iPhone are untouched. Once the
    /// server has confirmed, the local steps must not be able to fail the operation — the account
    /// is already gone.
    func deleteAccount(eraseLocalHistory shouldErase: Bool, session: CopilotSession,
                       router: CheckoutRouter) async throws {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        let deletedUserID = Clerk.shared.user?.id
        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        try await client.deleteAccount()

        // Geofences are refreshed from the store on the next significant location change, which
        // could be hours away. Arrival monitoring for merchants the owner just erased stops now.
        if shouldErase { eraseLocalHistory(session: session) }
        if let deletedUserID {
            sync.syncMetadataStore.remove(forUserID: deletedUserID)
            sync.ownerStateUploadQueue.remove(forUserID: deletedUserID)
            sync.cardRequestQueue.removeAll(forUserID: deletedUserID)
            sync.accountOwnerStateStore.removeProfile(forUserID: deletedUserID)
        }
        WalletCaptureCredentialStore().remove()
        WalletCaptureSettingsStore().setEnabled(false)
        WalletCaptureSettingsStore().clearConnection()
        let captureRoot = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let outbox = try? WalletOutboxStore(root: captureRoot) { try? await outbox.deleteAll() }
        try? await Clerk.shared.auth.signOut()
        resetSyncedState(session: session)
        router.popToRoot()
        router.resetToIdle()
    }

    func signOut(session: CopilotSession, router: CheckoutRouter) async {
        try? await Clerk.shared.auth.signOut()
        resetSyncedState(session: session)
        router.popToRoot()
        router.resetToIdle()
    }

    /// Clears account-only presentation state. The synced wallet remains in the offline owner-state
    /// store, while the per-account timestamp can be restored if this account signs in again.
    func resetSyncedState(session: CopilotSession) {
        sync.resetSyncedState()
        // Nearby results and their local counters are account-independent presentation state;
        // never carry a previous owner's merchant context into the next signed-in session.
        session.forgetNearbyHistory()
        reload(session: session)
    }

    func createInstallation(label: String) async throws -> WalletCaptureConnectionTestResult {
        try await sync.createInstallation(label: label)
    }
}
