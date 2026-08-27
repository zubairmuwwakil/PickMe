import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

final class ProvenanceCaptureTests: XCTestCase {

    /// Mirrors the construction in `CheckoutServiceTests.setUpWithError` exactly — the live seed,
    /// not a pinned fixture, because this test asserts on the release the build actually ships.
    private func makeService() throws -> (CheckoutService, ModelContext) {
        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
                StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState(),
                                      context: context)
        return (service, context)
    }

    private func merchant(_ name: String, poi: String?) -> NearbyMerchant {
        NearbyMerchant(id: "poi-1", name: name, poiCategoryRaw: poi,
                       latitude: 43.65, longitude: -79.38, distanceMeters: 40)
    }

    func testRecommendStampsTheContractRelease() throws {
        let (service, context) = try makeService()
        let expected = try SeedLoader.loadContractRelease()

        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                  amountCad: 140, asOf: "2026-08-26")

        let stored = try context.fetch(FetchDescriptor<StoredPrediction>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].contractRelease, expected.release)
        XCTAssertEqual(stored[0].contractDigest, expected.digest)
    }

    func testRecommendFreezesTheWinningRule() throws {
        let (service, context) = try makeService()

        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                  amountCad: 140, asOf: "2026-08-26")

        let stored = try context.fetch(FetchDescriptor<StoredPrediction>())
        let blob = try XCTUnwrap(stored[0].frozenInputs, "the winning rule was not frozen")
        let snapshot = try JSONDecoder().decode(ScoredRuleSnapshot.self, from: blob)

        XCTAssertEqual(snapshot.cardId, stored[0].winnerCardId)
        XCTAssertEqual(snapshot.appliedRule?.ruleId, stored[0].winnerRuleId)
        XCTAssertEqual(snapshot.asOf, "2026-08-26")
        XCTAssertEqual(snapshot.netValueCad, stored[0].winnerValueCad, accuracy: 0.001)
    }
}
