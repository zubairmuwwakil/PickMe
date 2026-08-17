import SwiftUI
import SwiftData
import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import ClerkKit

/// The core loop: find or search the merchant, capture the amount, show the answer.
struct CheckoutFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stage: Stage = .idle
    @State private var deps: Dependencies?
    @State private var locationDenied = false
    @State private var cachedLocation: CachedLocation?
    @State private var homeMerchants: [StoredMerchant] = []
    @State private var valueRecoveredCad: Double = 0
    @State private var reconcileQueue: [StoredPrediction] = []
    @State private var metrics: ExperimentMetrics?
    @State private var lastSyncedAt: Date?
    @State private var walletFeedback: [WalletFeedback] = []
    @State private var isSyncing = false

    enum Stage {
        case idle
        case locating
        case confirming(merchants: [NearbyMerchant])
        case amount(merchant: NearbyMerchant)
        case recommendation(CheckoutResult)
        case reconcile
        case dashboard
        case protectionLens(BenefitContext)
        case benefitsReference
        case walletHealth
        case sync
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
                .navigationTitle("Card Copilot")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { stage = .sync } label: {
                            Image(systemName: lastSyncedAt == nil ? "icloud" : "checkmark.icloud")
                        }
                        .accessibilityLabel("Sync and Wallet Capture")
                    }
                }
        }
        .task { loadDependencies() }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle:
            HomeView(valueRecoveredCad: valueRecoveredCad,
                     merchants: homeMerchants,
                     isSortedByRecentLocation: cachedLocation?.isRecent == true,
                     locationDenied: locationDenied,
                     reconcileCount: reconcileQueue.count,
                     confirmedCount: metrics?.confirmedCount ?? 0,
                     onInstantRepeat: { merchant in startInstantRepeat(merchant) },
                     onFindNearby: { Task { await findNearby() } },
                     onSearch: { text in Task { await search(text) } },
                     onReconcile: { stage = .reconcile },
                     onDashboard: { stage = .dashboard },
                     onProtectionLens: { stage = .protectionLens(BenefitContext(kind: .flight)) },
                     onBenefits: { stage = .benefitsReference },
                     onWalletHealth: { stage = .walletHealth })
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
        case .reconcile:
            ReconcileView(queue: reconcileQueue,
                          cards: deps?.catalogue.cards ?? [],
                          categories: deps.map { observableCategories(in: $0.catalogue) } ?? [],
                          onConfirm: { prediction, entry in confirm(prediction, entry: entry) },
                          onDone: { stage = .idle })
        case .dashboard:
            DashboardView(metrics: metrics ?? .empty,
                          valueRecoveredCad: valueRecoveredCad,
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
        case .walletHealth:
            if let deps {
                WalletHealthView(deps: deps, onDone: { stage = .idle })
            }
        case .sync:
            SyncCenterView(isSignedIn: MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil,
                           lastSyncedAt: lastSyncedAt,
                           feedback: walletFeedback,
                           isSyncing: isSyncing,
                           onSync: { Task { await syncCapsSilently() } },
                           onCreateInstallation: { label in try await createInstallation(label: label) },
                           onDone: { stage = .idle })
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
            let owner = try SeedLoader.loadOwnerState()
            let benefits = try SeedLoader.loadBenefitsCatalogue()
            deps = makeDependencies(catalogue: catalogue, candidates: candidates, owner: owner, benefits: benefits)
            refreshHome()
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
            stage = .recommendation(try deps.service.recommend(merchant: merchant,
                                                               amountCad: amount,
                                                               asOf: today))
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

    /// Attaching an observation to a prediction. The prediction is never touched — the store
    /// offers no way to touch it — so this reads as "record what happened", not "fix the guess".
    private func confirm(_ prediction: StoredPrediction, entry: ReconcileEntry) {
        guard let deps else { return }
        do {
            try deps.service.log.confirm(prediction,
                                         cardUsed: entry.cardUsed,
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
            valueRecoveredCad = try deps.service.log.valueRecovered()
            homeMerchants = sortedHomeMerchants(try deps.service.knownMerchants())
            reconcileQueue = try deps.service.log.awaitingConfirmation()
            metrics = try deps.service.log.metrics()
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
            walletFeedback = result.feedback
            lastSyncedAt = result.lastSyncedAt
        } catch {
            // A1: existing local state is usable; connectivity must never interrupt checkout.
        }
    }

    private func createInstallation(label: String) async throws -> String {
        guard MoneyTalksConfiguration.isConfigured, let baseURL = MoneyTalksConfiguration.apiBaseURL else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        let client = MoneyTalksAPIClient(baseURL: baseURL) { try await Clerk.shared.auth.getToken() }
        let installation = try await client.createWalletInstallation(label: label)
        guard let token = installation.token else { throw MoneyTalksAPIError.unexpectedResponse(-1) }
        return token
    }

    private func makeDependencies(catalogue: Catalogue, candidates: Catalogue, owner: OwnerState,
                                  benefits: BenefitsCatalogue) -> Dependencies {
        Dependencies(catalogue: catalogue, candidateCatalogue: candidates, ownerState: owner, benefits: benefits,
                     service: CheckoutService(catalogue: catalogue, ownerState: owner, context: modelContext),
                     explainer: RecommendationExplainer(catalogue: catalogue),
                     engine: RecommendationEngine(catalogue: catalogue, ownerState: owner), provider: LiveMerchantProvider())
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
