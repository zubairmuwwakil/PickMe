import SwiftUI
import SwiftData
import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import CardCopilotCapture
import ClerkKit

/// The core loop: find or search the merchant, capture the amount, show the answer.
///
/// A navigation root, not the flow itself. Loading, session state, and account operations live
/// on `CopilotEnvironment`/`CopilotSession`/`CheckoutRouter` (injected via `@Environment`) so
/// they can be exercised without a simulator. This view's only job is wiring: which screen the
/// router says to show, and translating a handful of local UI actions into router pushes and
/// session operations.
struct CheckoutFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncCoordinator.self) private var sync
    /// Not `@Environment`: `AmbientLocationService` is an `NSObject`/`CLLocationManagerDelegate`
    /// conformer, not `@Observable`, so it is held directly here exactly as it was before this
    /// view existed as a navigation root.
    @State private var ambient = AmbientLocationService.shared
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @State private var environment: CopilotEnvironment?
    @State private var walletBannerCenter = WalletCaptureBannerCenter.shared
    @State private var attemptedWalletEnrichmentIDs: Set<String> = []
    @State private var isCompletingPrivateOnboarding = false

    private var rootTitle: String {
        switch router.selectedTab {
        case .copilot: return ""
        case .activity: return "Activity"
        case .wallet: return "My Wallet"
        case .perks: return "Protection & Perks"
        case .you: return "Account & Settings"
        }
    }

    private var isAtRoot: Bool {
        if case .idle = router.step { return true }
        return false
    }

    private var signedInUserID: String? { ClerkSession.currentUserID }

    private var captureBoundAccountLabel: String? {
        guard let credential = WalletCaptureCredentialStore().load() else { return nil }
        guard let current = ClerkSession.currentUser else {
            return "Connected account (signed out)"
        }
        guard current.id == credential.boundUserID else { return "Different In Unity account — relink required" }
        return current.primaryEmailAddress?.emailAddress ?? String(current.id.prefix(12))
    }

    var body: some View {
        Group {
            if let environment {
                if let loadFailure = environment.loadFailure {
                    ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle",
                                           description: Text(loadFailure))
                } else if environment.graph == nil {
                    ProgressView()
                } else {
                    loadedNavigationStack(environment: environment)
                        .environment(environment)
                }
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .top) {
            if let banner = walletBannerCenter.banner {
                WalletCaptureBannerView(banner: banner) { walletBannerCenter.dismiss() }
                    .padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity)).zIndex(100)
            }
        }
        .animation(.spring(duration: 0.35), value: walletBannerCenter.banner)
        .alert(item: Binding(get: { session.lastError }, set: { session.lastError = $0 })) { error in
            Alert(title: Text("Something went wrong"), message: Text(error.message))
        }
        .task {
            let environment = ensureEnvironment()
            environment.load(session: session)
            _ = WalletCaptureNetworkMonitor.shared
            await sync.drainWalletCaptures()
            await ingestAutomaticCaptures()
            if WalletCaptureDeepLinkStore.consume() { router.show(.sync) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let environment = ensureEnvironment()
            environment.load(session: session)
            guard let graph = environment.graph else { return }
            await session.prefetchNearby(using: graph)
        }
        .task(id: signedInUserID) {
            await ensureEnvironment().prepareAccount(forUserID: signedInUserID,
                                                     session: session, router: router)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                environment?.refreshAmbientDiagnostics()
                Task {
                    await sync.drainWalletCaptures()
                    // Foregrounding commonly means the owner just returned from Wallet. A normal
                    // 15-minute stale gate would hide that brand-new capture, so pull feedback now.
                    await syncCapsSilently()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .walletCaptureConnectivityRestored)) { _ in
            Task {
                await sync.drainWalletCaptures()
                // The upload and the feedback read are two sides of one handoff. Refreshing only
                // the outbox left the accepted purchase invisible until the next scheduled sync.
                await syncCapsSilently()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWalletCaptureStatus)) { _ in
            router.show(.sync)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCreditReminders)) { _ in
            router.selectTab(.perks)
        }
        .onOpenURL { url in
            guard let link = AmbientDeepLink(url: url) else { return }
            switch link {
            case .identifyMerchant:
                // The presence Live Activity asked "which shop is this?". `findNearby` is that
                // question: it lists the places around the owner and routes to `.confirming`,
                // where picking one both answers it and produces a recommendation.
                router.selectTab(.copilot)
                router.popToRoot()
                findNearby()
            }
        }
    }

    @ViewBuilder
    private func loadedNavigationStack(environment: CopilotEnvironment) -> some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            rootContent(environment: environment)
                .navigationTitle(isAtRoot ? rootTitle : "PickMe")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Destination.self) { destination in
                    destinationView(destination, environment: environment)
                }
                .toolbar {
                    if isAtRoot, !environment.isFirstRun, router.selectedTab != .copilot {
                        ToolbarItem(placement: .topBarTrailing) {
                            SyncStatusToolbarButton(
                                isSyncing: sync.isSyncing || sync.isPreparingAccount,
                                lastSyncedAt: sync.lastSyncedAt,
                                syncIssue: sync.syncIssue,
                                action: { router.show(.sync) }
                            )
                        }
                    }
                }
        }
        .fullScreenCover(isPresented: $router.showingAddCard, onDismiss: {
            isCompletingPrivateOnboarding = false
        }) {
            addCardModal(environment: environment)
        }
    }

    @ViewBuilder
    private func addCardModal(environment: CopilotEnvironment) -> some View {
        if let graph = environment.graph {
            AddCardSheet(
                catalogue: graph.catalogue,
                ownedCardIds: graph.ownerState.ownedCardIds,
                residency: graph.ownerState.market.flatMap(Market.init(rawValue:)) ?? .ca,
                onAdd: { cardId in
                    var setup = OwnerStateBuilder.setup(from: graph.ownerState)
                    guard !setup.ownedCardIds.contains(cardId) else { return }
                    setup.ownedCardIds.append(cardId)
                    setup.deletedCardIds?.removeAll { $0 == cardId }
                    if setup.defaultCardId.isEmpty {
                        setup.defaultCardId = cardId
                    }
                    environment.applyWalletEdit(setup, session: session, router: router)
                },
                onRequestCard: { request in
                    await environment.requestCard(request)
                },
                onDismiss: {
                    router.showingAddCard = false
                }
            )
            // Keep the welcome gateway underneath the cover while it animates in. Clearing
            // first-run state from the button action exposes Home during that transition.
            .onAppear {
                if environment.isFirstRun {
                    environment.continuePrivately(session: session)
                }
            }
        }
    }

    /// Lazily builds the dependency graph owner. Deferred to `.task` rather than `init` because
    /// it needs `\.modelContext`, which is only available once this view is in the hierarchy.
    /// Both `.task` handlers below call this rather than assuming the other one already has —
    /// `.task(id:)` can fire before the plain `.task` finishes, exactly as `prepareAccount` used
    /// to call `loadDependencies()` itself rather than trust it had already run.
    @discardableResult
    private func ensureEnvironment() -> CopilotEnvironment {
        if let environment { return environment }
        let created = CopilotEnvironment(modelContext: modelContext, sync: sync, ambient: ambient)
        environment = created
        return created
    }

    /// The first-run gate replaces the tab root *inside* the stack, never the stack itself
    /// (Design Decision 4). Rendered as a sibling of the `NavigationStack`, nothing observed
    /// `router.path`, so "Continue privately" pushed `.walletSetup` onto a path no stack was
    /// rendering: the gate stayed on screen and a fresh install could not reach setup at all
    /// without signing in.
    @ViewBuilder
    private func rootContent(environment: CopilotEnvironment) -> some View {
        if environment.isFirstRun || isCompletingPrivateOnboarding {
            WelcomeGatewayView(
                isSignedIn: ClerkSession.isSignedIn,
                isPreparingAccount: sync.isPreparingAccount,
                syncIssueMessage: sync.syncIssue?.message,
                onRetryAccountRestore: {
                    Task { await environment.prepareAccount(forUserID: signedInUserID,
                                                            session: session, router: router) }
                },
                onContinuePrivately: {
                    isCompletingPrivateOnboarding = true
                    router.showingAddCard = true
                }
            )
        } else {
            checkoutStepContent(environment: environment)
        }
    }

    @ViewBuilder
    private func checkoutStepContent(environment: CopilotEnvironment) -> some View {
        switch router.step {
        case .idle:
            idleTabContent(environment: environment)
        case .locating:
            ProgressView("Finding nearby merchants…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirming(let merchants):
            MerchantConfirmView(merchants: merchants,
                                onConfirm: { merchant in
                                    if let graph = environment.graph {
                                        router.step = session.recommend(merchant: merchant, amount: nil,
                                                                        using: graph)
                                    }
                                },
                                onSearch: { text in Task { await search(text) } },
                                onCancel: { router.resetToIdle() })
        case .recommendation(let result):
            RecommendationView(result: result,
                               onCompare: { kind in router.push(.protectionLens(BenefitContext(kind: kind))) })
        case .failed(let message):
            ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
            Button("Start over") { router.resetToIdle() }
        }
    }

    @ViewBuilder
    private func idleTabContent(environment: CopilotEnvironment) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                switch router.selectedTab {
                case .copilot:
                    HomeView()
                case .activity:
                    ActivityHubView()
                case .wallet:
                    WalletHubView()
                case .perks:
                    PerksHubView()
                case .you:
                    YouHubView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingGlassNavBar(
                selectedTab: Binding(get: { router.selectedTab }, set: { router.selectTab($0) }),
                activityBadgeCount: session.completionQueue.count + session.reconcileQueue.count,
                hasYouAlert: sync.syncIssue != nil || (!ambient.isEnabled)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: Destination, environment: CopilotEnvironment) -> some View {
        switch destination {
        case .finish:
            FinishPurchaseView(queue: session.completionQueue,
                               cards: environment.graph?.walletCards ?? [],
                               proposals: session.captureProposals(sync: sync),
                               onFinish: { prediction, entry in
                                   if let graph = environment.graph {
                                       session.finish(prediction, entry: entry, using: graph)
                                   }
                               },
                               onDone: { router.pop() })
                // Captures are only pulled when the owner opens Sync, which most never will.
                // This queue is the one screen where a capture has something to offer, so it is
                // the right place to go looking. Failure is silent by design: the queue works
                // exactly as it did before, asking for both facts.
                .task { await syncCapsSilently() }
        case .reconcile:
            ReconcileView(queue: session.reconcileQueue,
                          cards: environment.graph?.walletCards ?? [],
                          categories: environment.graph.map { observableCategories(in: $0.catalogue) } ?? [],
                          onConfirm: { prediction, entry in
                              if let graph = environment.graph {
                                  session.confirm(prediction, entry: entry, using: graph)
                              }
                          },
                          onDone: { router.pop() })
        case .dashboard:
            DashboardView(metrics: session.metrics ?? .empty,
                          valueRecoveredCad: session.valueRecoveredCad,
                          pendingValueCad: session.pendingValueCad,
                          onDone: { router.pop() })
        case .protectionLens(let context):
            ProtectionLensView(initialContext: context)
        case .benefitsReference:
            BenefitsReferenceView()
        case .categoryPicker(let category):
            if let category, let graph = environment.graph {
                CategoryBandListView(category: CategoryTaxonomy.canonicalID(category),
                                     deps: graph,
                                     distribution: .placeholderCanadianHousehold)
            } else {
                CategoryPickerView()
            }
        case .walletHealth:
            WalletHealthView(recentPurchases: session.recentPurchases)
        case .valuationSandbox:
            ValuationSandboxView()
        case .sync:
            SyncCenterView(isSignedIn: ClerkSession.isSignedIn,
                           onSync: { await syncFromUI() },
                           boundAccountLabel: captureBoundAccountLabel,
                           isCaptureBoundToCurrentAccount:
                               WalletCaptureCredentialStore().load()?.boundUserID == signedInUserID)
        case .settings:
            SettingsView(isSignedIn: ClerkSession.isSignedIn,
                         accountEmail: ClerkSession.currentUser?.primaryEmailAddress?.emailAddress,
                         lastSyncedAt: sync.lastSyncedAt,
                         syncIssue: sync.syncIssue,
                         ambientEnabled: environment.ambientReady,
                         onOpenSync: { router.push(.sync) },
                         onOpenAmbient: { router.push(.ambientSetup) },
                         onOpenLearnedMerchants: { router.push(.learnedMerchants) },
                         onOpenBenefits: { router.push(.benefitsReference) },
                         onEditWallet: { router.push(.walletSetup) },
                         onSignIn: { router.push(.sync) },
                         onSignOut: { Task { await environment.signOut(session: session, router: router) } },
                         onEraseLocalHistory: { environment.eraseLocalHistory(session: session) },
                         onDeleteAccount: { erase in
                             try await environment.deleteAccount(eraseLocalHistory: erase, session: session,
                                                                 router: router)
                         },
                         onDone: { router.pop() })
        case .walletSetup:
            if let graph = environment.graph {
                WalletEditorView(
                    catalogue: graph.catalogue,
                    existing: graph.ownerState,
                    isFirstRun: false,
                    onChange: { setup in
                        environment.applyWalletEdit(setup, session: session, router: router)
                    },
                    onCommitFirstRun: { setup in
                        await environment.saveWalletSetup(setup, session: session, router: router)
                    },
                    onRequestCard: { request in await environment.requestCard(request) },
                    onDone: { router.pop() })
            }
        case .ambientSetup:
            AmbientLocationExplainerView(
                isEnabled: environment.ambientEnabled,
                diagnostics: environment.ambientDiagnostics,
                coverage: environment.ambientCoverage,
                runtimeStatus: environment.ambientRuntimeStatus,
                ownerThreshold: environment.graph?.ownerState.switchThreshold,
                alertPolicy: environment.ambientAlertPolicy,
                onAlertPolicyChange: { environment.saveAmbientAlertPolicy($0) },
                fieldLogRecordCount: environment.ambientFieldLogRecordCount,
                onExportFieldLog: { environment.exportAmbientFieldLog() },
                onEnable: {
                    Task {
                        await environment.enableArrivalAlerts()
                    }
                },
                onTestNotification: {
                    Task { await environment.sendArrivalTestNotification() }
                },
                onDone: {
                    environment.refreshAmbientDiagnostics()
                    router.pop()
                }
            )
            .task { await environment.refreshAmbientRuntimeStatus() }
        case .learnedMerchants:
            LearnedMerchantsView(onDone: { router.pop() })
        }
    }

    private func findNearby() {
        guard let graph = environment?.graph else { return }
        if let prepared = session.preparedOutcomeForTap() {
            router.step = CheckoutFlowRouting.step(for: prepared)
            return
        }

        Task {
            let delayedSpinner = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                router.step = .locating
            }
            let outcome = await session.findNearby(using: graph)
            delayedSpinner.cancel()
            router.step = CheckoutFlowRouting.step(for: outcome)
        }
    }

    private func search(_ text: String) async {
        guard let graph = environment?.graph else { return }
        router.step = .locating
        let outcome = await session.search(text, using: graph)
        router.step = CheckoutFlowRouting.step(for: outcome)
    }

    private func syncCapsSilently() async {
        guard let environment, let graph = environment.graph else { return }
        if let result = await sync.syncCapsSilently(ownerState: graph.ownerState, catalogue: graph.catalogue) {
            environment.rebuild(ownerState: result.ownerState)
            await ingestAutomaticCaptures()
            if let refreshed = environment.graph { session.refresh(using: refreshed) }
        }
    }

    /// Best-effort by design: automatic logging must never turn an otherwise successful sync
    /// into a blocking screen over something the owner cannot act on.
    private func ingestAutomaticCaptures() async {
        guard let graph = environment?.graph else { return }
        do {
            try graph.service.ingestAutomaticCaptures(from: sync.walletFeedback)
            try await enrichUnknownWalletMerchants(using: graph)
            session.refresh(using: graph)
        } catch {
            #if DEBUG
            print("⚠️ Auto-capture ingest failed: \(error)")
            #endif
        }
    }

    /// Uses a capture's optional GPS fix to join an unknown Wallet descriptor to a nearby MapKit
    /// POI. The pure resolver enforces the confidence threshold; this layer only supplies places
    /// and persists matches. Failed searches remain retryable, while a completed no-match is not
    /// repeated again during the same app session.
    private func enrichUnknownWalletMerchants(using graph: DependencyGraph) async throws {
        // Selection moved into the service so the attempt is counted where it is decided. Doing it
        // here left "we looked and missed" indistinguishable from "we never looked", which is the
        // one distinction that says whether more merchant data would help.
        let candidates = try graph.service.walletEnrichmentCandidates(
            excluding: attemptedWalletEnrichmentIDs)

        for purchase in candidates {
            guard let eventID = purchase.walletEventId,
                  let latitude = purchase.merchantLatitude,
                  let longitude = purchase.merchantLongitude else { continue }
            do {
                let nearby = try await graph.provider.nearby(latitude: latitude,
                                                             longitude: longitude)
                if let resolution = resolveWalletMerchant(
                    capturedName: purchase.displayMerchant,
                    nearbyMerchants: nearby) {
                    try graph.service.enrichAutomaticPurchase(purchase, with: resolution)
                }
                attemptedWalletEnrichmentIDs.insert(eventID)
            } catch {
                // Connectivity and MapKit failures are transient. Leave this id unmarked so the
                // next activation or sync can retry without surfacing an error over checkout.
                #if DEBUG
                print("⚠️ Wallet merchant enrichment failed: \(error)")
                #endif
            }
        }
    }

    private func syncFromUI() async {
        guard let environment, let userID = signedInUserID else { return }
        if sync.readySyncUserID != userID {
            await environment.prepareAccount(forUserID: userID, session: session, router: router)
        }
        await syncCapsSilently()
    }
}
