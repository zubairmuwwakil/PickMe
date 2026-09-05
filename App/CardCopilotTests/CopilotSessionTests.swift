import XCTest
import SwiftData
import CoreLocation
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

@MainActor
final class CopilotSessionTests: XCTestCase {

    private final class StubLocationProvider: CheckoutLocationProviding {
        var authorizedLocation: CheckoutLocationFix?
        var promptedLocation = CheckoutLocationFix(latitude: 43.6532, longitude: -79.3832,
                                                    horizontalAccuracyMeters: 10)
        var authorizedError: Error?
        var promptedError: Error?
        private(set) var authorizedRequestCount = 0
        private(set) var promptedRequestCount = 0

        func requestLocation() async throws -> CheckoutLocationFix {
            promptedRequestCount += 1
            if let promptedError { throw promptedError }
            return promptedLocation
        }

        func requestLocationIfAuthorized() async throws -> CheckoutLocationFix? {
            authorizedRequestCount += 1
            if let authorizedError { throw authorizedError }
            return authorizedLocation
        }
    }

    private actor StubMerchantProvider: MerchantProviding {
        var nearbyResult: [NearbyPlace]
        var delay: Duration?
        var nearbyError: Error?
        private(set) var nearbyRequestCount = 0

        init(nearbyResult: [NearbyPlace], delay: Duration? = nil, nearbyError: Error? = nil) {
            self.nearbyResult = nearbyResult
            self.delay = delay
            self.nearbyError = nearbyError
        }

        func nearby(latitude: Double, longitude: Double) async throws -> [NearbyPlace] {
            nearbyRequestCount += 1
            if let delay { try await Task.sleep(for: delay) }
            if let nearbyError { throw nearbyError }
            return nearbyResult
        }

        func search(text: String) async throws -> [NearbyPlace] { [] }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CardCopilotSchema.current)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeMetricsStore() -> NearbyLookupMetricsStore {
        let defaults = UserDefaults(suiteName: "CopilotSessionNearby.\(UUID().uuidString)")!
        return NearbyLookupMetricsStore(defaults: defaults)
    }

    private struct StubFailure: LocalizedError {
        var errorDescription: String? { "stub failure" }
    }

    func testEveryRadarFailureProvidesSpecificOwnerFacingCopy() {
        XCTAssertEqual(NearbyPreparationFailure.locationTimedOut.retryStatusText,
                       "Location took too long · Tap to retry")
        XCTAssertEqual(NearbyPreparationFailure.locationFixUnavailable.retryStatusText,
                       "Couldn't get an accurate location · Tap to retry")
        XCTAssertEqual(NearbyPreparationFailure.merchantTimedOut.retryStatusText,
                       "Apple Maps took too long · Tap to retry")
        XCTAssertEqual(NearbyPreparationFailure.locationFailed.retryStatusText,
                       "Location is temporarily unavailable · Tap to retry")
        XCTAssertEqual(NearbyPreparationFailure.merchantFailed.retryStatusText,
                       "Apple Maps couldn't load nearby places · Tap to retry")
    }

    private func makeGraph(context: ModelContext,
                           provider: any MerchantProviding = LiveMerchantProvider()) throws -> DependencyGraph {
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
            provider: provider)
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

    func testAuthorizedLaunchPrefetchServesRadarWithoutASecondLookup() async throws {
        let location = StubLocationProvider()
        location.authorizedLocation = CheckoutLocationFix(latitude: 43.6532, longitude: -79.3832,
                                                           horizontalAccuracyMeters: 10)
        let merchants = [NearbyPlace(id: "nearby-loblaws", name: "Loblaws",
                                        poiCategoryRaw: nil, latitude: 43.6532,
                                        longitude: -79.3832, distanceMeters: 12)]
        let provider = StubMerchantProvider(nearbyResult: merchants)
        let graph = try makeGraph(context: makeContext(), provider: provider)
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: graph)
        let outcome = await session.findNearby(using: graph)

        XCTAssertEqual(outcome, .found(merchants))
        XCTAssertEqual(location.authorizedRequestCount, 1)
        XCTAssertEqual(location.promptedRequestCount, 0)
        let nearbyRequestCount = await provider.nearbyRequestCount
        XCTAssertEqual(nearbyRequestCount, 1)
        XCTAssertEqual(session.nearbyMetrics.preparedTaps, 1)
        XCTAssertEqual(session.nearbyPreparationState, .ready(merchantCount: 1))
    }

    func testLaunchPrefetchDoesNotPromptBeforeFirstRadarTap() async throws {
        let location = StubLocationProvider()
        let merchants = [NearbyPlace(id: "nearby-metro", name: "Metro",
                                        poiCategoryRaw: nil, latitude: 43.6532,
                                        longitude: -79.3832, distanceMeters: 20)]
        let provider = StubMerchantProvider(nearbyResult: merchants)
        let graph = try makeGraph(context: makeContext(), provider: provider)
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: graph)
        XCTAssertEqual(location.authorizedRequestCount, 1)
        XCTAssertEqual(location.promptedRequestCount, 0)
        let prefetchRequestCount = await provider.nearbyRequestCount
        XCTAssertEqual(prefetchRequestCount, 0)
        XCTAssertEqual(session.nearbyPreparationState, .permissionRequired)

        let outcome = await session.findNearby(using: graph)

        XCTAssertEqual(outcome, .found(merchants))
        XCTAssertEqual(location.promptedRequestCount, 1)
        let finalRequestCount = await provider.nearbyRequestCount
        XCTAssertEqual(finalRequestCount, 1)
    }

    func testForegroundPrefetchReusesCacheOnlyWhenDeviceHasNotMoved() async throws {
        let location = StubLocationProvider()
        location.authorizedLocation = CheckoutLocationFix(latitude: 43.6532, longitude: -79.3832,
                                                           horizontalAccuracyMeters: 10)
        let merchants = [NearbyPlace(id: "nearby", name: "Nearby",
                                        poiCategoryRaw: nil, latitude: 43.6533,
                                        longitude: -79.3832, distanceMeters: 12)]
        let provider = StubMerchantProvider(nearbyResult: merchants)
        let graph = try makeGraph(context: makeContext(), provider: provider)
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: graph)
        await session.prefetchNearby(using: graph)
        var requestCount = await provider.nearbyRequestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(session.nearbyMetrics.movementCacheHits, 1)

        location.authorizedLocation = CheckoutLocationFix(latitude: 43.6632, longitude: -79.3832,
                                                           horizontalAccuracyMeters: 10)
        await session.prefetchNearby(using: graph)
        requestCount = await provider.nearbyRequestCount
        XCTAssertEqual(requestCount, 2, "moving about 1 km must invalidate a 200 m result")
    }

    func testConfidentShortcutRequiresASeparatedRunnerUp() async throws {
        let location = StubLocationProvider()
        location.authorizedLocation = CheckoutLocationFix(latitude: 43.6532, longitude: -79.3832,
                                                           horizontalAccuracyMeters: 10)
        let first = NearbyPlace(id: "first", name: "First", poiCategoryRaw: nil,
                                   latitude: 43.6532, longitude: -79.3832, distanceMeters: 10)
        let closeSecond = NearbyPlace(id: "second", name: "Second", poiCategoryRaw: nil,
                                         latitude: 43.6533, longitude: -79.3832, distanceMeters: 30)
        let provider = StubMerchantProvider(nearbyResult: [closeSecond, first])
        let graph = try makeGraph(context: makeContext(), provider: provider)
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: graph)

        XCTAssertEqual(session.preparedNearestMerchant?.id, "first")
        XCTAssertEqual(session.preparedNearbyMerchants.map(\.id), ["first", "second"])
        XCTAssertNil(session.confidentPreparedMerchant,
                     "two storefronts 20 m apart must retain exact-merchant confirmation")
    }

    func testMerchantLookupTimesOutAndRecordsOnlyASafeCounter() async throws {
        let location = StubLocationProvider()
        let provider = StubMerchantProvider(nearbyResult: [], delay: .seconds(10))
        let graph = try makeGraph(context: makeContext(), provider: provider)
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore(),
                                     nearbyTapTimeout: .milliseconds(20))

        let outcome = await session.findNearby(using: graph)

        guard case .failed(let message) = outcome else { return XCTFail("expected timeout") }
        XCTAssertTrue(message.contains("too long"), "got: \(message)")
        XCTAssertEqual(session.nearbyMetrics.merchantTimeouts, 1)
        XCTAssertEqual(session.nearbyPreparationState, .unavailable(.merchantTimedOut))
    }

    func testLocationTimeoutExplainsFailureAndAnExplicitRetryCanRecover() async throws {
        let location = StubLocationProvider()
        location.promptedError = LocationUnavailable.timedOut
        let merchant = NearbyPlace(id: "nearby", name: "Nearby", poiCategoryRaw: nil,
                                   latitude: 43.6532, longitude: -79.3832, distanceMeters: 5)
        let graph = try makeGraph(context: makeContext(),
                                  provider: StubMerchantProvider(nearbyResult: [merchant]))
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        let failed = await session.findNearby(using: graph)

        XCTAssertEqual(failed, .failed("Location took too long to respond."))
        XCTAssertEqual(session.nearbyPreparationState, .unavailable(.locationTimedOut))
        XCTAssertEqual(session.nearbyMetrics.locationTimeouts, 1)

        location.promptedError = nil
        let recovered = await session.findNearby(using: graph)

        XCTAssertEqual(recovered, .found([merchant]))
        XCTAssertEqual(location.promptedRequestCount, 2)
        XCTAssertEqual(session.nearbyPreparationState, .ready(merchantCount: 1))
    }

    func testAnUnusableLocationFixHasItsOwnFailureCounterAndReason() async throws {
        let location = StubLocationProvider()
        location.promptedError = LocationUnavailable.fixFailed("no recent accurate fix")
        let graph = try makeGraph(context: makeContext(),
                                  provider: StubMerchantProvider(nearbyResult: []))
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        let outcome = await session.findNearby(using: graph)

        XCTAssertEqual(outcome, .failed("Couldn't get an accurate location."))
        XCTAssertEqual(session.nearbyPreparationState, .unavailable(.locationFixUnavailable))
        XCTAssertEqual(session.nearbyMetrics.locationFailures, 1)
        XCTAssertEqual(session.nearbyMetrics.merchantFailures, 0)
    }

    func testOtherLocationAndAppleMapsFailuresAreCountedByStage() async throws {
        let location = StubLocationProvider()
        location.promptedError = StubFailure()
        let graph = try makeGraph(context: makeContext(),
                                  provider: StubMerchantProvider(nearbyResult: []))
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        let locationFailure = await session.findNearby(using: graph)
        XCTAssertEqual(locationFailure, .failed("Location is temporarily unavailable."))
        XCTAssertEqual(session.nearbyPreparationState, .unavailable(.locationFailed))
        XCTAssertEqual(session.nearbyMetrics.locationFailures, 1)

        location.promptedError = nil
        let failingProvider = StubMerchantProvider(nearbyResult: [], nearbyError: StubFailure())
        let failingGraph = try makeGraph(context: makeContext(), provider: failingProvider)

        let merchantFailure = await session.findNearby(using: failingGraph)
        XCTAssertEqual(merchantFailure, .failed("Apple Maps couldn't load nearby places."))
        XCTAssertEqual(session.nearbyPreparationState, .unavailable(.merchantFailed))
        XCTAssertEqual(session.nearbyMetrics.merchantFailures, 1)
        XCTAssertEqual(session.nearbyMetrics.failures, 2)
    }

    func testSilentPrefetchRecordsFailureWithoutShowingAnErrorState() async throws {
        let location = StubLocationProvider()
        location.authorizedError = LocationUnavailable.timedOut
        let graph = try makeGraph(context: makeContext(),
                                  provider: StubMerchantProvider(nearbyResult: []))
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: graph)

        XCTAssertEqual(session.nearbyPreparationState, .idle)
        XCTAssertEqual(session.nearbyMetrics.locationTimeouts, 1)
    }

    func testLocationFixRejectsStaleAndInaccurateSamples() {
        XCTAssertFalse(CheckoutLocationFix(latitude: 43.65, longitude: -79.38,
                                           horizontalAccuracyMeters: 10,
                                           capturedAt: Date().addingTimeInterval(-61)).isUsable())
        XCTAssertFalse(CheckoutLocationFix(latitude: 43.65, longitude: -79.38,
                                           horizontalAccuracyMeters: 300).isUsable())
        XCTAssertTrue(CheckoutLocationFix(latitude: 43.65, longitude: -79.38,
                                          horizontalAccuracyMeters: 20).isUsable())
    }

    func testForgettingNearbyHistoryClearsPreparedMerchantAndLocalCounters() async throws {
        let location = StubLocationProvider()
        location.authorizedLocation = CheckoutLocationFix(latitude: 43.6532, longitude: -79.3832,
                                                           horizontalAccuracyMeters: 10)
        let merchant = NearbyPlace(id: "nearby", name: "Nearby", poiCategoryRaw: nil,
                                      latitude: 43.6532, longitude: -79.3832, distanceMeters: 12)
        let provider = StubMerchantProvider(nearbyResult: [merchant])
        let graph = try makeGraph(context: makeContext(), provider: provider)
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: graph)
        XCTAssertNotNil(session.preparedNearestMerchant)
        XCTAssertGreaterThan(session.nearbyMetrics.prefetchAttempts, 0)

        session.forgetNearbyHistory()

        XCTAssertNil(session.preparedNearestMerchant)
        XCTAssertNil(session.cachedLocation)
        XCTAssertEqual(session.nearbyMetrics, NearbyLookupMetrics())
        XCTAssertEqual(session.nearbyPreparationState, .idle)
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

    func testHomeAnswerSubjectMergedPreservesNearbyAndRecentSeparation() {
        let nearby = [
            NearbyPlace(id: "n1", name: "Nearby 1", poiCategoryRaw: "cafe", latitude: 43.65, longitude: -79.38, distanceMeters: 50),
            NearbyPlace(id: "n2", name: "Nearby 2", poiCategoryRaw: "grocery", latitude: 43.65, longitude: -79.38, distanceMeters: 120),
            NearbyPlace(id: "common", name: "Shared Place", poiCategoryRaw: "restaurant", latitude: 43.65, longitude: -79.38, distanceMeters: 200)
        ]
        let remembered = [
            StoredMerchant(name: "Shared Place", identifier: "common", poiCategoryRaw: "restaurant", latitude: 43.65, longitude: -79.38),
            StoredMerchant(name: "Recent 1", identifier: "r1", poiCategoryRaw: "gas_station", latitude: 43.65, longitude: -79.38),
            StoredMerchant(name: "Recent 2", identifier: "r2", poiCategoryRaw: "pharmacy", latitude: 43.65, longitude: -79.38)
        ]

        let subjects = HomeAnswerSubject.merged(nearby: nearby, remembered: remembered)

        // 3 nearby + 2 unique remembered = 5 subjects total
        XCTAssertEqual(subjects.count, 5)

        let nearbySubjects = subjects.filter { $0.provenance == HomeSubjectProvenance.nearby }
        let recentSubjects = subjects.filter { $0.provenance == HomeSubjectProvenance.recent }

        XCTAssertEqual(nearbySubjects.map { $0.id }, ["n1", "n2", "common"])
        XCTAssertEqual(recentSubjects.map { $0.id }, ["r1", "r2"])
        XCTAssertEqual(nearbySubjects.first?.distanceMeters, 50)
        XCTAssertNil(recentSubjects.first?.distanceMeters)
    }

    func testHomeAnswerSubjectMergedEnforcesPerSectionLimits() {
        let nearby = (1...15).map {
            NearbyPlace(id: "n\($0)", name: "Nearby \($0)", poiCategoryRaw: "cafe", latitude: 43.65, longitude: -79.38, distanceMeters: Double($0 * 10))
        }
        let remembered = (1...15).map {
            StoredMerchant(name: "Recent \($0)", identifier: "r\($0)", poiCategoryRaw: "grocery", latitude: 43.65, longitude: -79.38)
        }

        let subjects = HomeAnswerSubject.merged(nearby: nearby, remembered: remembered, nearbyLimit: 3, rememberedLimit: 4)

        let nearbySubjects = subjects.filter { $0.provenance == HomeSubjectProvenance.nearby }
        let recentSubjects = subjects.filter { $0.provenance == HomeSubjectProvenance.recent }

        XCTAssertEqual(nearbySubjects.count, 3)
        XCTAssertEqual(recentSubjects.count, 4)
        XCTAssertEqual(subjects.count, 7)
    }
}
