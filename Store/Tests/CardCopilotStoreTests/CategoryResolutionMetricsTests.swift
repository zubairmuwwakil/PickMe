import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

/// Which rung of the ladder actually answers, counted on device.
///
/// Nobody knew this number, and not knowing it is how a places-dataset import came to look like
/// the obvious fix — the pack was assumed to be the bottleneck without evidence that it was.
/// Before growing any data, count where resolution currently lands.
final class CategoryResolutionMetricsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: CategoryResolutionMetricsStore!

    override func setUp() {
        super.setUp()
        let name = "category-resolution-metrics-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)
        store = CategoryResolutionMetricsStore(defaults: defaults, key: "test.v1")
    }

    func testStartsEmpty() {
        XCTAssertEqual(store.snapshot.resolutionsByRung, [:])
        XCTAssertEqual(store.snapshot.totalResolutions, 0)
    }

    func testCountsTheRungThatAnswered() {
        store.record(.resolved(rung: .brandPrior, forked: false))
        store.record(.resolved(rung: .brandPrior, forked: false))
        store.record(.resolved(rung: .mapKitCategory, forked: true))

        XCTAssertEqual(store.snapshot.resolutionsByRung[ConfidenceSource.brandPrior.rawValue], 2)
        XCTAssertEqual(store.snapshot.resolutionsByRung[ConfidenceSource.mapKitCategory.rawValue], 1)
        XCTAssertEqual(store.snapshot.totalResolutions, 3)
    }

    /// A forked answer is not a failure — the engine collapses it when the branches agree — but it
    /// is the population that would benefit from better evidence, so it is counted separately.
    func testCountsForksSeparatelyFromFailures() {
        store.record(.resolved(rung: .mapKitCategory, forked: true))
        store.record(.resolved(rung: .observedMcc, forked: false))

        XCTAssertEqual(store.snapshot.forkedResolutions, 1)
        XCTAssertEqual(store.snapshot.unresolved, 0)
    }

    func testCountsWhatNothingCouldAnswer() {
        store.record(.resolved(rung: .fallback, forked: false))
        XCTAssertEqual(store.snapshot.unresolved, 1)
    }

    func testCountsWalletEnrichmentOutcomes() {
        store.record(.walletEnrichmentAttempted)
        store.record(.walletEnrichmentAttempted)
        store.record(.walletEnrichmentMatched)
        store.record(.walletEnrichmentSkippedWithoutLocation)

        let snapshot = store.snapshot
        XCTAssertEqual(snapshot.walletEnrichmentAttempts, 2)
        XCTAssertEqual(snapshot.walletEnrichmentMatches, 1)
        XCTAssertEqual(snapshot.walletEnrichmentSkippedWithoutLocation, 1)
    }

    /// The whole point of the counter: an evidence-based answer to "is the pack the bottleneck?"
    func testReportsTheShareOfResolutionsNothingCouldAnswer() {
        store.record(.resolved(rung: .brandPrior, forked: false))
        store.record(.resolved(rung: .brandPrior, forked: false))
        store.record(.resolved(rung: .fallback, forked: false))
        store.record(.resolved(rung: .fallback, forked: false))

        XCTAssertEqual(try XCTUnwrap(store.snapshot.unresolvedShare), 0.5, accuracy: 0.0001)
    }

    func testUnresolvedShareIsNilBeforeAnythingIsRecorded() {
        XCTAssertNil(store.snapshot.unresolvedShare)
    }

    // MARK: - Wiring

    /// Counting is worthless if the counter is not on the path that decides. Scoring a checkout
    /// must record which rung answered.
    func testScoringRecordsTheRungThatAnswered() throws {
        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState(),
                                      context: ModelContext(container),
                                      metrics: store)

        let netflix = try XCTUnwrap(CanadianMerchantPreIndex.all.first { $0.name == "Netflix" })
        _ = try service.recommend(merchant: NearbyMerchant(preIndexed: netflix),
                                  amountCad: 20, asOf: "2026-08-20")

        XCTAssertEqual(store.snapshot.totalResolutions, 1)
        XCTAssertEqual(store.snapshot.resolutionsByRung[ConfidenceSource.brandPrior.rawValue], 1)
    }

    /// The path where "my Apple Pay purchase has no category" actually happens. A capture with no
    /// coordinates can never reach location enrichment, so it is counted separately from one that
    /// was looked up and missed — different problems, different owners.
    func testAnUnresolvableWalletCaptureWithNoFixIsCountedAsSkipped() throws {
        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState(),
                                      context: ModelContext(container),
                                      metrics: store)

        let feedback = WalletFeedback(
            eventId: "wallet-unknown-1", capturedAt: Date(),
            merchantRaw: "SQ *BLUE DOOR", merchantNormalized: nil,
            amountMinor: 1850, currency: "CAD", cardRaw: "Amex Cobalt",
            resolvedCardId: "amex-cobalt", verdict: "best", warning: nil)

        _ = try service.ingestAutomaticCaptures(from: [feedback])

        XCTAssertEqual(store.snapshot.resolutionsByRung[ConfidenceSource.fallback.rawValue], 1,
                       "an unrecognised descriptor with no POI signal reaches no rung")
        XCTAssertEqual(store.snapshot.walletEnrichmentSkippedWithoutLocation, 1)
    }
}
