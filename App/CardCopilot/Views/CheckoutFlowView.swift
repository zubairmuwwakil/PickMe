import SwiftUI
import SwiftData
import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import CardCopilotCapture
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
    @State private var recentPurchases: [StoredPrediction] = []
    @State private var metrics: ExperimentMetrics?
    @State private var sync = SyncCoordinator()
    @State private var ambient = AmbientLocationService()
    @State private var ambientDiagnostics = SuppressionLog()
    @State private var seedOwnerState: OwnerState?
    @State private var walletIsFirstRun = false
    @State private var selectedTab: AppTab = .copilot
    @State private var walletBannerCenter = WalletCaptureBannerCenter.shared

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
        case welcome
        case walletSetup
        case ambientSetup
        case failed(String)
    }

    struct Dependencies {
        let catalogue: Catalogue
        /// Ids into `catalogue`, not a second card corpus (one corpus, 2026-08-24).
        let candidateCardIds: [String]
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

    private var rootTitle: String {
        switch selectedTab {
        case .copilot: return "PickMe"
        case .activity: return "Activity"
        case .wallet: return "My Wallet"
        case .perks: return "Protection & Perks"
        case .you: return "Account & Settings"
        }
    }

    private var captureBoundAccountLabel: String? {
        guard let credential = WalletCaptureCredentialStore().load() else { return nil }
        guard let current = Clerk.shared.user else { return "Connected account (signed out)" }
        guard current.id == credential.boundUserID else { return "Different Inunity account — relink required" }
        return current.primaryEmailAddress?.emailAddress ?? String(current.id.prefix(12))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(isAtRoot ? rootTitle : "PickMe")
                .toolbar {
                    if isAtRoot {
                        ToolbarItem(placement: .topBarTrailing) {
                            SyncStatusToolbarButton(
                                isSyncing: sync.isSyncing || sync.isPreparingAccount,
                                lastSyncedAt: sync.lastSyncedAt,
                                syncIssue: sync.syncIssue,
                                action: { stage = .sync }
                            )
                        }
                    }
                }
        }
        .overlay(alignment: .top) {
            if let banner = walletBannerCenter.banner {
                WalletCaptureBannerView(banner: banner) { walletBannerCenter.dismiss() }
                    .padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity)).zIndex(100)
            }
        }
        .animation(.spring(duration: 0.35), value: walletBannerCenter.banner)
        .task {
            loadDependencies()
            _ = WalletCaptureNetworkMonitor.shared
            await sync.drainWalletCaptures()
            if WalletCaptureDeepLinkStore.consume() { stage = .sync }
        }
        .task(id: Clerk.shared.user?.id) {
            await prepareAccount(forUserID: Clerk.shared.user?.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ambientDiagnostics = ambient.diagnostics
                Task { await sync.drainWalletCaptures(); await autoSyncIfStale() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .walletCaptureConnectivityRestored)) { _ in
            Task { await sync.drainWalletCaptures() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWalletCaptureStatus)) { _ in stage = .sync }
    }

    private var isAtRoot: Bool {
        if case .idle = stage { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle:
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedTab {
                    case .copilot:
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
                                 deps: deps,
                                 onSelectPreIndexedMerchant: { match in
                                     stage = .amount(merchant: NearbyMerchant(id: "preindex:\(match.id)",
                                                                              name: match.name,
                                                                              poiCategoryRaw: match.category,
                                                                              latitude: 0,
                                                                              longitude: 0,
                                                                              distanceMeters: nil))
                                 },
                                 onInstantRepeat: { merchant in startInstantRepeat(merchant) },
                                 onLogPurchase: { merchant, amount in logInstantPurchase(merchant, amount: amount) },
                                 onOpenDetails: { merchant, amount in startInstantRepeatWithAmount(merchant, amount: amount) },
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
                    case .activity:
                        ActivityHubView(
                            finishCount: completionQueue.count,
                            reconcileCount: reconcileQueue.count,
                            metrics: metrics,
                            valueRecoveredCad: valueRecoveredCad,
                            pendingValueCad: pendingValueCad,
                            recentPurchases: recentPurchases,
                            cards: deps?.walletCards ?? [],
                            onFinish: { stage = .finish },
                            onReconcile: { stage = .reconcile },
                            onOpenDashboard: { stage = .dashboard },
                            onSelectPurchase: { prediction in
                                if prediction.purchase?.isComplete == false {
                                    stage = .finish
                                }
                            },
                            onUpdateCategory: { prediction, newCategory in
                                if let deps {
                                    try? deps.service.log.updateCategory(for: prediction, to: newCategory)
                                    refreshHome()
                                }
                            }
                        )
                    case .wallet:
                        WalletHubView(
                            deps: deps,
                            onCategoryPicker: { stage = .categoryPicker },
                            onWalletHealth: { stage = .walletHealth },
                            onValuationSandbox: { stage = .valuationSandbox },
                            onEditWallet: { stage = .walletSetup }
                        )
                    case .perks:
                        PerksHubView(
                            deps: deps,
                            onProtectionLens: { kind in stage = .protectionLens(BenefitContext(kind: kind)) },
                            onBenefitsReference: { stage = .benefitsReference }
                        )
                    case .you:
                        YouHubView(
                            isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                            accountEmail: Clerk.shared.user?.primaryEmailAddress?.emailAddress,
                            lastSyncedAt: sync.lastSyncedAt,
                            syncIssue: sync.syncIssue,
                            ambientEnabled: ambient.isEnabled,
                            ambientDiagnostics: ambientDiagnostics,
                            onOpenSync: { stage = .sync },
                            onOpenAmbient: { stage = .ambientSetup },
                            onEditWallet: { stage = .walletSetup },
                            onSignIn: { stage = .sync },
                            onSignOut: { Task { await signOut() } },
                            onEraseLocalHistory: { eraseLocalHistory() },
                            onDeleteAccount: { erase in try await deleteAccount(eraseLocalHistory: erase) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                FloatingGlassNavBar(
                    selectedTab: $selectedTab,
                    activityBadgeCount: completionQueue.count + reconcileQueue.count,
                    hasYouAlert: sync.syncIssue != nil || (!ambient.isEnabled)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
                                   LiveActivityManager.shared.endActivity()
                                   refreshHome()
                                   stage = .idle
                               })
        case .finish:
            FinishPurchaseView(queue: completionQueue,
                               cards: deps?.walletCards ?? [],
                               proposals: captureProposals,
                               onFinish: { prediction, entry in finish(prediction, entry: entry) },
                               onDone: { stage = .idle })
                // Captures are only pulled when the owner opens Sync, which most never will.
                // This queue is the one screen where a capture has something to offer, so it is
                // the right place to go looking. Failure is silent by design: the queue works
                // exactly as it did before, asking for both facts.
                .task { await syncCapsSilently() }
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
                WalletHealthView(deps: deps, recentPurchases: recentPurchases, onDone: { stage = .idle })
            }
        case .valuationSandbox:
            if let deps {
                ValuationSandboxView(deps: deps, onDone: { stage = .idle })
            }
        case .sync:
            SyncCenterView(isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                           lastSyncedAt: sync.lastSyncedAt,
                           feedback: sync.walletFeedback,
                           installations: sync.walletInstallations,
                           syncIssue: sync.syncIssue,
                           isSyncing: sync.isSyncing,
                           isPreparingAccount: sync.isPreparingAccount,
                           isAccountReady: sync.readySyncUserID == Clerk.shared.user?.id,
                           onSync: { Task { await syncFromUI() } },
                           onCreateInstallation: { label in try await createInstallation(label: label) },
                           onRevokeInstallation: { id in try await sync.revokeWalletInstallation(id: id) },
                           boundAccountLabel: captureBoundAccountLabel,
                           isCaptureBoundToCurrentAccount: WalletCaptureCredentialStore().load()?.boundUserID == Clerk.shared.user?.id,
                           onTestCaptureConnection: { await sync.testWalletCaptureConnection() },
                           onAssignUnassigned: { try await sync.assignUnassignedCaptures() },
                           onDeleteUnassigned: { try await sync.deleteUnassignedCaptures() },
                           onDisableCapture: { delete in try await sync.disableWalletCapture(deleteUnsent: delete) },
                           onSubmitDiagnostic: { report in try await sync.submitDiagnostic(report) },
                           onDeleteSubmittedDiagnostic: { id in try await sync.deleteSubmittedDiagnostic(id: id) },
                           onListSubmittedDiagnostics: { try await sync.listSubmittedDiagnostics() },
                           onDone: { stage = .idle })
        case .settings:
            SettingsView(isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                         accountEmail: Clerk.shared.user?.primaryEmailAddress?.emailAddress,
                         lastSyncedAt: sync.lastSyncedAt,
                         syncIssue: sync.syncIssue,
                         ambientEnabled: ambient.isEnabled,
                         onOpenSync: { stage = .sync },
                         onOpenAmbient: { stage = .ambientSetup },
                         onEditWallet: { stage = .walletSetup },
                         onSignIn: { stage = .sync },
                         onSignOut: { Task { await signOut() } },
                         onEraseLocalHistory: { eraseLocalHistory() },
                         onDeleteAccount: { erase in try await deleteAccount(eraseLocalHistory: erase) },
                         onDone: { stage = .idle })
        case .welcome:
            WelcomeGatewayView(
                isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                isPreparingAccount: sync.isPreparingAccount,
                syncIssueMessage: sync.syncIssue?.message,
                onRetryAccountRestore: {
                    Task { await prepareAccount(forUserID: Clerk.shared.user?.id) }
                },
                onContinuePrivately: {
                    stage = .walletSetup
                }
            )
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
            let candidates = try SeedLoader.loadCandidateCatalogue().cardIds
            let seedOwner = try SeedLoader.loadOwnerState()
            let localOwner = sync.ownerStateLocalStore.load()
            let owner = localOwner ?? seedOwner
            seedOwnerState = seedOwner
            walletIsFirstRun = localOwner == nil
            let benefits = try SeedLoader.loadBenefitsCatalogue()
            deps = makeDependencies(catalogue: catalogue, candidates: candidates, owner: owner, benefits: benefits)
            configureAmbient(catalogue: catalogue, owner: owner)
            refreshHome()
            if localOwner == nil { stage = .welcome }
        } catch {
            stage = .failed("Seed data failed to load: \(error.localizedDescription)")
        }
    }

    /// Binds the active device wallet to the signed-in account. A cached profile is restored when
    /// possible; a different, previously unseen account is seeded from its server wallet instead
    /// of inheriting the prior account's cards. A server miss opens a genuinely empty setup flow.
    private func prepareAccount(forUserID userID: String?) async {
        sync.restoreSyncMetadata(forUserID: userID)
        sync.walletFeedback = []
        sync.walletInstallations = []
        sync.readySyncUserID = nil
        sync.accountSetupUserID = nil
        guard let userID else { return }

        loadDependencies()
        guard let deps else { return }
        sync.isPreparingAccount = true
        defer { sync.isPreparingAccount = false }

        do {
            if sync.accountOwnerStateStore.activeUserID == userID,
               let cached = sync.accountOwnerStateStore.state(forUserID: userID) {
                try sync.accountOwnerStateStore.activate(cached, forUserID: userID)
                applyOwnerState(cached, using: deps)
                walletIsFirstRun = false
                if case .walletSetup = stage { stage = .idle }
                if case .welcome = stage { stage = .idle }
                sync.readySyncUserID = userID
                return
            }

            if let cached = sync.accountOwnerStateStore.state(forUserID: userID) {
                try sync.accountOwnerStateStore.activate(cached, forUserID: userID)
                applyOwnerState(cached, using: deps)
                walletIsFirstRun = false
                if case .walletSetup = stage { stage = .idle }
                if case .welcome = stage { stage = .idle }
                sync.readySyncUserID = userID
                return
            }

            // Migration and first account attachment: an existing unbound device wallet belongs to
            // the first account the owner signs into. A first-run bundled seed is never adopted.
            if sync.accountOwnerStateStore.activeUserID == nil, !walletIsFirstRun {
                try sync.accountOwnerStateStore.activate(deps.ownerState, forUserID: userID)
                try sync.ownerStateUploadQueue.enqueue(deps.ownerState, forUserID: userID)
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
            if let remote = try await OwnerStateSyncService(client: client).seedFromRemote(),
               !remote.ownedCardIds.isEmpty {
                try sync.accountOwnerStateStore.activate(remote, forUserID: userID)
                if shouldClaimUnscopedRequests {
                    sync.cardRequestQueue.claimUnscopedRequests(forUserID: userID)
                }
                applyOwnerState(remote, using: deps)
                walletIsFirstRun = false
                if case .walletSetup = stage { stage = .idle }
                if case .welcome = stage { stage = .idle }
            } else {
                let emptySetup = WalletSetup(ownedCardIds: [], defaultCardId: "",
                                             switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                                             valuationsCad: deps.ownerState.valuationsCad)
                let empty = OwnerStateBuilder.make(setup: emptySetup, catalogue: deps.catalogue)
                applyOwnerState(empty, using: deps)
                walletIsFirstRun = true
                sync.accountSetupUserID = userID
                stage = .walletSetup
            }
            sync.readySyncUserID = userID
        } catch {
            sync.saveSyncFailure(error, forUserID: userID)
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

    private func startInstantRepeatWithAmount(_ merchant: StoredMerchant, amount: Double) {
        let nearby = NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                    name: merchant.name,
                                    poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude,
                                    longitude: merchant.longitude,
                                    distanceMeters: nil)
        recommend(merchant: nearby, amount: amount)
    }

    private func logInstantPurchase(_ merchant: StoredMerchant, amount: Double) {
        guard let deps else { return }
        let nearby = NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                    name: merchant.name,
                                    poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude,
                                    longitude: merchant.longitude,
                                    distanceMeters: nil)
        do {
            let today = Date().formatted(.iso8601.year().month().day())
            let result = try deps.service.recommend(merchant: nearby,
                                                    amountCad: amount,
                                                    asOf: today)
            let winnerCardId: String = {
                switch result.outcome {
                case .single(let rec): return rec.winner.cardId
                case .fork(let branches): return branches.first?.recommendation.winner.cardId ?? ""
                }
            }()
            let allPredictions = try deps.service.log.allPredictions()
            if let stored = allPredictions.first(where: { $0.id == result.storedPredictionId }) {
                let purchase = try deps.service.log.recordPurchase(for: stored, cardUsedId: winnerCardId, cardSource: .atTill)
                try deps.service.log.recordAmount(amount, source: .atTill, on: purchase)
            }
            refreshHome()

            let cardName = deps.catalogue.cards.first { $0.cardId == winnerCardId }?.officialName ?? winnerCardId
            let meta = CategoryVisuals.meta(for: result.prediction.category)
            LiveActivityManager.shared.startRecommendationActivity(
                merchantName: merchant.name,
                cardName: cardName,
                cardId: winnerCardId,
                multiplierHeadline: String(format: "$%.2f logged", amount),
                advantageDescription: "1-Tap Checkout",
                categoryDisplayName: meta.displayName,
                categoryIcon: meta.icon,
                isFork: false
            )
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// What the Apple Wallet Shortcut already answered for the checkouts still in the finish
    /// queue. Recomputed from the two published facts rather than stored, so it can never
    /// disagree with the queue it annotates — a stale proposal would offer to fill a field that
    /// was filled a moment ago.
    private var captureProposals: [UUID: CaptureProposal] {
        Dictionary(CaptureMatcher.proposals(for: completionQueue, from: sync.walletFeedback)
                    .map { ($0.predictionId, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Supplying the till facts, without touching anything already recorded.
    ///
    /// Provenance comes from the entry rather than being assumed here. This screen is reached
    /// after the fact, so a typed answer is `.recalledLater` — but a figure read off an Apple
    /// Wallet transaction and accepted unedited is `.walletCapture`, and collapsing the two would
    /// throw away the only evidence of which rows were measured rather than remembered.
    private func finish(_ prediction: StoredPrediction, entry: FinishEntry) {
        guard let deps else { return }
        do {
            let purchase = try deps.service.log.recordPurchase(for: prediction,
                                                               cardUsedId: entry.cardUsedId,
                                                               cardSource: entry.cardSource)
            if let amount = entry.actualAmountCad {
                try deps.service.log.recordAmount(amount,
                                                  source: entry.amountSource ?? .recalledLater,
                                                  on: purchase)
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
            recentPurchases = snapshot.recentPurchases
            metrics = snapshot.metrics
            homeMerchants = sortedHomeMerchants(try deps.service.knownMerchants())
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func autoSyncIfStale() async {
        guard let deps else { return }
        if let result = await sync.autoSyncIfStale(ownerState: deps.ownerState, catalogue: deps.catalogue) {
            applyOwnerState(result.ownerState, using: deps)
        }
    }

    private func syncCapsSilently() async {
        guard let deps else { return }
        if let result = await sync.syncCapsSilently(ownerState: deps.ownerState, catalogue: deps.catalogue) {
            applyOwnerState(result.ownerState, using: deps)
        }
    }

    private func syncFromUI() async {
        guard let userID = Clerk.shared.user?.id else { return }
        if sync.readySyncUserID != userID {
            await prepareAccount(forUserID: userID)
        }
        await syncCapsSilently()
    }

    private func saveWalletSetup(_ setup: WalletSetup) async {
        guard let deps else { return }
        let owner = OwnerStateBuilder.make(setup: setup, catalogue: deps.catalogue)
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
                stage = .failed(
                    "This wallet is linked to another account. Open Sync and Wallet Capture to choose the correct account before saving."
                )
                return
            }
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }
        self.deps = makeDependencies(catalogue: deps.catalogue, candidates: deps.candidateCardIds,
                                     owner: owner, benefits: deps.benefits)
        configureAmbient(catalogue: deps.catalogue, owner: owner)
        walletIsFirstRun = false
        stage = .idle

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

    private func requestCard(_ request: PendingCardRequest) async -> Bool {
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

    private func enqueueCardRequestForCurrentProfile(_ request: PendingCardRequest) {
        if let userID = sync.accountOwnerStateStore.activeUserID {
            sync.cardRequestQueue.enqueue(request, forUserID: userID)
        } else {
            sync.cardRequestQueue.enqueue(request)
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
        let deletedUserID = Clerk.shared.user?.id
        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        try await client.deleteAccount()

        // Geofences are refreshed from the store on the next significant location change, which
        // could be hours away. Arrival monitoring for merchants the owner just erased stops now.
        if eraseLocalHistory { self.eraseLocalHistory() }
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
        resetSyncedState()
        stage = .idle
    }

    private func signOut() async {
        try? await Clerk.shared.auth.signOut()
        resetSyncedState()
        stage = .idle
    }

    /// Clears account-only presentation state. The synced wallet remains in the offline owner-state
    /// store, while the per-account timestamp can be restored if this account signs in again.
    private func resetSyncedState() {
        sync.resetSyncedState()
        deps = nil
        loadDependencies()
    }

    private func applyOwnerState(_ owner: OwnerState, using existing: Dependencies) {
        deps = makeDependencies(catalogue: existing.catalogue, candidates: existing.candidateCardIds,
                                owner: owner, benefits: existing.benefits)
        configureAmbient(catalogue: existing.catalogue, owner: owner)
        refreshHome()
    }

    private func createInstallation(label: String) async throws -> String {
        try await sync.createInstallation(label: label)
    }

    private func makeDependencies(catalogue: Catalogue, candidates: [String], owner: OwnerState,
                                  benefits: BenefitsCatalogue) -> Dependencies {
        Dependencies(catalogue: catalogue, candidateCardIds: candidates, ownerState: owner, benefits: benefits,
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
