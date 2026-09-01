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
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self, StoredMerchant.self,
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
        XCTAssertEqual(stored.scoredAmountCad ?? .nan, 140, accuracy: 0.005)
        XCTAssertEqual(stored.defaultCardValueCad ?? .nan, 2.80, accuracy: 0.005)
        XCTAssertEqual(stored.valuationCentsPerPoint ?? .nan, 1.0, accuracy: 0.005,
                       "the valuation in force must be snapshotted with the prediction")
        XCTAssertFalse(stored.headline.isEmpty)
    }

    func testPredictionSnapshotsWinnerRewardUnitsAndUnitKind() throws {
        // Metric #2 compares posted units against what the app predicted AT THE TIME. Without
        // this snapshot the only way to check the arithmetic would be to re-run today's engine
        // against an old row — which measures today's catalogue, not the advice that was given.
        let result = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                           amountCad: 140, asOf: asOf)
        guard case .single(let rec) = result.outcome else {
            return XCTFail("expected single outcome, got \(result.outcome)")
        }
        let stored = try XCTUnwrap(try service.log.allPredictions().first)
        XCTAssertEqual(stored.predictedRewardUnits ?? .nan, rec.winner.rewardUnits, accuracy: 0.0001)
        XCTAssertEqual(stored.predictedRewardUnits ?? .nan, 700, accuracy: 0.0001,
                       "Cobalt earns 5x on $140 of grocery")
        XCTAssertEqual(stored.predictedRewardUnitKind, "point",
                       "the unit decides the comparison tolerance — points post as integers")
    }

    func testCashBackWinnerSnapshotsDollarUnits() throws {
        _ = try service.recommend(merchant: merchant("Costco Wholesale", poi: nil),
                                  amountCad: 220, asOf: asOf)
        let stored = try XCTUnwrap(try service.log.allPredictions().first)
        XCTAssertEqual(stored.predictedRewardUnitKind, "cad",
                       "cash back posts to the cent — a 1.0-unit tolerance would hide a dollar of error")
        XCTAssertEqual(stored.predictedRewardUnits ?? .nan, stored.winnerValueCad, accuracy: 0.0001,
                       "a cash-back card's units ARE dollars")
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
        XCTAssertNil(stored.scoredAmountCad,
                     "an estimated amount is not evidence — the value-recovered counter must skip it")
    }

    // MARK: merchant upsert

    func testMapKitEnrichmentCategorizesAutomaticCaptureWithoutInventingPrediction() throws {
        let feedback = WalletFeedback(
            eventId: "wallet-1", capturedAt: Date(), merchantRaw: "Mom's Kitchen (Ajax)",
            amountMinor: 4743, currency: "CAD", cardRaw: "Cobalt",
            resolvedCardId: "amex-cobalt", verdict: "unknown", warning: nil,
            latitude: 43.85, longitude: -79.02)
        let purchase = try XCTUnwrap(service.ingestAutomaticCaptures(from: [feedback]).first)
        let poi = merchant("Mom's Kitchen", poi: "MKPOICategoryRestaurant",
                           id: "mapkit-moms-kitchen")
        let resolution = try XCTUnwrap(resolveWalletMerchant(
            capturedName: purchase.displayMerchant, nearbyMerchants: [poi]))

        try service.enrichAutomaticPurchase(purchase, with: resolution)

        XCTAssertNil(purchase.prediction)
        XCTAssertEqual(purchase.displayCategory, "dining")
        XCTAssertEqual(purchase.categoryConfidence, .mapKitCategory)
        XCTAssertEqual(purchase.merchantIdentifier, poi.id)
        XCTAssertEqual(try service.knownMerchants().first?.poiCategoryRaw,
                       "MKPOICategoryRestaurant")
    }

    func testRecommendUpsertsMerchantWithoutConfirming() throws {
        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket",
                                                     id: "poi-loblaws"), amountCad: 20, asOf: asOf)
        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket",
                                                     id: "poi-loblaws"), amountCad: 30, asOf: asOf)
        let merchants = try service.knownMerchants()
        XCTAssertEqual(merchants.count, 1, "same POI id must upsert, not duplicate")
        XCTAssertEqual(merchants.first?.poiCategoryRaw, "MKPOICategoryFoodMarket",
                       "instant repeats must replay the known POI facts without a MapKit call")
        XCTAssertNil(merchants.first?.confirmedCategory,
                     "recommending is not confirming — only reconcile promotes a merchant")
        XCTAssertEqual(merchants.first?.confirmationCount, 0)
    }

    func testCannotAdviseThrowsCheckoutError() throws {
        var unvaluedCatalogue = try SeedLoader.loadCatalogue()
        unvaluedCatalogue.cards = unvaluedCatalogue.cards.map { card in
            var c = card
            c.program = Program(programId: "unknownProgram", unit: "point")
            return c
        }
        var owner = try SeedLoader.loadOwnerState()
        owner.ownedCardIds = unvaluedCatalogue.cards.map(\.cardId)
        let unvaluedService = CheckoutService(catalogue: unvaluedCatalogue, ownerState: owner,
                                              context: ModelContext(container))

        XCTAssertThrowsError(try unvaluedService.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                                           amountCad: 50, asOf: asOf)) { error in
            guard case CheckoutError.cannotAdvise(let reasons) = error else {
                return XCTFail("expected CheckoutError.cannotAdvise, got \(error)")
            }
            XCTAssertFalse(reasons.isEmpty)
        }
    }

    // MARK: rescoring (AmountRefineRow) — the day-to-day flow scores an estimate first and
    // refines it in place, so `rescoreCheckout` must reproduce whatever `recommend` would have
    // said at the refined amount, without writing to the store itself.

    func testRescoreCheckoutMatchesWhatRecommendWouldHaveSaidAtTheRefinedAmount() throws {
        let original = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                             amountCad: nil, asOf: asOf)
        let refined = try XCTUnwrap(rescoreCheckout(original, amountCad: 140,
                                                    engine: service.engine, asOf: asOf))
        guard case .single(let rec) = refined.outcome else {
            return XCTFail("expected single outcome, got \(refined.outcome)")
        }
        XCTAssertEqual(rec.winner.cardId, "amex-cobalt")
        XCTAssertEqual(rec.winner.netValueCad, 7.00, accuracy: 0.005,
                       "must match testUnambiguousGroceryProducesSingleOutcomeAndPersists exactly")
        XCTAssertEqual(refined.effectiveAmountCad, 140, accuracy: 0.005)
        XCTAssertFalse(refined.amountWasEstimated)
        XCTAssertEqual(refined.storedPredictionId, original.storedPredictionId,
                       "refining an answer must not mint a new prediction id")
    }

    func testRescoreCheckoutReproducesAForkSplit() throws {
        let original = try service.recommend(merchant: merchant("Walmart Supercentre",
                                                                 poi: "MKPOICategoryFoodMarket"),
                                             amountCad: 50, asOf: asOf)
        let refined = try XCTUnwrap(rescoreCheckout(original, amountCad: 100,
                                                    engine: service.engine, asOf: asOf))
        guard case .fork(let branches) = refined.outcome else {
            return XCTFail("Walmart at $100 must still fork — see testWalmartForkSplitsWhenBranchesDisagree")
        }
        XCTAssertEqual(branches.map(\.category), ["grocery", "other"])
        XCTAssertEqual(branches[0].recommendation.winner.cardId, "amex-cobalt")
        XCTAssertEqual(branches[1].recommendation.winner.cardId, "wealthsimple-vip")
    }

    func testRescoreCheckoutNeverWritesToTheStore() throws {
        let result = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                          amountCad: nil, asOf: asOf)
        _ = rescoreCheckout(result, amountCad: 140, engine: service.engine, asOf: asOf)

        XCTAssertEqual(try service.log.allPredictions().count, 1,
                       "rescoring twice on screen must still be one prediction row")
        let stored = try XCTUnwrap(try service.log.allPredictions().first)
        XCTAssertNil(stored.scoredAmountCad,
                     "rescoring alone must not persist — that is PredictionLog.recordScoredAmount's job")
    }
}
