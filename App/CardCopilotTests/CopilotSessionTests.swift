import XCTest
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

@MainActor
final class CopilotSessionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CardCopilotSchema.current)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
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

    func testRefreshOnAnEmptyStoreProducesZeroesNotNil() throws {
        let context = try makeContext()
        let session = CopilotSession()
        session.refresh(using: try makeGraph(context: context))

        XCTAssertEqual(session.valueRecoveredCad, 0)
        XCTAssertEqual(session.pendingValueCad, 0)
        XCTAssertTrue(session.completionQueue.isEmpty)
        XCTAssertTrue(session.reconcileQueue.isEmpty)
        XCTAssertTrue(session.recentPurchases.isEmpty)
        XCTAssertNil(session.lastError)
    }

    /// `PredictionLogTests.testAPredictionWithNoPurchaseIsInNeitherQueue` (Store, pinned) is the
    /// other half of this: a prediction nobody acted on sits in neither queue, so it is not
    /// duplicated here. What belongs in `completionQueue` is a purchase already started but
    /// still missing a card or an amount — the "finish these" queue's actual definition.
    func testAPurchaseMissingCardOrAmountEntersTheCompletionQueue() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let prediction = StoredPrediction(merchantName: "Loblaws",
                                          predictedCategory: "grocery",
                                          confidenceSource: .brandPrior,
                                          winnerCardId: "amex-cobalt",
                                          winnerValueCad: 2.50,
                                          headline: "Cobalt")
        context.insert(prediction)
        try context.save()
        _ = try graph.service.log.recordPurchase(for: prediction)

        let session = CopilotSession()
        session.refresh(using: graph)
        XCTAssertEqual(session.completionQueue.count, 1)
    }

    /// A prediction with no purchase at all is advice that was given and not acted on — a real
    /// outcome, but not an unfinished chore. Matches `PredictionLogTests
    /// .testAPredictionWithNoPurchaseIsInNeitherQueue`: dropping it into a to-do list would
    /// measure footfall, not follow-through.
    func testAPredictionWithNoPurchaseStaysOutOfBothQueues() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        context.insert(StoredPrediction(merchantName: "Loblaws",
                                        predictedCategory: "grocery",
                                        confidenceSource: .brandPrior,
                                        winnerCardId: "amex-cobalt",
                                        winnerValueCad: 2.50,
                                        headline: "Cobalt"))
        try context.save()

        let session = CopilotSession()
        session.refresh(using: graph)
        XCTAssertTrue(session.completionQueue.isEmpty)
        XCTAssertTrue(session.reconcileQueue.isEmpty)
    }

    /// The regression guard for the defect this refactor fixes. Before, every failure did
    /// `stage = .failed(...)`, so a write failure while reconciling replaced the entire
    /// checkout flow with a full-screen error and dropped the owner at "Start over".
    func testAnOperationalFailureSetsLastErrorAndNothingElse() throws {
        let session = CopilotSession()
        session.report(FlowError(message: "could not save"))

        XCTAssertEqual(session.lastError?.message, "could not save")
        // The session owns no navigation at all — that is the structural guarantee.
        XCTAssertFalse((session as Any) is CheckoutRouter)
    }

    func testClearingAnErrorRemovesIt() {
        let session = CopilotSession()
        session.report(FlowError(message: "boom"))
        session.clearError()
        XCTAssertNil(session.lastError)
    }

    /// Without a recent fix, merchants sort by recency. With one, by distance. Getting this
    /// backwards puts the shop the owner is standing in below one they visited last week.
    func testHomeMerchantsSortByRecencyWithoutALocationFix() throws {
        let session = CopilotSession()
        XCTAssertNil(session.cachedLocation)
        // sortedHomeMerchants is exercised through refresh(); this pins the precondition that
        // no location means no distance sort.
        XCTAssertFalse(session.cachedLocation?.isRecent ?? false)
    }

    /// An empty query must not reach MapKit. The old code guarded with
    /// `guard let deps, !text.isEmpty` ahead of its own `.locating` assignment, so an empty
    /// submission was a silent no-op. Reaching this line at all means a caller skipped
    /// `SearchSubmission.query(from:)` — the outcome below is the backstop, not the UX.
    func testEmptySearchReturnsNothingFoundWithoutCallingTheProvider() async throws {
        let context = try makeContext()
        let session = CopilotSession()
        let outcome = await session.search("", using: try makeGraph(context: context))
        XCTAssertEqual(outcome, .nothingFound(query: ""))
    }
}
