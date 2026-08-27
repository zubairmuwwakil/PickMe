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
    @State private var ambient = AmbientLocationService()
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @State private var environment: CopilotEnvironment?
    @State private var walletBannerCenter = WalletCaptureBannerCenter.shared

    private var rootTitle: String {
        switch router.selectedTab {
        case .copilot: return "PickMe"
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

    private var captureBoundAccountLabel: String? {
        guard let credential = WalletCaptureCredentialStore().load() else { return nil }
        guard let current = Clerk.shared.user else { return "Connected account (signed out)" }
        guard current.id == credential.boundUserID else { return "Different Inunity account — relink required" }
        return current.primaryEmailAddress?.emailAddress ?? String(current.id.prefix(12))
    }

    var body: some View {
        @Bindable var router = router
        Group {
            if let environment {
                if let loadFailure = environment.loadFailure {
                    ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle",
                                           description: Text(loadFailure))
                } else if environment.graph == nil {
                    ProgressView()
                } else if environment.isFirstRun {
                    WelcomeGatewayView(
                        isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                        isPreparingAccount: sync.isPreparingAccount,
                        syncIssueMessage: sync.syncIssue?.message,
                        onRetryAccountRestore: {
                            Task { await environment.prepareAccount(forUserID: Clerk.shared.user?.id,
                                                                    session: session, router: router) }
                        },
                        onContinuePrivately: { router.push(.walletSetup) }
                    )
                } else {
                    NavigationStack(path: $router.path) {
                        checkoutStepContent(environment: environment)
                            .navigationTitle(isAtRoot ? rootTitle : "PickMe")
                            .navigationDestination(for: Destination.self) { destination in
                                destinationView(destination, environment: environment)
                            }
                            .toolbar {
                                if isAtRoot {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        SyncStatusToolbarButton(
                                            isSyncing: sync.isSyncing || sync.isPreparingAccount,
                                            lastSyncedAt: sync.lastSyncedAt,
                                            syncIssue: sync.syncIssue,
                                            action: { router.push(.sync) }
                                        )
                                    }
                                }
                            }
                    }
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
            environment.load()
            _ = WalletCaptureNetworkMonitor.shared
            await sync.drainWalletCaptures()
            if WalletCaptureDeepLinkStore.consume() { router.push(.sync) }
        }
        .task(id: Clerk.shared.user?.id) {
            await ensureEnvironment().prepareAccount(forUserID: Clerk.shared.user?.id,
                                                     session: session, router: router)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                environment?.refreshAmbientDiagnostics()
                Task { await sync.drainWalletCaptures(); await autoSyncIfStale() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .walletCaptureConnectivityRestored)) { _ in
            Task { await sync.drainWalletCaptures() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWalletCaptureStatus)) { _ in
            router.push(.sync)
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
                                onConfirm: { router.step = .amount($0) },
                                onSearch: { text in Task { await search(text) } },
                                onCancel: { router.resetToIdle() })
        case .amount(let merchant):
            AmountCaptureView(merchantName: merchant.name,
                              onAmount: { amount in
                                  if let graph = environment.graph {
                                      router.step = session.recommend(merchant: merchant, amount: amount,
                                                                      using: graph)
                                  }
                              },
                              onCancel: { router.resetToIdle() })
        case .recommendation(let result):
            RecommendationView(result: result,
                               deps: environment.graph,
                               onCompare: { kind in router.push(.protectionLens(BenefitContext(kind: kind))) },
                               onDone: {
                                   LiveActivityManager.shared.endActivity()
                                   if let graph = environment.graph { session.refresh(using: graph) }
                                   router.resetToIdle()
                               })
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
                    HomeView(valueRecoveredCad: session.valueRecoveredCad,
                             pendingValueCad: session.pendingValueCad,
                             merchants: session.homeMerchants,
                             isSortedByRecentLocation: session.cachedLocation?.isRecent == true,
                             locationDenied: session.locationDenied,
                             finishCount: session.completionQueue.count,
                             reconcileCount: session.reconcileQueue.count,
                             confirmedCount: session.metrics?.confirmedCount ?? 0,
                             ambientDiagnostics: environment.ambientDiagnostics,
                             ambientEnabled: ambient.isEnabled,
                             deps: environment.graph,
                             onSelectPreIndexedMerchant: { match in
                                 router.step = .amount(NearbyMerchant(id: "preindex:\(match.id)",
                                                                      name: match.name,
                                                                      poiCategoryRaw: match.category,
                                                                      latitude: 0,
                                                                      longitude: 0,
                                                                      distanceMeters: nil))
                             },
                             onInstantRepeat: { merchant in router.step = session.startInstantRepeat(merchant) },
                             onLogPurchase: { merchant, amount in
                                 if let graph = environment.graph {
                                     session.logInstantPurchase(merchant, amount: amount, using: graph)
                                 }
                             },
                             onOpenDetails: { merchant, amount in
                                 if let graph = environment.graph {
                                     router.step = session.startInstantRepeatWithAmount(merchant, amount: amount,
                                                                                        using: graph)
                                 }
                             },
                             onFindNearby: { Task { await findNearby() } },
                             onSearch: { text in Task { await search(text) } },
                             onFinish: { router.push(.finish) },
                             onReconcile: { router.push(.reconcile) },
                             onDashboard: { router.push(.dashboard) },
                             onProtectionLens: { router.push(.protectionLens(BenefitContext(kind: .flight))) },
                             onBenefits: { router.push(.benefitsReference) },
                             onCategoryPicker: { router.push(.categoryPicker) },
                             onWalletHealth: { router.push(.walletHealth) },
                             onValuationSandbox: { router.push(.valuationSandbox) },
                             onConfigureAmbient: { router.push(.ambientSetup) })
                case .activity:
                    ActivityHubView(
                        finishCount: session.completionQueue.count,
                        reconcileCount: session.reconcileQueue.count,
                        metrics: session.metrics,
                        valueRecoveredCad: session.valueRecoveredCad,
                        pendingValueCad: session.pendingValueCad,
                        recentPurchases: session.recentPurchases,
                        cards: environment.graph?.walletCards ?? [],
                        onFinish: { router.push(.finish) },
                        onReconcile: { router.push(.reconcile) },
                        onOpenDashboard: { router.push(.dashboard) },
                        onSelectPurchase: { prediction in
                            if prediction.purchase?.isComplete == false {
                                router.push(.finish)
                            }
                        },
                        onUpdateCategory: { prediction, newCategory in
                            if let graph = environment.graph {
                                session.updateCategory(for: prediction, to: newCategory, using: graph)
                            }
                        }
                    )
                case .wallet:
                    WalletHubView(
                        deps: environment.graph,
                        onCategoryPicker: { router.push(.categoryPicker) },
                        onWalletHealth: { router.push(.walletHealth) },
                        onValuationSandbox: { router.push(.valuationSandbox) },
                        onEditWallet: { router.push(.walletSetup) }
                    )
                case .perks:
                    PerksHubView(
                        deps: environment.graph,
                        onProtectionLens: { kind in router.push(.protectionLens(BenefitContext(kind: kind))) },
                        onBenefitsReference: { router.push(.benefitsReference) }
                    )
                case .you:
                    YouHubView(
                        isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                        accountEmail: Clerk.shared.user?.primaryEmailAddress?.emailAddress,
                        lastSyncedAt: sync.lastSyncedAt,
                        syncIssue: sync.syncIssue,
                        ambientEnabled: ambient.isEnabled,
                        ambientDiagnostics: environment.ambientDiagnostics,
                        onOpenSync: { router.push(.sync) },
                        onOpenAmbient: { router.push(.ambientSetup) },
                        onEditWallet: { router.push(.walletSetup) },
                        onSignIn: { router.push(.sync) },
                        onSignOut: { Task { await environment.signOut(router: router) } },
                        onEraseLocalHistory: { environment.eraseLocalHistory(session: session) },
                        onDeleteAccount: { erase in
                            try await environment.deleteAccount(eraseLocalHistory: erase, session: session,
                                                                router: router)
                        }
                    )
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
            if let graph = environment.graph {
                ProtectionLensView(deps: graph, initialContext: context, onDone: { router.pop() })
            }
        case .benefitsReference:
            if let graph = environment.graph {
                BenefitsReferenceView(deps: graph, onDone: { router.pop() })
            }
        case .categoryPicker:
            if let graph = environment.graph {
                CategoryPickerView(deps: graph, onDone: { router.pop() })
            }
        case .walletHealth:
            if let graph = environment.graph {
                WalletHealthView(deps: graph, recentPurchases: session.recentPurchases, onDone: { router.pop() })
            }
        case .valuationSandbox:
            if let graph = environment.graph {
                ValuationSandboxView(deps: graph, onDone: { router.pop() })
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
                           onCreateInstallation: { label in try await environment.createInstallation(label: label) },
                           onRevokeInstallation: { id in try await sync.revokeWalletInstallation(id: id) },
                           boundAccountLabel: captureBoundAccountLabel,
                           isCaptureBoundToCurrentAccount:
                               WalletCaptureCredentialStore().load()?.boundUserID == Clerk.shared.user?.id,
                           onTestCaptureConnection: { await sync.testWalletCaptureConnection() },
                           onAssignUnassigned: { try await sync.assignUnassignedCaptures() },
                           onDeleteUnassigned: { try await sync.deleteUnassignedCaptures() },
                           onDisableCapture: { delete in try await sync.disableWalletCapture(deleteUnsent: delete) },
                           onSubmitDiagnostic: { report in try await sync.submitDiagnostic(report) },
                           onDeleteSubmittedDiagnostic: { id in try await sync.deleteSubmittedDiagnostic(id: id) },
                           onListSubmittedDiagnostics: { try await sync.listSubmittedDiagnostics() },
                           onDone: { router.pop() })
        case .settings:
            SettingsView(isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                         accountEmail: Clerk.shared.user?.primaryEmailAddress?.emailAddress,
                         lastSyncedAt: sync.lastSyncedAt,
                         syncIssue: sync.syncIssue,
                         ambientEnabled: ambient.isEnabled,
                         onOpenSync: { router.push(.sync) },
                         onOpenAmbient: { router.push(.ambientSetup) },
                         onEditWallet: { router.push(.walletSetup) },
                         onSignIn: { router.push(.sync) },
                         onSignOut: { Task { await environment.signOut(router: router) } },
                         onEraseLocalHistory: { environment.eraseLocalHistory(session: session) },
                         onDeleteAccount: { erase in
                             try await environment.deleteAccount(eraseLocalHistory: erase, session: session,
                                                                 router: router)
                         },
                         onDone: { router.pop() })
        case .walletSetup:
            if let graph = environment.graph, let seedOwnerState = environment.seedOwnerState {
                WalletSetupView(catalogue: graph.catalogue, seed: seedOwnerState,
                                existing: environment.walletIsFirstRun ? nil : graph.ownerState,
                                isFirstRun: environment.walletIsFirstRun,
                                onSave: { setup in
                                    await environment.saveWalletSetup(setup, session: session, router: router)
                                },
                                onRequestCard: { request in await environment.requestCard(request) },
                                onDone: { router.pop() })
            }
        case .ambientSetup:
            AmbientLocationExplainerView(
                isEnabled: ambient.isEnabled,
                diagnostics: environment.ambientDiagnostics,
                onEnable: {
                    ambient.requestAlwaysAuthorization()
                    environment.refreshAmbientDiagnostics()
                    router.pop()
                },
                onDone: { router.pop() }
            )
        }
    }

    private func findNearby() async {
        guard let graph = environment?.graph else { return }
        router.step = .locating
        let outcome = await session.findNearby(using: graph)
        router.step = CheckoutFlowRouting.step(for: outcome)
    }

    private func search(_ text: String) async {
        guard let graph = environment?.graph else { return }
        router.step = .locating
        let outcome = await session.search(text, using: graph)
        router.step = CheckoutFlowRouting.step(for: outcome)
    }

    private func autoSyncIfStale() async {
        guard let environment, let graph = environment.graph else { return }
        if let result = await sync.autoSyncIfStale(ownerState: graph.ownerState, catalogue: graph.catalogue) {
            environment.rebuild(ownerState: result.ownerState)
            if let refreshed = environment.graph { session.refresh(using: refreshed) }
        }
    }

    private func syncCapsSilently() async {
        guard let environment, let graph = environment.graph else { return }
        if let result = await sync.syncCapsSilently(ownerState: graph.ownerState, catalogue: graph.catalogue) {
            environment.rebuild(ownerState: result.ownerState)
            if let refreshed = environment.graph { session.refresh(using: refreshed) }
        }
    }

    private func syncFromUI() async {
        guard let environment, let userID = Clerk.shared.user?.id else { return }
        if sync.readySyncUserID != userID {
            await environment.prepareAccount(forUserID: userID, session: session, router: router)
        }
        await syncCapsSilently()
    }
}
