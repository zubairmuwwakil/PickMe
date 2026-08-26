import Foundation
import Observation
import SwiftData
import CardCopilotEngine
import CardCopilotStore

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

/// Owns the dependency graph and its lifecycle.
///
/// Account operations live here rather than in a separate object because every one of them —
/// saving a wallet, applying a synced owner state, signing out — ends by rebuilding this graph.
/// Splitting them off would produce two objects that could never act independently.
@Observable
@MainActor
final class CopilotEnvironment {
    private(set) var graph: DependencyGraph?
    private(set) var seedOwnerState: OwnerState?
    private(set) var isFirstRun = false
    /// Set when seed data cannot be read at all. Distinct from an operational error: the app
    /// has nothing to show, so this is a full-screen state, not an alert.
    private(set) var loadFailure: String?

    private let modelContext: ModelContext
    private let sync: SyncCoordinator
    private let ambient: AmbientLocationService

    init(modelContext: ModelContext, sync: SyncCoordinator, ambient: AmbientLocationService) {
        self.modelContext = modelContext
        self.sync = sync
        self.ambient = ambient
    }

    /// Idempotent: repeated calls after a successful load are no-ops, matching the old
    /// `guard deps == nil else { return }`.
    func load() {
        guard graph == nil else { return }
        do {
            let catalogue = try SeedLoader.loadCatalogue()
            let candidates = try SeedLoader.loadCandidateCatalogue().cardIds
            let seedOwner = try SeedLoader.loadOwnerState()
            let localOwner = sync.ownerStateLocalStore.load()
            let owner = localOwner ?? seedOwner
            let benefits = try SeedLoader.loadBenefitsCatalogue()

            seedOwnerState = seedOwner
            isFirstRun = localOwner == nil
            graph = makeGraph(catalogue: catalogue, candidates: candidates,
                              owner: owner, benefits: benefits)
            configureAmbient(catalogue: catalogue, owner: owner)
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
                          owner: owner, benefits: existing.benefits)
        configureAmbient(catalogue: existing.catalogue, owner: owner)
        isFirstRun = false
    }

    /// Drops the graph and reloads from disk. Used after sign-out and account deletion, where
    /// the local owner-state store has changed underneath us.
    func reload() {
        graph = nil
        load()
    }

    private func makeGraph(catalogue: Catalogue, candidates: [String], owner: OwnerState,
                           benefits: BenefitsCatalogue) -> DependencyGraph {
        DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: candidates,
            ownerState: owner,
            benefits: benefits,
            service: CheckoutService(catalogue: catalogue, ownerState: owner, context: modelContext),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: LiveMerchantProvider())
    }

    private func configureAmbient(catalogue: Catalogue, owner: OwnerState) {
        ambient.configure(modelContainer: modelContext.container, catalogue: catalogue, ownerState: owner)
    }
}
