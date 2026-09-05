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

    private func merchant(_ name: String, poi: String?, id: String = "poi-1") -> NearbyPlace {
        NearbyPlace(id: id, name: name, poiCategoryRaw: poi,
                       latitude: 43.65, longitude: -79.38, distanceMeters: 40)
    }

    // MARK: the resolution ladder

    /// Scoring must consult the same ladder recognition does. `predict` alone sees only MCC, POI
    /// and nine seed brand priors — and `observedMCCCategory` deliberately holds only MCCs with a
    /// single stable meaning, so 5968 (Netflix), 5200 (Canadian Tire) and 4814 (Rogers) are all
    /// absent. A tapped pre-index row therefore scored `other` and every card tied at base earn,
    /// even though the pack states the category outright.
    func testATappedPreIndexRowScoresItsPackCategoryNotOther() throws {
        let netflix = try XCTUnwrap(CanadianMerchantPreIndex.all.first { $0.name == "Netflix" })
        let result = try service.recommend(merchant: NearbyPlace(preIndexed: netflix),
                                           amountCad: 20, asOf: asOf)
        XCTAssertEqual(result.prediction.category, "streaming")
    }

    func testATappedRowWhoseMccIsAbsentStillResolves() throws {
        let ct = try XCTUnwrap(CanadianMerchantPreIndex.all.first { $0.name == "Canadian Tire" })
        let result = try service.recommend(merchant: NearbyPlace(preIndexed: ct),
                                           amountCad: 60, asOf: asOf)
        XCTAssertEqual(result.prediction.category, "ctFamily")
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

    // MARK: network acceptance is recognised, never guessed

    /// Removing `.amex` is an affirmative negative claim: the app renders it as "does not accept
    /// American Express" and withholds the owner's best dining card. Nothing the owner can see
    /// ever contradicts it, so it must come from recognition and not from a name that happens to
    /// share letters with a grocery banner.
    ///
    /// Each name below was resolved to the banner in the comment by the substring matcher this
    /// function used before 2026-09-04, which compared the POI name to each row's DISPLAY name in
    /// both directions and took the first pack row that matched. Two are fixed by tokenising
    /// ("maxi" is no longer inside "Maxime's"); two needed the pack to drop a single-token needle
    /// that was an ordinary English word on a row that removes Amex.
    ///
    /// NOT fixed here, and deliberately: "Dominion Square Tavern" still resolves to the Dominion
    /// grocery banner, because that row's displayName IS "Dominion" and
    /// `MerchantRecognizerTests.testEveryIndexedMerchantRecognisesItself` requires a row to be
    /// reachable from its own name. Narrowing the needle to "dominion stores" needs the
    /// displayName narrowed too, and `PreIndexedMerchant.id` is derived from displayName and
    /// persisted by `MerchantPatronageStore` — so that is a migration, not an edit. Same shape:
    /// "No Frills Fitness" -> no-frills.
    func testAmexIsNotWithheldFromMerchantsThatMerelyShareLettersWithAGrocer() {
        let open: Set<Network> = [.amex, .visa, .mastercard]
        // -> real-canadian-superstore, via the bare "superstore" needle
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "Superstore Liquidation"), open)
        // -> maxi, by substring
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "Maxime's Bistro"), open)
        // -> metro (which also mis-set the category to grocery)
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "Metropolitan Hotel"), open)
        // -> fortinos, via the singular "fortino" needle (an Italian surname)
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "Fortino Ristorante"), open)
    }

    /// The narrowing must still happen for the merchants that earned it, including inside a
    /// fuller POI string — a store number or city suffix is how these names actually arrive.
    func testRecognisedGrocersStillNarrowAcceptance() {
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "Costco Wholesale #536"),
                       [.mastercard])
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "No Frills Bramalea"),
                       [.mastercard, .visa])
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "Bulk Barn"),
                       [.mastercard, .visa])
    }

    /// An unrecognised merchant fails toward the open default. The owner taps a second card and
    /// learns something; the reverse failure is silent and permanent.
    func testUnrecognisedMerchantsGetTheOpenDefault() {
        XCTAssertEqual(knownAcceptedNetworks(for: nil, merchantName: "Fresh Foods Market"),
                       [.amex, .visa, .mastercard])
    }

    // MARK: single-outcome flow

    func testUnambiguousGroceryProducesSingleOutcomeAndPersists() throws {
        let result = try service.recommend(merchant: merchant("Metro", poi: "MKPOICategoryFoodMarket"),
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
        let result = try service.recommend(merchant: merchant("Metro", poi: "MKPOICategoryFoodMarket"),
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

    func testLoblawsExcludesAmexDueToNetworkRestriction() throws {
        let result = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                           amountCad: 140, asOf: asOf)
        guard case .single(let rec) = result.outcome else {
            return XCTFail("expected single outcome, got \(result.outcome)")
        }
        XCTAssertNotEqual(rec.winner.cardId, "amex-cobalt",
                          "Loblaws terminal policy rejects American Express; Cobalt cannot be recommended")
        XCTAssertEqual(rec.winner.cardId, "mbna-rewards-we",
                       "MBNA Rewards World Elite (Mastercard) wins with 5x on grocery at Loblaws")
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

    func testCompleteUniqueWalletMatchMovesCheckoutStraightToRecentPurchases() throws {
        let checkout = try service.recommend(
            merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
            amountCad: nil,
            asOf: asOf)
        let prediction = try XCTUnwrap(try service.log.allPredictions().first)
        let purchaseID = try XCTUnwrap(prediction.purchase?.id)
        let capturedAt = prediction.recordedAt.addingTimeInterval(90)
        let feedback = WalletFeedback(
            eventId: "wallet-checkout-1", capturedAt: capturedAt,
            merchantRaw: "LOBLAWS #1024", merchantNormalized: "Loblaws",
            amountMinor: 4210, currency: "CAD", cardRaw: "Amex Cobalt",
            resolvedCardId: "amex-cobalt", verdict: "best", warning: nil)

        let ingested = try service.ingestAutomaticCaptures(from: [feedback])

        let purchase = try XCTUnwrap(ingested.first)
        XCTAssertEqual(purchase.id, purchaseID, "the capture must complete the checkout's row, not add another")
        XCTAssertEqual(purchase.amountCad ?? .nan, 42.10, accuracy: 0.001)
        XCTAssertEqual(purchase.cardUsedId, "amex-cobalt")
        XCTAssertEqual(purchase.walletEventId, "wallet-checkout-1")
        XCTAssertEqual(purchase.amountSource, .walletCapture)
        XCTAssertEqual(purchase.cardSource, .walletCapture)
        XCTAssertEqual(purchase.completedAt, capturedAt)
        XCTAssertTrue(try service.log.awaitingCompletion().isEmpty)
        XCTAssertEqual(try service.log.allPurchases().map(\.id), [purchaseID])
        XCTAssertEqual(checkout.storedPredictionId, prediction.id)

        XCTAssertTrue(try service.ingestAutomaticCaptures(from: [feedback]).isEmpty,
                      "replaying the same Wallet event must be idempotent")
        XCTAssertEqual(try service.log.allPurchases().count, 1)
    }

    func testDeletingWalletCapturePreventsSyncFromRecreatingIt() throws {
        let suiteName = "WalletCaptureDeletionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deletionStore = WalletCaptureDeletionStore(defaults: defaults)
        let deletionAwareService = CheckoutService(
            catalogue: try SeedLoader.loadCatalogue(),
            ownerState: try SeedLoader.loadOwnerState(),
            context: ModelContext(container),
            walletCaptureDeletionStore: deletionStore)
        let feedback = WalletFeedback(
            eventId: "wallet-deleted-capture", capturedAt: Date(),
            merchantRaw: "Mom's Kitchen", amountMinor: 4743, currency: "CAD",
            cardRaw: "Amex Cobalt", resolvedCardId: "amex-cobalt",
            verdict: "unknown", warning: nil)

        let purchase = try XCTUnwrap(deletionAwareService.ingestAutomaticCaptures(from: [feedback]).first)
        try deletionAwareService.deletePurchase(purchase)

        XCTAssertTrue(deletionStore.contains(eventID: feedback.eventId))
        XCTAssertTrue(try deletionAwareService.log.allPurchases().isEmpty)
        XCTAssertTrue(try deletionAwareService.ingestAutomaticCaptures(from: [feedback]).isEmpty,
                      "A server feedback replay must respect the owner's local Activity deletion.")
        XCTAssertTrue(try deletionAwareService.log.allPurchases().isEmpty)

        try LocalDataEraser(context: ModelContext(container),
                             walletCaptureDeletionStore: deletionStore).eraseLocalHistory()
        XCTAssertFalse(deletionStore.contains(eventID: feedback.eventId),
                       "A local-history wipe must remove its capture suppressions too.")
    }

    func testPartialWalletMatchStaysInFinishPurchases() throws {
        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                  amountCad: nil, asOf: asOf)
        let prediction = try XCTUnwrap(try service.log.allPredictions().first)
        let feedback = WalletFeedback(
            eventId: "wallet-partial", capturedAt: prediction.recordedAt.addingTimeInterval(60),
            merchantRaw: "Loblaws", amountMinor: 4210, currency: "CAD",
            cardRaw: "Unmapped card", resolvedCardId: nil, verdict: "unknown", warning: nil)

        XCTAssertTrue(try service.ingestAutomaticCaptures(from: [feedback]).isEmpty)
        XCTAssertEqual(try service.log.awaitingCompletion().map(\.id), [prediction.id])
        XCTAssertNil(prediction.purchase?.walletEventId)
        XCTAssertEqual(try service.log.allPurchases().count, 1,
                       "a partial match must not also create a standalone purchase")
    }

    func testForeignCurrencyWalletMatchStaysInFinishPurchases() throws {
        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                  amountCad: nil, asOf: asOf)
        let prediction = try XCTUnwrap(try service.log.allPredictions().first)
        let feedback = WalletFeedback(
            eventId: "wallet-usd", capturedAt: prediction.recordedAt.addingTimeInterval(60),
            merchantRaw: "Loblaws", amountMinor: 4210, currency: "USD",
            cardRaw: "Amex Cobalt", resolvedCardId: "amex-cobalt",
            verdict: "unknown", warning: nil)

        XCTAssertTrue(try service.ingestAutomaticCaptures(from: [feedback]).isEmpty)
        XCTAssertEqual(try service.log.awaitingCompletion().map(\.id), [prediction.id])
        XCTAssertNil(prediction.purchase?.amountCad, "PickMe must not invent an FX conversion")
    }

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
        let original = try service.recommend(merchant: merchant("Metro", poi: "MKPOICategoryFoodMarket"),
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
