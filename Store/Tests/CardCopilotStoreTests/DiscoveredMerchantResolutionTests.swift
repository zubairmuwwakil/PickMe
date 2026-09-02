import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// The rung-2 decision: what tier and category a *discovered* POI earns, with no owner history.
///
/// Before this existed the tier was decided by `canonicalEngineBrand`, a six-token vocabulary
/// sized for the catalogue's scoring predicates. Every Canadian store outside it resolved to
/// `.unknown`, which `AmbientGate` suppresses unconditionally — so discovery could not speak.
final class DiscoveredMerchantResolutionTests: XCTestCase {

    func testWalletDescriptorResolvesAgainstMatchingNearbyRestaurant() throws {
        let restaurant = NearbyMerchant(
            id: "mapkit-moms-kitchen", name: "Mom's Kitchen",
            poiCategoryRaw: "MKPOICategoryRestaurant",
            latitude: 43.85, longitude: -79.02, distanceMeters: 24)

        let result = try XCTUnwrap(resolveWalletMerchant(
            capturedName: "Mom's Kitchen (Ajax)", nearbyMerchants: [restaurant]))

        XCTAssertEqual(result.merchant.id, restaurant.id)
        XCTAssertEqual(result.prediction.category, "dining")
        XCTAssertEqual(result.prediction.confidenceSource, .mapKitCategory)
    }

    func testWalletResolutionRejectsANameMatchThatIsTooFarAway() {
        let restaurant = NearbyMerchant(
            id: "far-away", name: "Mom's Kitchen",
            poiCategoryRaw: "MKPOICategoryRestaurant",
            latitude: 43.85, longitude: -79.02, distanceMeters: 180)

        XCTAssertNil(resolveWalletMerchant(capturedName: "Mom's Kitchen (Ajax)",
                                           nearbyMerchants: [restaurant]))
    }

    func testWalletResolutionRejectsAnAmbiguousPoiCategory() {
        let store = NearbyMerchant(
            id: "mapkit-store", name: "Mom's Kitchen",
            poiCategoryRaw: "MKPOICategoryStore",
            latitude: 43.85, longitude: -79.02, distanceMeters: 20)

        XCTAssertNil(resolveWalletMerchant(capturedName: "Mom's Kitchen (Ajax)",
                                           nearbyMerchants: [store]))
    }

    /// `CategoryMapper` forks the two commonest place types on purpose — gasstation yields
    /// ["gasStation", "other"] because you might have bought snacks inside. Wallet enrichment used
    /// to require `candidates.count == 1`, so it read that deliberate honesty as "not confident
    /// enough" and refused. Every gas-station capture was therefore unenrichable, no matter how
    /// good the fix or the name match.
    ///
    /// The engine scores every candidate and collapses the fork when the branches agree, so a
    /// two-element set is an answer it can act on, not a failure.
    func testAGasStationCaptureEnrichesDespiteItsDeliberateFork() throws {
        let station = NearbyMerchant(
            id: "mapkit-petro", name: "Petro-Canada",
            poiCategoryRaw: "MKPOICategoryGasStation",
            latitude: 43.85, longitude: -79.02, distanceMeters: 30)

        let result = try XCTUnwrap(resolveWalletMerchant(capturedName: "PETRO-CANADA #4021",
                                                         nearbyMerchants: [station]))
        XCTAssertEqual(result.prediction.category, "gasStation")
        XCTAssertEqual(result.prediction.candidates, ["gasStation", "other"],
                       "the fork survives; it is the engine's job to collapse it")
    }

    func testAPreIndexedGroceryBrandEarnsTheMiddleTier() {
        let r = resolveDiscoveredMerchant(name: "Sobeys", poiCategoryRaw: nil)
        XCTAssertEqual(r.confidence, .brandMatched)
        XCTAssertEqual(r.prediction.category, "grocery")
    }

    func testAPreIndexedBrandSuppliesItsOwnMccRatherThanAPoiGuess() {
        let r = resolveDiscoveredMerchant(name: "Shoppers Drug Mart", poiCategoryRaw: nil)
        XCTAssertEqual(r.prediction.category, "drugStore")
        XCTAssertNotNil(r.mcc, "the index carries an MCC for every row; it is better evidence than a POI category")
    }

    func testAnUnrecognisedNameWithNoPoiSignalStaysUnknown() {
        let r = resolveDiscoveredMerchant(name: "Bob's Hardware", poiCategoryRaw: nil)
        XCTAssertEqual(r.confidence, .unknown)
    }

    /// The seed brand priors in `CategoryMapper` are the same class of evidence as the index and
    /// must reach the same tier — otherwise which of two name-based priors fires is arbitrary.
    func testASeedBrandPriorAlsoEarnsTheMiddleTier() {
        let r = resolveDiscoveredMerchant(name: "Pro Hockey Life", poiCategoryRaw: nil)
        XCTAssertEqual(r.confidence, .brandMatched)
        XCTAssertEqual(r.prediction.category, "ctFamily")
    }

    /// The 2026-08-15 dossier keeps Walmart deliberately ambiguous: a Supercentre codes grocery,
    /// a discount store codes general merchandise. Recognition must not collapse that fork just
    /// because the index happens to hold a row named "Walmart".
    func testWalmartKeepsItsCategoryForkWhileStillBeingIdentified() {
        let r = resolveDiscoveredMerchant(name: "Walmart", poiCategoryRaw: "foodMarket")
        XCTAssertEqual(r.confidence, .brandMatched, "the brand is identified")
        XCTAssertTrue(r.prediction.candidates.contains("other"),
                      "but the coding stays forked rather than being asserted from the index row")
    }

    /// 15 catalogue rules gate on `mccInclude`. A recognised merchant carries a real MCC, so the
    /// ambient scoring context must actually carry it — otherwise the index's best evidence is
    /// read and then dropped on the floor.
    func testAmbientScoringContextCarriesTheRecognisedMcc() {
        let resolution = resolveDiscoveredMerchant(name: "Shoppers Drug Mart", poiCategoryRaw: nil)
        let merchant = NearbyMerchant(id: "poi-1", name: "Shoppers Drug Mart", poiCategoryRaw: nil,
                                      latitude: 45.4, longitude: -75.7, distanceMeters: nil)
        let context = ambientPurchaseContext(merchant: merchant,
                                             category: resolution.prediction.category,
                                             mcc: resolution.mcc)
        XCTAssertEqual(context.mcc, resolution.mcc)
        XCTAssertNotNil(context.mcc)
    }

    // MARK: - The size of the widening

    /// Every indexed merchant must clear `.unknown`. This is the whole point of the change: the
    /// previous gate, `canonicalEngineBrand`, recognised 7 of these 127 rows, so 120 Canadian
    /// merchants resolved to a tier `AmbientGate` suppresses unconditionally.
    func testEveryIndexedMerchantClearsTheSilentTier() {
        let silent = CanadianMerchantPreIndex.all
            .filter { resolveDiscoveredMerchant(name: $0.name, poiCategoryRaw: nil).confidence == .unknown }
            .map(\.name)
        XCTAssertEqual(silent, [], "indexed merchants that would still be suppressed on arrival")
    }

    /// Guards the regression rather than the fix: if recognition is ever narrowed back to the
    /// scoring vocabulary, this fails loudly instead of the app quietly going silent again.
    func testRecognitionIsWiderThanTheScoringBrandVocabulary() {
        let scoringVocabulary = CanadianMerchantPreIndex.all
            .filter { canonicalEngineBrand($0.name) != nil }.count
        let recognised = CanadianMerchantPreIndex.all
            .filter { MerchantRecognizer.recognise($0.name) != nil }.count
        XCTAssertGreaterThan(recognised, scoringVocabulary * 10,
                             "recognition (\(recognised)) must not collapse back toward the "
                             + "scoring vocabulary (\(scoringVocabulary))")
    }
}

// MARK: - Patronage

/// What repeated payment at a recognised merchant buys: the identity and presence doubts are
/// answered, so the tier rises. The category question is untouched — it is still a brand prior.
extension DiscoveredMerchantResolutionTests {

    func testAFrequentedPreIndexedBrandEarnsThePatronageTier() {
        let r = resolveDiscoveredMerchant(name: "Sobeys", poiCategoryRaw: nil,
                                          frequentedKeys: ["sobeys"])
        XCTAssertEqual(r.confidence, .frequented)
        XCTAssertEqual(r.prediction.category, "grocery", "patronage does not change the category")
    }

    /// Patronage is keyed on the indexed merchant, so a name the recogniser cannot place has no
    /// identity to have accrued standing under. It must not be rescued by a coincidental key.
    func testAnUnrecognisedNameCannotBeFrequented() {
        let r = resolveDiscoveredMerchant(name: "Bob's Hardware", poiCategoryRaw: nil,
                                          frequentedKeys: ["bob's hardware"])
        XCTAssertEqual(r.confidence, .unknown)
    }

    /// The tier fires at the owner's own threshold, which is only defensible while the category
    /// is checkable. An index row categorised "other" leaves the coding forked, so patronage
    /// establishes the identity but does not buy the lower bar.
    func testAForkedCategoryHoldsTheTierDownDespitePatronage() {
        let r = resolveDiscoveredMerchant(name: "Walmart", poiCategoryRaw: "foodMarket",
                                          frequentedKeys: ["walmart"])
        XCTAssertEqual(r.confidence, .brandMatched)
    }

    /// A stored merchant the owner never reconciled falls back to the discovered ladder, so it
    /// must carry patronage with it rather than silently losing it.
    func testAnUnreconciledStoredMerchantStillEarnsPatronage() {
        let r = resolveStoredMerchant(name: "Sobeys", poiCategoryRaw: nil,
                                      confirmedCategory: nil, confirmationCount: 0,
                                      frequentedKeys: ["sobeys"])
        XCTAssertEqual(r.confidence, .frequented)
    }

    /// Reconciliation against a statement remains the strongest evidence there is. Patronage
    /// must never displace it.
    func testReconciliationStillOutranksPatronage() {
        let r = resolveStoredMerchant(name: "Sobeys", poiCategoryRaw: nil,
                                      confirmedCategory: "grocery", confirmationCount: 1,
                                      frequentedKeys: ["sobeys"])
        XCTAssertEqual(r.confidence, .verified)
    }
}

// MARK: - Place-type evidence (A4)

extension DiscoveredMerchantResolutionTests {
    /// The 5-of-6 defect. `predict` carries a `.mapKitCategory` tier that maps pharmacy to
    /// drugStore, and rung 2 lifted only `.brandPrior` out of it — so a POI Apple confidently
    /// classifies as a pharmacy resolved to `.unknown`, which the gate suppresses to `.presence`
    /// unconditionally. The same file already trusts this evidence to categorise a real logged
    /// purchase in `resolveWalletMerchant`. One file, two verdicts, same evidence.
    func testAPharmacyPoiWithNoRecognisedBrandEarnsTheCategoryTier() {
        let r = resolveDiscoveredMerchant(name: "Riverbend Compounding",
                                          poiCategoryRaw: "MKPOICategoryPharmacy")
        XCTAssertEqual(r.confidence, .categoryMatched)
        XCTAssertEqual(r.prediction.category, "drugStore")
        XCTAssertEqual(r.prediction.confidenceSource, .mapKitCategory)
    }

    /// Every mapping `predict` offers, not just the one that produced the incident report.
    func testEveryMapKitCategoryMappingReachesTheCategoryTier() {
        let mappings = [
            ("MKPOICategoryPharmacy", "drugStore"),
            ("MKPOICategoryRestaurant", "dining"),
            ("MKPOICategoryCafe", "dining"),
            ("MKPOICategoryBakery", "dining"),
            ("MKPOICategoryGasStation", "gasStation"),
            ("MKPOICategoryFoodMarket", "grocery"),
            ("MKPOICategoryHotel", "lodging"),
            ("MKPOICategoryPublicTransport", "transit"),
            ("MKPOICategoryMovieTheater", "entertainment"),
            ("MKPOICategoryFitnessCenter", "fitness"),
        ]
        for (raw, category) in mappings {
            let r = resolveDiscoveredMerchant(name: "Riverbend Trading Post", poiCategoryRaw: raw)
            XCTAssertEqual(r.confidence, .categoryMatched, raw)
            XCTAssertEqual(r.prediction.category, category, raw)
        }
    }

    /// `MKPOICategoryStore` maps to "other", where every card ties at base earn. Refused for
    /// exactly the reason `resolveWalletMerchant` refuses it: storing "other" would dress up an
    /// absence of evidence as a categorization, and the tier is a claim about knowing the
    /// category.
    func testAPlaceTypeThatOnlyYieldsOtherStaysUnknown() {
        let r = resolveDiscoveredMerchant(name: "Riverbend Trading Post",
                                          poiCategoryRaw: "MKPOICategoryStore")
        XCTAssertEqual(r.confidence, .unknown)
    }

    func testAPlaceTypeMapKitCannotClassifyStaysUnknown() {
        let r = resolveDiscoveredMerchant(name: "Riverbend Trading Post",
                                          poiCategoryRaw: "MKPOICategoryCampground")
        XCTAssertEqual(r.confidence, .unknown)
    }

    /// Identity outranks place type. A recognised brand keeps `.brandMatched` — the claim that we
    /// know *which* store this is — rather than being demoted to the tier that claims only the
    /// category.
    func testARecognisedBrandOutranksItsPlaceType() {
        let r = resolveDiscoveredMerchant(name: "Shoppers Drug Mart",
                                          poiCategoryRaw: "MKPOICategoryPharmacy")
        XCTAssertEqual(r.confidence, .brandMatched)
    }

    /// Place-type evidence says nothing about identity, so it cannot carry patronage: standing is
    /// keyed on an indexed merchant, and there is no merchant here to have accrued it.
    func testPlaceTypeEvidenceCannotBeFrequented() {
        let r = resolveDiscoveredMerchant(name: "Riverbend Compounding",
                                          poiCategoryRaw: "MKPOICategoryPharmacy",
                                          frequentedKeys: ["riverbend compounding"])
        XCTAssertEqual(r.confidence, .categoryMatched)
    }
}
