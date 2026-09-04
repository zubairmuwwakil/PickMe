import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

final class WalletGPSIdentityIntegrationTests: XCTestCase {
    func testEnrichAutomaticPurchaseFeedsTheIdentityLedger() throws {
        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState(),
                                      context: ModelContext(container))

        // Unique per run so the process-wide learning store can never make this capture look known
        // before the test starts. Four suffix characters keep the compact-name overlap with
        // "Pizza Pizza" above resolveWalletMerchant's 60% identity threshold.
        let alias = "PIZZAPIZZA\(UUID().uuidString.prefix(4))"
        XCTAssertNil(MerchantMCCSeedCatalogue.canonicalMatch(merchantName: alias))

        let feedback = WalletFeedback(
            eventId: "gps-integration-\(UUID().uuidString)",
            capturedAt: Date(),
            merchantRaw: alias,
            amountMinor: 2400,
            currency: "CAD",
            cardRaw: "Amex Cobalt",
            resolvedCardId: "amex-cobalt",
            verdict: "unknown",
            warning: nil,
            latitude: 43.65,
            longitude: -79.38)
        let purchase = try XCTUnwrap(service.ingestAutomaticCaptures(from: [feedback]).first)
        XCTAssertNil(purchase.displayCategory,
                     "fixture must require GPS enrichment rather than static merchant recognition")

        let poi = NearbyPlace(id: "mapkit-pizza-pizza", placeID: "apple-pizza-pizza",
                              name: "Pizza Pizza", poiCategoryRaw: "MKPOICategoryRestaurant",
                              latitude: 43.6501, longitude: -79.3801, distanceMeters: 20)
        let resolution = try XCTUnwrap(resolveWalletMerchant(
            capturedName: purchase.displayMerchant,
            nearbyMerchants: [poi]))

        let before = MerchantMCCIdentityLearningStore.shared.evidenceCount(for: alias)
        try service.enrichAutomaticPurchase(purchase, with: resolution)
        let after = MerchantMCCIdentityLearningStore.shared.evidenceCount(for: alias)

        XCTAssertEqual(after, before + 1)
        XCTAssertEqual(purchase.displayCategory, "dining")
        XCTAssertNil(MerchantMCCIdentityLearningStore.shared.match(merchantName: alias),
                     "one GPS-confirmed transaction is evidence, not enough to activate an alias")
    }
}
