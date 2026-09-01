import XCTest
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// Loading the dependency graph and refreshing the state derived from it were one call in the
/// 846-line predecessor (`loadDependencies` ended in `refreshHome`). Splitting them across two
/// objects turned that invariant into a convention, and three launch paths dropped it. These
/// pin it back.
@MainActor
final class CopilotEnvironmentTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CardCopilotSchema.current)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Every store is pinned to a throwaway suite so a test can never read — or evict — the
    /// wallet a real install left in the shared app group.
    private func makeSync() throws -> SyncCoordinator {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CopilotEnvironmentTests.\(UUID().uuidString)"))
        return SyncCoordinator(
            ownerStateLocalStore: OwnerStateLocalStore(defaults: defaults),
            accountOwnerStateStore: AccountOwnerStateStore(defaults: defaults))
    }

    private func makeGraph(context: ModelContext) throws -> DependencyGraph {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        return DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: [],
            ownerState: owner,
            benefits: try SeedLoader.loadBenefitsCatalogue(),
            service: CheckoutService(catalogue: catalogue, ownerState: owner, context: context),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: LiveMerchantProvider())
    }

    /// One purchase started and left unfinished — the row Home counts as a chore.
    private func seedOneUnfinishedPurchase(in context: ModelContext,
                                           using graph: DependencyGraph) throws {
        let prediction = StoredPrediction(merchantName: "Loblaws",
                                          predictedCategory: "grocery",
                                          confidenceSource: .brandPrior,
                                          winnerCardId: "amex-cobalt",
                                          winnerValueCad: 2.50,
                                          headline: "Cobalt")
        context.insert(prediction)
        try context.save()
        _ = try graph.service.log.recordPurchase(for: prediction)
    }

    /// A signed-out cold launch, replayed as `CheckoutFlowView` performs it: `.task` loads the
    /// graph, then `.task(id:)` calls `prepareAccount` with no user, which returns at its first
    /// guard. Nothing else refreshes on that path, so when `load` did not, the local-only owner
    /// — the "Continue privately" install — saw $0.00 recovered, no instant-repeat merchants and
    /// an empty Activity badge on every launch, over a store full of purchases.
    func testASignedOutColdLaunchShowsTheStoredHistory() async throws {
        let context = try makeContext()
        try seedOneUnfinishedPurchase(in: context, using: try makeGraph(context: context))

        let environment = CopilotEnvironment(modelContext: context, sync: try makeSync(),
                                             ambient: AmbientLocationService())
        let session = CopilotSession()
        let router = CheckoutRouter()

        environment.load(session: session)
        await environment.prepareAccount(forUserID: nil, session: session, router: router)

        XCTAssertEqual(session.completionQueue.count, 1,
                       "Loading the graph must leave the session showing what is in the store")
    }

    /// Sign-out drops the graph and rebuilds it around the device wallet. The session's counts
    /// are derived from that graph, so skipping the refresh leaves the previous account's totals
    /// standing over the wallet that replaced them.
    func testSigningOutRederivesTheSessionFromTheStore() async throws {
        let context = try makeContext()
        let environment = CopilotEnvironment(modelContext: context, sync: try makeSync(),
                                             ambient: AmbientLocationService())
        let session = CopilotSession()
        let router = CheckoutRouter()

        environment.load(session: session)
        try seedOneUnfinishedPurchase(in: context, using: try XCTUnwrap(environment.graph))
        await environment.signOut(session: session, router: router)

        XCTAssertEqual(session.completionQueue.count, 1,
                       "Rebuilding the graph on sign-out must refresh the state derived from it")
    }

    /// A brand-new install has no local owner state, so the welcome gate is up. It is rendered as
    /// the root *of* the navigation stack, not beside it — pinned here because the alternative
    /// compiles, looks right, and silently strands the owner: `.walletSetup` lands on a path
    /// nothing is rendering and the gate never moves.
    func testAFreshInstallRaisesTheFirstRunGate() throws {
        let environment = CopilotEnvironment(modelContext: try makeContext(), sync: try makeSync(),
                                             ambient: AmbientLocationService())
        environment.load(session: CopilotSession())

        XCTAssertTrue(environment.isFirstRun)
        XCTAssertNotNil(environment.graph, "The gate is a root swap, not a reason to skip loading")
    }

    /// `owner-state.json` is an engine fixture, not a starter wallet. It currently describes the
    /// original 27-card test portfolio, so using it as the fallback when the device store is empty
    /// makes every one of those cards appear as "In Wallet" on a brand-new install.
    func testAFreshInstallDoesNotAdoptTheBundledOwnerFixture() throws {
        let bundledFixture = try SeedLoader.loadOwnerState()
        XCTAssertFalse(bundledFixture.ownedCardIds.isEmpty,
                       "The regression needs a non-empty engine fixture to distinguish from onboarding")

        let environment = CopilotEnvironment(modelContext: try makeContext(), sync: try makeSync(),
                                             ambient: AmbientLocationService())
        environment.load(session: CopilotSession())
        let graph = try XCTUnwrap(environment.graph)

        XCTAssertTrue(graph.ownerState.ownedCardIds.isEmpty,
                      "Missing local state means a new empty wallet, not the bundled test owner")
        XCTAssertTrue(graph.walletCards.isEmpty)
        XCTAssertTrue(graph.walletCardIds.isEmpty)
    }

    func testLaunchKeepsAnExistingStoredWalletAuthoritative() throws {
        let sync = try makeSync()
        var stored = try SeedLoader.loadOwnerState()
        stored.ownedCardIds = ["amex-cobalt"]
        stored.defaultCardId = "amex-cobalt"
        try sync.ownerStateLocalStore.save(stored)

        let environment = CopilotEnvironment(modelContext: try makeContext(), sync: sync,
                                             ambient: AmbientLocationService())
        environment.load(session: CopilotSession())

        XCTAssertFalse(environment.isFirstRun)
        XCTAssertFalse(environment.walletIsFirstRun)
        XCTAssertEqual(environment.graph?.ownerState, stored)
        XCTAssertEqual(environment.graph?.walletCardIds, ["amex-cobalt"])
    }

    func testLaunchRepairsAnExactlyPersistedBundledFixture() throws {
        let sync = try makeSync()
        try sync.ownerStateLocalStore.save(SeedLoader.loadOwnerState())

        let environment = CopilotEnvironment(modelContext: try makeContext(), sync: sync,
                                             ambient: AmbientLocationService())
        environment.load(session: CopilotSession())

        XCTAssertTrue(environment.isFirstRun)
        XCTAssertTrue(environment.walletIsFirstRun)
        XCTAssertTrue(try XCTUnwrap(environment.graph).ownerState.ownedCardIds.isEmpty)
    }

    func testContinuingPrivatelyDismissesFirstRunAndPersistsState() throws {
        let sync = try makeSync()
        let environment = CopilotEnvironment(modelContext: try makeContext(), sync: sync,
                                             ambient: AmbientLocationService())
        let session = CopilotSession()
        environment.load(session: session)

        XCTAssertTrue(environment.isFirstRun)
        XCTAssertTrue(environment.walletIsFirstRun)

        environment.continuePrivately(session: session)

        XCTAssertFalse(environment.isFirstRun)
        XCTAssertFalse(environment.walletIsFirstRun)
        let saved = try XCTUnwrap(sync.ownerStateLocalStore.load(),
                                 "Local owner state must be saved on continue privately")
        XCTAssertTrue(saved.ownedCardIds.isEmpty,
                      "Continuing privately must not make the bundled 27-card fixture durable")

        // Reloading with the saved store must not raise the first-run gate again
        let nextSession = CopilotSession()
        let nextEnvironment = CopilotEnvironment(modelContext: try makeContext(), sync: sync,
                                                 ambient: AmbientLocationService())
        nextEnvironment.load(session: nextSession)
        XCTAssertFalse(nextEnvironment.isFirstRun)
        XCTAssertFalse(nextEnvironment.walletIsFirstRun)
    }

    func testPreparingConfirmedEmptyNewAccountDoesNotPushWalletSetup() async throws {
        let sync = try makeSync()
        let environment = CopilotEnvironment(modelContext: try makeContext(), sync: sync,
                                             ambient: AmbientLocationService(),
                                             remoteOwnerStateLoader: { nil })
        let session = CopilotSession()
        let router = CheckoutRouter()

        environment.load(session: session)
        await environment.prepareAccount(forUserID: "new-user-123", session: session, router: router)

        XCTAssertFalse(router.path.contains(.walletSetup), "New accounts must not be forced into walletSetup")
        XCTAssertTrue(router.showingAddCard, "New accounts must open addCard directly")
        XCTAssertFalse(environment.walletIsFirstRun)
    }

    func testFailedNewAccountDownloadDoesNotInventAnEmptyCloudWallet() async throws {
        let sync = try makeSync()
        let environment = CopilotEnvironment(modelContext: try makeContext(), sync: sync,
                                             ambient: AmbientLocationService(),
                                             remoteOwnerStateLoader: { throw URLError(.timedOut) })
        let session = CopilotSession()
        let router = CheckoutRouter()
        environment.load(session: session)
        let before = try XCTUnwrap(environment.graph?.ownerState)

        await environment.prepareAccount(forUserID: "unreachable-user", session: session, router: router)

        XCTAssertEqual(environment.graph?.ownerState, before)
        XCTAssertFalse(router.showingAddCard)
        XCTAssertNil(sync.readySyncUserID)
        XCTAssertNotNil(sync.syncMetadataStore.issue(forUserID: "unreachable-user"))
    }

    func testEmptyOwnerStateYieldsEmptyWalletCards() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        var emptyOwner = try SeedLoader.loadOwnerState()
        emptyOwner.ownedCardIds = []
        let graph = DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: [],
            ownerState: emptyOwner,
            benefits: try SeedLoader.loadBenefitsCatalogue(),
            service: CheckoutService(catalogue: catalogue, ownerState: emptyOwner, context: try makeContext()),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: emptyOwner),
            provider: LiveMerchantProvider())

        XCTAssertTrue(graph.walletCards.isEmpty, "Empty owner state must yield empty walletCards rather than leaking the full catalogue")
        XCTAssertTrue(graph.walletCardIds.isEmpty, "Empty owner state must yield empty walletCardIds")
    }
}
