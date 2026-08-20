import SwiftUI
import SwiftData
import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import ClerkKit

/// The core loop: find or search the merchant, capture the amount, show the answer.
struct CheckoutFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage: Stage = .idle
    @State private var deps: Dependencies?
    @State private var locationDenied = false
    @State private var cachedLocation: CachedLocation?
    @State private var homeMerchants: [StoredMerchant] = []
    @State private var valueRecoveredCad: Double = 0
    /// Complete purchases not yet checked against a statement. Shown beside the confirmed figure
    /// rather than added to it — see PredictionLog.ValueRecovered.
    @State private var pendingValueCad: Double = 0
    /// Purchases missing a card or a charge: one field each, no statement needed.
    @State private var completionQueue: [StoredPrediction] = []
    @State private var reconcileQueue: [StoredPrediction] = []
    @State private var metrics: ExperimentMetrics?
    @State private var lastSyncedAt: Date?
    @State private var walletFeedback: [WalletFeedback] = []
    @State private var walletInstallations: [WalletInstallation] = []
    @State private var isSyncing = false
    @State private var ambient = AmbientLocationService()
    @State private var ambientDiagnostics = SuppressionLog()
    @State private var seedOwnerState: OwnerState?
    @State private var walletIsFirstRun = false
    private let ownerStateLocalStore = OwnerStateLocalStore()
    private let cardRequestQueue = CardRequestQueue()

    enum Stage {
        case idle
        case locating
        case confirming(merchants: [NearbyMerchant])
        case amount(merchant: NearbyMerchant)
        case recommendation(CheckoutResult)
        case finish
        case reconcile
        case dashboard
        case protectionLens(BenefitContext)
        case benefitsReference
        case categoryPicker
        case walletHealth
        case valuationSandbox
        case sync
        case settings
        case walletSetup
        case ambientSetup
        case failed(String)
    }

    struct Dependencies {
        let catalogue: Catalogue
        let candidateCatalogue: Catalogue
        let ownerState: OwnerState
        let benefits: BenefitsCatalogue
        let service: CheckoutService
        let explainer: RecommendationExplainer
        let engine: RecommendationEngine
        let provider: LiveMerchantProvider

        var walletCards: [CardProduct] {
            if ownerState.ownedCardIds.isEmpty {
                return catalogue.cards
            }
            let owned = Set(ownerState.ownedCardIds)
            return catalogue.cards.filter { owned.contains($0.cardId) }
        }

        var walletCardIds: [String] {
            ownerState.ownedCardIds.isEmpty ? catalogue.cards.map(\.cardId) : ownerState.ownedCardIds
        }
    }

    struct CachedLocation {
        let latitude: Double
        let longitude: Double
        let capturedAt: Date

        var isRecent: Bool {
            Date().timeIntervalSince(capturedAt) < 15 * 60
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("PickMe")
                .toolbar {
                    // Only the root screen owns these. Every other stage supplies its own Done
                    // button, and leaving the root buttons visible offered a reviewer a gear that
                    // led back to the screen they were already on.
                    if isAtRoot {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { stage = .sync } label: {
                                Image(systemName: lastSyncedAt == nil ? "icloud" : "checkmark.icloud")
                            }
                            .accessibilityLabel("Sync and Wallet Capture")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { stage = .settings } label: { Image(systemName: "gearshape") }
                                .accessibilityLabel("Settings")
                        }
                    }
                }
        }
        .task { loadDependencies() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ambientDiagnostics = ambient.diagnostics }
        }
    }

    private var isAtRoot: Bool {
        if case .idle = stage { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle:
            HomeView(valueRecoveredCad: valueRecoveredCad,
                     pendingValueCad: pendingValueCad,
                     merchants: homeMerchants,
                     isSortedByRecentLocation: cachedLocation?.isRecent == true,
                     locationDenied: locationDenied,
                     finishCount: completionQueue.count,
                     reconcileCount: reconcileQueue.count,
                     confirmedCount: metrics?.confirmedCount ?? 0,
                     ambientDiagnostics: ambientDiagnostics,
                     ambientEnabled: ambient.isEnabled,
                     onInstantRepeat: { merchant in startInstantRepeat(merchant) },
                     onFindNearby: { Task { await findNearby() } },
                     onSearch: { text in Task { await search(text) } },
                     onFinish: { stage = .finish },
                     onReconcile: { stage = .reconcile },
                     onDashboard: { stage = .dashboard },
                     onProtectionLens: { stage = .protectionLens(BenefitContext(kind: .flight)) },
                     onBenefits: { stage = .benefitsReference },
                     onCategoryPicker: { stage = .categoryPicker },
                     onWalletHealth: { stage = .walletHealth },
                     onValuationSandbox: { stage = .valuationSandbox },
                     onConfigureAmbient: { stage = .ambientSetup })
        case .locating:
            ProgressView("Finding nearby merchants…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirming(let merchants):
            MerchantConfirmView(merchants: merchants,
                                onConfirm: { stage = .amount(merchant: $0) },
                                onSearch: { text in Task { await search(text) } },
                                onCancel: { stage = .idle })
        case .amount(let merchant):
            AmountCaptureView(merchantName: merchant.name,
                              onAmount: { amount in recommend(merchant: merchant, amount: amount) },
                              onCancel: { stage = .idle })
        case .recommendation(let result):
            RecommendationView(result: result,
                               deps: deps,
                               onCompare: { kind in stage = .protectionLens(BenefitContext(kind: kind)) },
                               onDone: {
                                   refreshHome()
                                   stage = .idle
                               })
        case .finish:
            FinishPurchaseView(queue: completionQueue,
                               cards: deps?.walletCards ?? [],
                               onFinish: { prediction, entry in finish(prediction, entry: entry) },
                               onDone: { stage = .idle })
        case .reconcile:
            ReconcileView(queue: reconcileQueue,
                          cards: deps?.walletCards ?? [],
                          categories: deps.map { observableCategories(in: $0.catalogue) } ?? [],
                          onConfirm: { prediction, entry in confirm(prediction, entry: entry) },
                          onDone: { stage = .idle })
        case .dashboard:
            DashboardView(metrics: metrics ?? .empty,
                          valueRecoveredCad: valueRecoveredCad,
                          pendingValueCad: pendingValueCad,
                          onDone: { stage = .idle })
        case .protectionLens(let context):
            if let deps {
                ProtectionLensView(deps: deps,
                                   initialContext: context,
                                   onDone: { stage = .idle })
            }
        case .benefitsReference:
            if let deps {
                BenefitsReferenceView(deps: deps, onDone: { stage = .idle })
            }
        case .categoryPicker:
            if let deps {
                CategoryPickerView(deps: deps, onDone: { stage = .idle })
            }
        case .walletHealth:
            if let deps {
                WalletHealthView(deps: deps, onDone: { stage = .idle })
            }
        case .valuationSandbox:
            if let deps {
                ValuationSandboxView(deps: deps, onDone: { stage = .idle })
            }
        case .sync:
            SyncCenterView(isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                           lastSyncedAt: lastSyncedAt,
                           feedback: walletFeedback,
                           installations: walletInstallations,
                           isSyncing: isSyncing,
                           onSync: { Task { await syncCapsSilently() } },
                           onCreateInstallation: { label in try await createInstallation(label: label) },
                           onDone: { stage = .idle })
        case .settings:
            SettingsView(isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                         accountEmail: Clerk.shared.user?.primaryEmailAddress?.emailAddress,
                         lastSyncedAt: lastSyncedAt,
                         ambientEnabled: ambient.isEnabled,
                         onOpenSync: { stage = .sync },
                         onOpenAmbient: { stage = .ambientSetup },
                         onEditWallet: { stage = .walletSetup },
                         onSignIn: { stage = .sync },
                         onSignOut: { Task { await signOut() } },
                         onEraseLocalHistory: { eraseLocalHistory() },
                         onDeleteAccount: { erase in try await deleteAccount(eraseLocalHistory: erase) },
                         onDone: { stage = .idle })
        case .walletSetup:
            if let deps, let seedOwnerState {
                WalletSetupView(catalogue: deps.catalogue, seed: seedOwnerState,
                                existing: walletIsFirstRun ? nil : deps.ownerState,
                                isFirstRun: walletIsFirstRun,
                                onSave: { setup in await saveWalletSetup(setup) },
                                onRequestCard: { request in await requestCard(request) },
                                onDone: { stage = .idle })
            }
        case .ambientSetup:
            AmbientLocationExplainerView(
                isEnabled: ambient.isEnabled,
                diagnostics: ambientDiagnostics,
                onEnable: {
                    ambient.requestAlwaysAuthorization()
                    ambientDiagnostics = ambient.diagnostics
                    stage = .idle
                },
                onDone: { stage = .idle }
            )
        case .failed(let message):
            ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
            Button("Start over") { stage = .idle }
        }
    }

    private func loadDependencies() {
        guard deps == nil else { return }
        do {
            let catalogue = try SeedLoader.loadCatalogue()
            let candidates = try SeedLoader.loadCandidateCatalogue()
            let seedOwner = try SeedLoader.loadOwnerState()
            let localOwner = ownerStateLocalStore.load()
            let owner = localOwner ?? seedOwner
            seedOwnerState = seedOwner
            walletIsFirstRun = localOwner == nil
            let benefits = try SeedLoader.loadBenefitsCatalogue()
            deps = makeDependencies(catalogue: catalogue, candidates: candidates, owner: owner, benefits: benefits)
            configureAmbient(catalogue: catalogue, owner: owner)
            refreshHome()
            if localOwner == nil { stage = .walletSetup }
        } catch {
            stage = .failed("Seed data failed to load: \(error.localizedDescription)")
        }
    }

    private func findNearby() async {
        guard let deps else { return }
        stage = .locating
        do {
            let location = try await LocationProvider().requestLocation()
            cachedLocation = CachedLocation(latitude: location.latitude,
                                            longitude: location.longitude,
                                            capturedAt: Date())
            refreshHome()
            let merchants = try await deps.provider.nearby(latitude: location.latitude,
                                                           longitude: location.longitude)
            stage = merchants.isEmpty
                ? .failed("No merchants found nearby — try manual search.")
                : .confirming(merchants: merchants)
        } catch is LocationUnavailable {
            // Permission declined: Apple requires the manual path to stand on its own.
            locationDenied = true
            stage = .idle
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func search(_ text: String) async {
        guard let deps, !text.isEmpty else { return }
        stage = .locating
        do {
            let merchants = try await deps.provider.search(text: text)
            stage = merchants.isEmpty
                ? .failed("Nothing found for “\(text)”.")
                : .confirming(merchants: merchants)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func recommend(merchant: NearbyMerchant, amount: Double?) {
        guard let deps else { return }
        do {
            let today = Date().formatted(.iso8601.year().month().day())
            let result = try deps.service.recommend(merchant: merchant,
                                                    amountCad: amount,
                                                    asOf: today)
            stage = .recommendation(result)

            let (winnerCardId, headline, advantageCad, isFork): (String, String, Double?, Bool) = {
                switch result.outcome {
                case .single(let rec):
                    let returnText = String(format: "$%.2f back", rec.winner.netValueCad)
                    return (rec.winner.cardId, returnText, rec.advantageOverDefaultCad, false)
                case .fork(let branches):
                    if let first = branches.first {
                        let returnText = String(format: "$%.2f back", first.recommendation.winner.netValueCad)
                        return (first.recommendation.winner.cardId, returnText, first.recommendation.advantageOverDefaultCad, true)
                    }
                    return ("", "", nil, true)
                }
            }()
            let cardName = deps.catalogue.cards.first { $0.cardId == winnerCardId }?.officialName ?? winnerCardId
            let meta = CategoryVisuals.meta(for: result.prediction.category)
            let advantageText = advantageCad.map { String(format: "+$%.2f", $0) } ?? ""
            LiveActivityManager.shared.startRecommendationActivity(
                merchantName: merchant.name,
                cardName: cardName,
                cardId: winnerCardId,
                multiplierHeadline: headline,
                advantageDescription: advantageText,
                categoryDisplayName: meta.displayName,
                categoryIcon: meta.icon,
                isFork: isFork
            )
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func startInstantRepeat(_ merchant: StoredMerchant) {
        // This is the point of instant repeats: local row -> amount capture, with no
        // location request and no MapKit lookup.
        stage = .amount(merchant: NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                                 name: merchant.name,
                                                 poiCategoryRaw: merchant.poiCategoryRaw,
                                                 latitude: merchant.latitude,
                                                 longitude: merchant.longitude,
                                                 distanceMeters: nil))
    }

    /// Supplying the till facts, without touching anything already recorded.
    ///
    /// `.recalledLater` throughout: this screen is reached from the app, after the fact. The
    /// lock-screen path records the same fields as `.atTill`, and the difference between the two
    /// is the whole reason provenance is stored per field rather than per record.
    private func finish(_ prediction: StoredPrediction, entry: FinishEntry) {
        guard let deps else { return }
        do {
            let purchase = try deps.service.log.recordPurchase(for: prediction,
                                                               cardUsedId: entry.cardUsedId,
                                                               cardSource: entry.cardUsedId == nil ? nil : .recalledLater)
            if let amount = entry.actualAmountCad {
                try deps.service.log.recordAmount(amount, source: .recalledLater, on: purchase)
            }
            refreshHome()
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Recording what happened. The prediction is never touched — the store offers no way to
    /// touch it — so this reads as "record what happened", not "fix the guess".
    ///
    /// Three writes rather than one, because reconcile is now filling in two different records:
    /// the till facts the owner is recalling (card, charge) and the statement facts they are
    /// reading (category, reward units). Provenance is `.recalledLater` for the first pair and
    /// says so, which is what keeps a week-old recollection from being counted as an observation.
    private func confirm(_ prediction: StoredPrediction, entry: ReconcileEntry) {
        guard let deps else { return }
        do {
            let purchase = try deps.service.log.recordPurchase(for: prediction,
                                                               cardUsedId: entry.cardUsed,
                                                               cardSource: .recalledLater)
            if let amount = entry.actualAmountCad {
                try deps.service.log.recordAmount(amount, source: .recalledLater, on: purchase)
            }
            try deps.service.log.confirm(purchase,
                                         observedCategory: entry.observedCategory,
                                         observedRewardUnits: entry.observedRewardUnits,
                                         missClass: entry.missClass,
                                         note: entry.note)
            refreshHome()
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func refreshHome() {
        guard let deps else { return }
        do {
            // One fetch, four answers. Calling the individual accessors here ran three unfiltered
            // fetches per screen refresh, each walking the same rows again.
            let snapshot = try deps.service.log.snapshot()
            valueRecoveredCad = snapshot.valueRecovered.confirmedCad
            pendingValueCad = snapshot.valueRecovered.pendingCad
            completionQueue = snapshot.awaitingCompletion
            reconcileQueue = snapshot.awaitingConfirmation
            metrics = snapshot.metrics
            homeMerchants = sortedHomeMerchants(try deps.service.knownMerchants())
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func syncCapsSilently() async {
        guard MoneyTalksConfiguration.isConfigured, !isSyncing, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              Clerk.shared.user != nil, let deps else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
            let result = try await OwnerStateSyncService(client: client).sync(ownerState: deps.ownerState, catalogue: deps.catalogue)
            self.deps = makeDependencies(catalogue: deps.catalogue, candidates: deps.candidateCatalogue,
                                         owner: result.ownerState, benefits: deps.benefits)
            try? ownerStateLocalStore.save(result.ownerState)
            configureAmbient(catalogue: deps.catalogue, owner: result.ownerState)
            walletFeedback = result.feedback
            walletInstallations = result.installations
            lastSyncedAt = result.lastSyncedAt
            try await flushQueuedCardRequests(using: client)
        } catch {
            // A1: existing local state is usable; connectivity must never interrupt checkout.
        }
    }

    private func saveWalletSetup(_ setup: WalletSetup) async {
        guard let deps else { return }
        let owner = OwnerStateBuilder.make(setup: setup, catalogue: deps.catalogue)
        do {
            try ownerStateLocalStore.save(owner)
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }
        self.deps = makeDependencies(catalogue: deps.catalogue, candidates: deps.candidateCatalogue,
                                     owner: owner, benefits: deps.benefits)
        configureAmbient(catalogue: deps.catalogue, owner: owner)
        walletIsFirstRun = false
        stage = .idle

        // Setup remains usable offline. The server copy is retried by re-saving from Settings,
        // while Wallet Capture sees the exact per-user state as soon as this write succeeds.
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              Clerk.shared.user != nil else { return }
        do {
            let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
            try await client.updateOwnerState(owner)
        } catch { }
    }

    private func requestCard(_ request: PendingCardRequest) async -> Bool {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL,
              Clerk.shared.user != nil else {
            cardRequestQueue.enqueue(request)
            return false
        }
        do {
            let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
            try await client.createCardRequest(request)
            return true
        } catch {
            cardRequestQueue.enqueue(request)
            return false
        }
    }

    private func flushQueuedCardRequests(using client: MoneyTalksAPIClient) async throws {
        for request in cardRequestQueue.pending() {
            try await client.createCardRequest(request)
            cardRequestQueue.remove(request)
        }
    }

    /// Erasing the device history on its own — no account required, and nothing on the server is
    /// touched. Account deletion reuses this rather than repeating it.
    private func eraseLocalHistory() {
        try? LocalDataEraser(context: modelContext).eraseLocalHistory()
        ambient.forgetLocalHistory()
        ambientDiagnostics = ambient.diagnostics
        refreshHome()
    }

    /// Order matters and is not cosmetic. The server call comes first and everything after it is
    /// local cleanup: if the deletion fails, the account and this iPhone are untouched and the
    /// sheet says so. Once the server has confirmed, the local steps must not be able to fail the
    /// operation — the account is already gone.
    private func deleteAccount(eraseLocalHistory: Bool) async throws {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        try await client.deleteAccount()

        // Geofences are refreshed from the store on the next significant location change, which
        // could be hours away. Arrival monitoring for merchants the owner just erased stops now.
        if eraseLocalHistory { self.eraseLocalHistory() }
        try? await Clerk.shared.auth.signOut()
        resetSyncedState()
        stage = .idle
    }

    private func signOut() async {
        try? await Clerk.shared.auth.signOut()
        resetSyncedState()
        stage = .idle
    }

    /// Drops everything the server contributed: cap progress merged into OwnerState, the capture
    /// feedback list, and the sync timestamp. Reloading from the bundled seed is what makes this
    /// exact rather than approximate — there is no partially-synced state left to reason about.
    private func resetSyncedState() {
        lastSyncedAt = nil
        walletFeedback = []
        walletInstallations = []
        deps = nil
        loadDependencies()
    }

    private func createInstallation(label: String) async throws -> String {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        let installation = try await client.createWalletInstallation(label: label)
        guard let token = installation.token else { throw MoneyTalksAPIError.unexpectedResponse(-1) }
        walletInstallations.insert(installation, at: 0)
        return token
    }

    private func makeDependencies(catalogue: Catalogue, candidates: Catalogue, owner: OwnerState,
                                  benefits: BenefitsCatalogue) -> Dependencies {
        Dependencies(catalogue: catalogue, candidateCatalogue: candidates, ownerState: owner, benefits: benefits,
                     service: CheckoutService(catalogue: catalogue, ownerState: owner, context: modelContext),
                     explainer: RecommendationExplainer(catalogue: catalogue),
                     engine: RecommendationEngine(catalogue: catalogue, ownerState: owner), provider: LiveMerchantProvider())
    }

    private func configureAmbient(catalogue: Catalogue, owner: OwnerState) {
        ambient.configure(modelContainer: modelContext.container, catalogue: catalogue, ownerState: owner)
        ambientDiagnostics = ambient.diagnostics
    }


    private func sortedHomeMerchants(_ merchants: [StoredMerchant]) -> [StoredMerchant] {
        guard let cachedLocation, cachedLocation.isRecent else {
            return merchants.sorted { $0.lastSeenAt > $1.lastSeenAt }
        }
        let origin = CLLocation(latitude: cachedLocation.latitude, longitude: cachedLocation.longitude)
        return merchants.sorted { lhs, rhs in
            let lhsDistance = origin.distance(from: CLLocation(latitude: lhs.latitude,
                                                               longitude: lhs.longitude))
            let rhsDistance = origin.distance(from: CLLocation(latitude: rhs.latitude,
                                                               longitude: rhs.longitude))
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.lastSeenAt > rhs.lastSeenAt
        }
    }
}
