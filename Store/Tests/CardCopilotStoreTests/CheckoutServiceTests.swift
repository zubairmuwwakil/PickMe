import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

/// Task 5's composition layer: confirmed merchant + mapped category + amount → engine →
/// rendered outcome + immutably persisted prediction. Owner state is the LIVE seed (MR at
/// its 1.0¢ floor) — this service is what the real app runs, not a pinned spec.
final class CheckoutServiceTests: XCTestCase {
    var container: ModelContainer!
    var service: CheckoutService!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredObservation.self, StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                  ownerState: try SeedLoader.loadOwnerState(),
                                  context: ModelContext(container))
    }

    private func merchant(_ name: String, poi: String?, id: String = "poi-1") -> NearbyMerchant {
        NearbyMerchant(id: id, name: name, poiCategoryRaw: poi,
                       latitude: 43.65, longitude: -79.38, distanceMeters: 40)
    }

    // MARK: brand canonicalization for engine predicates

    func testCanonicalEngineBrandMatchesEngineTokens() {
        XCTAssertEqual(canonicalEngineBrand("Costco Wholesale #536"), "costco")
        XCTAssertEqual(canonicalEngineBrand("Walmart Supercentre"), "walmart")
        XCTAssertEqual(canonicalEngineBrand("Canadian Tire #045"), "canadian-tire")
        XCTAssertEqual(canonicalEngineBrand("Marriott Downtown"), "marriott")
        XCTAssertNil(canonicalEngineBrand("Fresh Foods Market"),
                     "unknown merchants pass no brand — engine predicates must not fire")
    }

    // MARK: single-outcome flow

    func testUnambiguousGroceryProducesSingleOutcomeAndPersists() throws {
        let result = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                           amountCad: 140, asOf: asOf)
        guard case .single(let rec) = result.outcome else {
            return XCTFail("expected single outcome, got \(result.outcome)")
        }
        XCTAssertEqual(rec.winner.cardId, "amex-cobalt")
        XCTAssertEqual(rec.winner.netValueCad, 7.00, accuracy: 0.005)

        let stored = try XCTUnwrap(try service.log.allPredictions().first)
        XCTAssertEqual(stored.predictedCategory, "grocery")
        XCTAssertEqual(stored.winnerCardId, "amex-cobalt")
        XCTAssertEqual(stored.amountCad ?? .nan, 140, accuracy: 0.005)
        XCTAssertEqual(stored.defaultCardValueCad ?? .nan, 2.80, accuracy: 0.005)
        XCTAssertEqual(stored.valuationCentsPerPoint ?? .nan, 1.0, accuracy: 0.005,
                       "the valuation in force must be snapshotted with the prediction")
        XCTAssertFalse(stored.headline.isEmpty)
    }

    // MARK: fork behaviour

    func testWalmartForkSplitsWhenBranchesDisagree() throws {
        let result = try service.recommend(merchant: merchant("Walmart Supercentre",
                                                              poi: "MKPOICategoryFoodMarket"),
                                           amountCad: 100, asOf: asOf)
        guard case .fork(let branches) = result.outcome else {
            return XCTFail("Walmart must fork — the dossier forbids hard-coding it either way")
        }
        XCTAssertEqual(branches.map(\.category), ["grocery", "other"])
        XCTAssertEqual(branches[0].recommendation.winner.cardId, "amex-cobalt",
                       "if it codes as grocery, Cobalt 5x wins even at the floor")
        XCTAssertEqual(branches[1].recommendation.winner.cardId, "wealthsimple-vip",
                       "if it codes as general merchandise, the default holds")
    }

    func testGasForkCollapsesWhenBothBranchesAgree() throws {
        // At the 1.0¢ floor, Cobalt 2x gas ties WS 2% — the default wins BOTH branches,
        // so showing a fork would be noise. Collapse to single, keep the ambiguity flag.
        let result = try service.recommend(merchant: merchant("Esso", poi: "MKPOICategoryGasStation"),
                                           amountCad: 70, asOf: asOf)
        guard case .single(let rec) = result.outcome else {
            return XCTFail("agreeing branches must collapse")
        }
        XCTAssertEqual(rec.winner.cardId, "wealthsimple-vip")
        XCTAssertTrue(result.categoryWasAmbiguous,
                      "collapse hides the fork, not the uncertainty — reconcile still needs it")
    }

    // MARK: brand-known acceptance

    func testCostcoExcludesNonMastercardCards() throws {
        let result = try service.recommend(merchant: merchant("Costco Wholesale", poi: nil),
                                           amountCad: 220, asOf: asOf)
        guard case .single(let rec) = result.outcome else {
            return XCTFail("Costco is a brand prior — no fork")
        }
        XCTAssertEqual(rec.winner.cardId, "rogers-red-we",
                       "brand-known acceptance: Costco takes Mastercard only, so WS/Amex are out")
        XCTAssertTrue(rec.defaultNotAccepted)

        let stored = try XCTUnwrap(try service.log.allPredictions().first)
        XCTAssertEqual(stored.defaultCardValueCad ?? .nan, stored.winnerValueCad, accuracy: 0.005,
                       "when the default card is not accepted, value recovered contributes zero")
    }

    // MARK: amount estimation

    func testSkippedAmountUsesCategoryEstimateAndStoresNil() throws {
        let result = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                           amountCad: nil, asOf: asOf)
        XCTAssertTrue(result.amountWasEstimated)
        XCTAssertEqual(result.effectiveAmountCad, 60, accuracy: 0.005,
                       "grocery estimate per the category table")
        let stored = try XCTUnwrap(try service.log.allPredictions().first)
        XCTAssertNil(stored.amountCad,
                     "an estimated amount is not evidence — the value-recovered counter must skip it")
    }

    // MARK: merchant upsert

    func testRecommendUpsertsMerchantWithoutConfirming() throws {
        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket",
                                                     id: "poi-loblaws"), amountCad: 20, asOf: asOf)
        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket",
                                                     id: "poi-loblaws"), amountCad: 30, asOf: asOf)
        let merchants = try service.knownMerchants()
        XCTAssertEqual(merchants.count, 1, "same POI id must upsert, not duplicate")
        XCTAssertNil(merchants.first?.confirmedCategory,
                     "recommending is not confirming — only reconcile promotes a merchant")
        XCTAssertEqual(merchants.first?.confirmationCount, 0)
    }
}
