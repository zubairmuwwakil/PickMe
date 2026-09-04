import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

final class CheckoutMCCDecisionQualityWiringTests: XCTestCase {
    func testCheckoutMeasuresOnlyDecisionsActuallySuppliedByTheMCCGraph() throws {
        let suite = "CheckoutMCCDecisionQualityWiringTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let metrics = CategoryResolutionMetricsStore(defaults: defaults, key: "metrics")

        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState(),
                                      context: ModelContext(container),
                                      metrics: metrics)

        // No POI category and no literal transaction MCC: the seeded graph is the answer source.
        let metro = NearbyPlace(id: "quality:metro", name: "Metro", poiCategoryRaw: nil,
                                latitude: 43.6532, longitude: -79.3832, distanceMeters: nil)

        // Arrival alerts reuse checkout scoring but may repeat in the background. They must not
        // overweight a frequent merchant in the explicit purchase-decision quality denominator.
        let arrivalResult = try service.recommend(merchant: metro, amountCad: 60,
                                                  asOf: "2026-09-04",
                                                  purchaseSource: .arrivalAlert)
        XCTAssertTrue(arrivalResult.prediction.rawCategory?.hasPrefix("merchantMccGraph:") == true)
        XCTAssertEqual(metrics.snapshot.mccGraphDecisionEvaluations, 0)

        let graphResult = try service.recommend(merchant: metro, amountCad: 60,
                                                asOf: "2026-09-04")
        XCTAssertTrue(graphResult.prediction.rawCategory?.hasPrefix("merchantMccGraph:") == true)
        XCTAssertEqual(metrics.snapshot.mccGraphDecisionEvaluations, 1)

        // A literal transaction MCC outranks the graph. It must not pollute the graph-quality
        // denominator even though the merchant name itself may also exist in the seed catalogue.
        let observedMetro = NearbyPlace(id: "quality:metro:observed", name: "Metro",
                                        poiCategoryRaw: nil, merchantCategoryCode: 5411,
                                        latitude: 43.6532, longitude: -79.3832,
                                        distanceMeters: nil)
        let observedResult = try service.recommend(merchant: observedMetro, amountCad: 60,
                                                   asOf: "2026-09-04")
        XCTAssertEqual(observedResult.prediction.confidenceSource, .observedMcc)
        XCTAssertEqual(metrics.snapshot.mccGraphDecisionEvaluations, 1,
                       "observed-MCC checkouts are not graph decisions")
    }
}
