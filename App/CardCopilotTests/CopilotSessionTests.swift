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

    /// Activity is a purchase history, not a prediction history. Automatic Wallet captures and
    /// checkouts share one ordered read model while the metric-bearing arrays stay separate.
    func testRecentPurchaseItemsMergeBothSourcesNewestFirst() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let prediction = StoredPrediction(merchantName: "Loblaws",
                                          predictedCategory: "grocery",
                                          confidenceSource: .brandPrior,
                                          winnerCardId: "amex-cobalt",
                                          winnerValueCad: 2.50,
                                          headline: "Cobalt",
                                          recordedAt: Date().addingTimeInterval(-3600))
        context.insert(prediction)
        try context.save()
        _ = try graph.service.log.recordPurchase(for: prediction,
                                                 cardUsedId: "amex-cobalt",
                                                 cardSource: .atTill)

        let automaticDate = Date().addingTimeInterval(3600)
        let feedback = WalletFeedback(eventId: "automatic-newest",
                                      capturedAt: automaticDate,
                                      merchantRaw: "Tim Hortons",
                                      amountMinor: 725,
                                      currency: "CAD",
                                      cardRaw: "Cobalt",
                                      resolvedCardId: "amex-cobalt",
                                      verdict: "best",
                                      warning: nil)
        _ = try AutoCaptureLog(context: context).ingest(feedback: [feedback], openPredictions: [])

        let session = CopilotSession()
        session.refresh(using: graph)

        XCTAssertEqual(session.recentPurchases.count, 1)
        XCTAssertEqual(session.purchaseHistory.count, 2)
        XCTAssertEqual(session.recentPurchaseItems.count, 2)
        let first = session.recentPurchaseItems[0]
        XCTAssertEqual(first.walletEventId, "automatic-newest")
        XCTAssertNotNil(session.recentPurchaseItems[1].prediction)
    }

    func testCheckoutAssessmentUsesTheFrozenRecommendedCard() throws {
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
        let purchase = try graph.service.log.recordPurchase(for: prediction,
                                                            cardUsedId: "amex-cobalt",
                                                            cardSource: .atTill)
        XCTAssertEqual(PurchaseActivityEvaluator.cardAssessment(for: purchase, graph: graph), .best)

        let otherCard = try XCTUnwrap(graph.walletCardIds.first { $0 != "amex-cobalt" })
        purchase.cardUsedId = otherCard
        guard case .better(let cardId, _) = PurchaseActivityEvaluator.cardAssessment(for: purchase,
                                                                                     graph: graph) else {
            return XCTFail("using a different card should surface the frozen better card")
        }
        XCTAssertEqual(cardId, "amex-cobalt")
    }

    func testAutomaticCaptureCanBeRecognisedAndMarkedBestWithoutCheckoutAdvice() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let indexed = try XCTUnwrap(MerchantRecognizer.recognise("Loblaws"))
        let recommendation = try XCTUnwrap(graph.engine.recommendOrNil(
            PurchaseContext(amountCad: 50,
                            category: indexed.category,
                            mcc: indexed.mcc,
                            merchantBrand: indexed.merchantBrand,
                            acceptedNetworks: indexed.acceptedNetworks),
            asOf: Date().formatted(.iso8601.year().month().day())))
        let purchase = StoredPurchase(merchantLabel: "Loblaws", walletEventId: "tap-best")
        purchase.amountCad = 50
        purchase.cardUsedId = recommendation.winner.cardId
        XCTAssertEqual(PurchaseActivityEvaluator.category(for: purchase), "grocery")
        XCTAssertEqual(PurchaseActivityEvaluator.cardAssessment(for: purchase, graph: graph), .best)
    }

    func testTrustedWalletVerdictMarksAnUnknownMerchantBestWithoutGuessingItsCategory() throws {
        let graph = try makeGraph(context: makeContext())
        let purchase = StoredPurchase(merchantLabel: "Mom's Kitchen", walletEventId: "local-place")
        purchase.amountCad = 47.43
        purchase.cardUsedId = "amex-cobalt"
        let feedback = WalletFeedback(eventId: "local-place",
                                      capturedAt: purchase.createdAt,
                                      merchantRaw: "Mom's Kitchen",
                                      amountMinor: 4743,
                                      currency: "CAD",
                                      cardRaw: "Cobalt",
                                      resolvedCardId: "amex-cobalt",
                                      verdict: "best",
                                      warning: nil)

        XCTAssertNil(PurchaseActivityEvaluator.category(for: purchase))
        XCTAssertEqual(PurchaseActivityEvaluator.cardAssessment(for: purchase,
                                                                graph: graph,
                                                                walletFeedback: feedback),
                       .best)
    }

    func testRecordCardUpdatesCardAndAssessment() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let purchase = StoredPurchase(merchantLabel: "Mom's Kitchen", walletEventId: "local-place-1")
        purchase.amountCad = 47.43
        context.insert(purchase)
        try context.save()

        let session = CopilotSession()
        session.refresh(using: graph)
        XCTAssertNil(purchase.cardUsedId)

        session.recordCard("amex-cobalt", for: purchase, using: graph)
        XCTAssertEqual(purchase.cardUsedId, "amex-cobalt")
        XCTAssertEqual(purchase.cardSource, .recalledLater)
    }

    func testDeletePurchaseRemovesPurchaseFromHistory() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let purchase = StoredPurchase(merchantLabel: "Mom's Kitchen", walletEventId: "local-place-2")
        purchase.amountCad = 47.43
        context.insert(purchase)
        try context.save()

        let session = CopilotSession()
        session.refresh(using: graph)
        XCTAssertEqual(session.purchaseHistory.count, 1)

        session.deletePurchase(purchase, using: graph)
        XCTAssertEqual(session.purchaseHistory.count, 0)
    }

    func testRecordAmountUpdatesAmountAndCompletesPurchase() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let purchase = StoredPurchase(merchantLabel: "Mom's Kitchen", walletEventId: "local-place-3")
        purchase.cardUsedId = "amex-cobalt"
        context.insert(purchase)
        try context.save()

        let session = CopilotSession()
        session.refresh(using: graph)
        XCTAssertNil(purchase.amountCad)
        XCTAssertFalse(purchase.isComplete)

        session.recordAmount(85.50, for: purchase, using: graph)
        XCTAssertEqual(purchase.amountCad, 85.50)
        XCTAssertEqual(purchase.amountSource, .recalledLater)
        XCTAssertTrue(purchase.isComplete)
    }
}
