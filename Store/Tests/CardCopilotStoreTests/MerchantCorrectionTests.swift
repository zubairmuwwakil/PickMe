import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

/// Confirming a merchant with no purchase behind it — the "not this store, that one" correction.
///
/// It goes through `PredictionLog`'s own confirmation writer rather than a second one. That column
/// is what promotes a merchant to `.verified` and its unscaled threshold, and two ways to write it
/// is two ways for them to disagree.
final class MerchantCorrectionTests: XCTestCase {
    private var container: ModelContainer!
    private var service: CheckoutService!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                  ownerState: try SeedLoader.loadOwnerState(),
                                  context: ModelContext(container))
    }

    private func shoppers(id: String = "poi.shoppers.1") -> NearbyMerchant {
        NearbyMerchant(id: id, name: "Shoppers Drug Mart",
                       poiCategoryRaw: "MKPOICategoryPharmacy",
                       latitude: 45, longitude: -75, distanceMeters: 40)
    }

    func testConfirmingAMerchantWithNoHistoryCreatesOneVerifiedRow() throws {
        try service.log.confirmMerchant(shoppers(), category: "drugStore")

        let merchants = try service.knownMerchants()
        XCTAssertEqual(merchants.count, 1)
        XCTAssertEqual(merchants[0].confirmedCategory, "drugStore")
        XCTAssertEqual(merchants[0].confirmationCount, 1)
        XCTAssertEqual(merchants[0].identifier, "poi.shoppers.1")
        XCTAssertEqual(merchants[0].categoryConfidenceScore,
                       ConfidenceSource.ownerConfirmedTerminal.defaultScore)
    }

    /// The point of going through the existing writer: the next checkout at this terminal reads
    /// the confirmation and stops guessing.
    func testAConfirmedMerchantIsWhatTheNextCheckoutScores() throws {
        try service.log.confirmMerchant(shoppers(), category: "drugStore")

        let result = try service.recommend(merchant: shoppers(), amountCad: 34,
                                           asOf: "2026-09-03")
        XCTAssertEqual(result.prediction.category, "drugStore")
        XCTAssertEqual(result.prediction.confidenceSource, .ownerConfirmedTerminal)
    }

    /// One merchant, not two. A correction at a terminal already known must update that row rather
    /// than insert a rival with the same identifier.
    func testConfirmingAKnownMerchantUpdatesItRatherThanInsertingASecond() throws {
        _ = try service.recommend(merchant: shoppers(), amountCad: 34, asOf: "2026-09-03")
        XCTAssertEqual(try service.knownMerchants().count, 1)

        try service.log.confirmMerchant(shoppers(), category: "drugStore")

        let merchants = try service.knownMerchants()
        XCTAssertEqual(merchants.count, 1)
        XCTAssertEqual(merchants[0].confirmedCategory, "drugStore")
    }

    /// A repeat confirmation of the same category is a streak, exactly as a reconciled purchase's
    /// is — that is what `.repeatedTerminal` claims, and the correction may not claim it on
    /// weaker evidence than the purchase path does.
    func testRepeatingTheSameConfirmationBuildsTheStreak() throws {
        try service.log.confirmMerchant(shoppers(), category: "drugStore")
        try service.log.confirmMerchant(shoppers(), category: "drugStore")

        let merchant = try XCTUnwrap(try service.knownMerchants().first)
        XCTAssertEqual(merchant.confirmationCount, 2)
        XCTAssertEqual(merchant.categoryConfidenceScore,
                       ConfidenceSource.repeatedTerminal.defaultScore)
    }

    /// A terminal that re-codes starts over rather than accruing confidence its own evidence
    /// contradicts. Same rule as `promoteMerchant`, because it is the same code.
    func testChangingTheConfirmedCategoryRestartsTheStreak() throws {
        try service.log.confirmMerchant(shoppers(), category: "drugStore")
        try service.log.confirmMerchant(shoppers(), category: "grocery")

        let merchant = try XCTUnwrap(try service.knownMerchants().first)
        XCTAssertEqual(merchant.confirmedCategory, "grocery")
        XCTAssertEqual(merchant.confirmationCount, 1)
    }

    /// "Other" is the absence of a category, not a category. Writing it as confirmed would promote
    /// a merchant to `.verified` on the strength of knowing nothing about it, and the unscaled
    /// threshold that promotion buys would then be spent on a guess.
    func testAnUnknownCategoryIsNotConfirmed() throws {
        try service.log.confirmMerchant(shoppers(), category: "other")

        XCTAssertTrue(try service.knownMerchants().isEmpty)
    }
}
