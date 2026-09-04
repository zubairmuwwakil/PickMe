import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

/// The four claims the stable-identity work has to make good on, plus the two it must NOT make.
///
/// Every one of these failed silently before: nothing threw, nothing logged, the owner's
/// confirmation simply stopped being found and the checkout quietly fell back to a POI guess. So
/// each test asserts on the merchant row and the confirmation streak rather than on any error.
final class MerchantIdentityTests: XCTestCase {
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

    override func tearDownWithError() throws {
        service = nil
        container = nil
    }

    /// The exact string `LiveMerchantProvider.syntheticId` produces, so these tests break the same
    /// way the app would rather than on a prettier stand-in.
    private func syntheticID(_ name: String, _ latitude: Double, _ longitude: Double) -> String {
        "\(name)@\(latitude),\(longitude)"
    }

    private func metro(latitude: Double = 43.6532, longitude: Double = -79.3832,
                       name: String = "Metro", placeID: String? = nil,
                       alternates: [String] = []) -> NearbyPlace {
        NearbyPlace(id: syntheticID(name, latitude, longitude),
                    placeID: placeID, alternatePlaceIDs: alternates,
                    name: name, poiCategoryRaw: "MKPOICategoryFoodMarket",
                    latitude: latitude, longitude: longitude, distanceMeters: 20)
    }

    // MARK: - The over-split

    /// The headline case. MapKit revises the pin by roughly twenty metres; the id string changes
    /// completely, because it is two `Double`s rendered as text. The owner's confirmed category —
    /// the top rung of the entire confidence ladder — has to survive that.
    func testACoordinateNudgePreservesAConfirmedCategory() throws {
        try service.log.confirmMerchant(metro(), category: "grocery")

        let nudged = metro(latitude: 43.65322, longitude: -79.38317)
        XCTAssertNotEqual(nudged.id, metro().id, "the fixture must actually change the id")

        let merchants = try service.knownMerchants()
        let match = try XCTUnwrap(MerchantIdentity.match(nudged, in: merchants))
        XCTAssertEqual(match.rung, .nameAndProximity)
        XCTAssertEqual(match.merchant.confirmedCategory, "grocery")
    }

    /// And the write path, which is where the damage actually accrued: confirming the same shop
    /// again after a revision used to mint a second row, so the streak `.repeatedTerminal` counts
    /// restarted at one and the owner's second confirmation bought them nothing.
    func testConfirmingAgainAfterANudgeStrengthensTheSameRow() throws {
        try service.log.confirmMerchant(metro(), category: "grocery")
        try service.log.confirmMerchant(metro(latitude: 43.65325, longitude: -79.38315),
                                        category: "grocery")

        let merchants = try service.knownMerchants()
        XCTAssertEqual(merchants.count, 1)
        XCTAssertEqual(merchants[0].confirmationCount, 2)
        XCTAssertEqual(merchants[0].categoryConfidenceScore,
                       ConfidenceSource.repeatedTerminal.defaultScore)
    }

    /// A renamed storefront is the other half of the same defect — the display name is in the id
    /// too — and it is the half proximity cannot rescue. Apple's place id is what carries it.
    func testARenamedStorefrontIsStillTheSameMerchantThroughItsPlaceID() throws {
        try service.log.confirmMerchant(metro(placeID: "I1A2B3C4"), category: "grocery")

        let renamed = metro(name: "Metro Plus", placeID: "I1A2B3C4")
        let match = try XCTUnwrap(MerchantIdentity.match(renamed, in: try service.knownMerchants()))
        XCTAssertEqual(match.rung, .placeID)
        XCTAssertEqual(match.merchant.confirmedCategory, "grocery")
    }

    /// Apple's own continuity mechanism: when a place record is merged or reissued, the id it
    /// superseded is reported in `alternateIdentifiers`. Matching only the primary would produce a
    /// second, rarer generation of exactly the orphan this work removes.
    func testASupersededPlaceIDStillMatchesThroughAlternateIdentifiers() throws {
        try service.log.confirmMerchant(metro(placeID: "I-old"), category: "grocery")

        let reissued = metro(placeID: "I-new", alternates: ["I-old"])
        let match = try XCTUnwrap(MerchantIdentity.match(reissued, in: try service.knownMerchants()))
        XCTAssertEqual(match.rung, .placeID)
    }

    // MARK: - What must NOT merge

    /// Proximity is a rescue for a moved pin, not a licence to pool a chain. Two Metros across
    /// town are two merchants, and a confirmation at one says nothing about the other — the
    /// terminal-level promotion rule the dossier is explicit about.
    func testTwoSameNamedMerchantsAtDifferentCoordinatesStaySeparate() throws {
        try service.log.confirmMerchant(metro(), category: "grocery")

        let acrossTown = metro(latitude: 43.7615, longitude: -79.4111)
        XCTAssertNil(MerchantIdentity.match(acrossTown, in: try service.knownMerchants()))

        // A different category on purpose: if these two ever merged, the second confirmation would
        // silently re-code the first shop rather than create a row of its own.
        try service.log.confirmMerchant(acrossTown, category: "dining")
        let merchants = try service.knownMerchants()
        XCTAssertEqual(merchants.count, 2)
        XCTAssertEqual(Set(merchants.compactMap(\.confirmedCategory)), ["grocery", "dining"])
    }

    /// Once both sides carry a place id, Apple has already answered the question and proximity
    /// must not overrule it. This is the two-Tim-Hortons-in-one-mall case: same name, well inside
    /// the proximity radius, definitively different places.
    func testDisagreeingPlaceIDsAreNotMergedByProximity() throws {
        try service.log.confirmMerchant(metro(placeID: "I-north-end"), category: "grocery")

        let otherUnit = metro(latitude: 43.65327, longitude: -79.38312, placeID: "I-south-end")
        XCTAssertNil(MerchantIdentity.match(otherUnit, in: try service.knownMerchants()))
    }

    // MARK: - The migration

    /// The whole migration story in one test: a row written before V6 has no place id at all, and
    /// must keep resolving on the legacy string exactly as it did — the rung that makes "no data
    /// rewrite" true rather than merely convenient.
    func testARowWithNoPlaceIDStillResolvesOnItsLegacyIdentifier() throws {
        try service.log.confirmMerchant(metro(), category: "grocery")
        let stored = try XCTUnwrap(try service.knownMerchants().first)
        XCTAssertNil(stored.placeID, "the fixture must reproduce a pre-V6 row")

        let match = try XCTUnwrap(MerchantIdentity.match(metro(placeID: "I-new"),
                                                         in: try service.knownMerchants()))
        XCTAssertEqual(match.rung, .legacyIdentifier)
    }

    /// …and heals on the next real encounter, which is the only moment a correct place id is
    /// available for free. Nothing is guessed at upgrade time because nothing can be.
    func testAWeakRungMatchBackfillsThePlaceID() throws {
        try service.log.confirmMerchant(metro(), category: "grocery")
        let stored = try XCTUnwrap(try service.knownMerchants().first)

        XCTAssertTrue(MerchantIdentity.backfill(stored, from: metro(placeID: "I1A2B3C4")))
        XCTAssertEqual(stored.placeID, "I1A2B3C4")

        let match = try XCTUnwrap(MerchantIdentity.match(metro(latitude: 0.1, longitude: 0.1,
                                                               placeID: "I1A2B3C4"),
                                                         in: try service.knownMerchants()))
        XCTAssertEqual(match.rung, .placeID, "the row should now match from anywhere")
    }

    /// Backfill never re-points a row that already has an id. A row whose place id disagrees with
    /// the incoming one should not have matched at all, and silently re-aiming owner-confirmed
    /// history at a different Apple place is the last thing to do about it if it somehow did.
    func testBackfillNeverOverwritesAnExistingPlaceID() throws {
        try service.log.confirmMerchant(metro(placeID: "I-original"), category: "grocery")
        let stored = try XCTUnwrap(try service.knownMerchants().first)

        XCTAssertFalse(MerchantIdentity.backfill(stored, from: metro(placeID: "I-other")))
        XCTAssertEqual(stored.placeID, "I-original")
    }

    // MARK: - The synthetic fallback

    /// A pre-index tap has no coordinates and no place id — the owner named a brand, not a place.
    /// It must not be matched to anything by proximity, or every brand-only tap would attach
    /// itself to whichever confirmed merchant happened to sit at the null island.
    func testABrandOnlyTapMatchesNothingByProximity() throws {
        let brandOnly = NearbyPlace(id: "preindex:metro", name: "Metro", poiCategoryRaw: nil,
                                    latitude: 0, longitude: 0, distanceMeters: nil)
        try service.log.confirmMerchant(metro(), category: "grocery")

        XCTAssertNil(MerchantIdentity.match(brandOnly, in: try service.knownMerchants()))
    }

    /// The synthetic id remains a working identity end to end when MapKit supplies nothing, which
    /// is the state every stub provider and every offline path is in.
    func testTheSyntheticIdentifierStillIdentifiesAMerchantOnItsOwn() throws {
        let noPlaceID = metro()
        try service.log.confirmMerchant(noPlaceID, category: "grocery")

        let match = try XCTUnwrap(MerchantIdentity.match(noPlaceID, in: try service.knownMerchants()))
        XCTAssertEqual(match.rung, .legacyIdentifier)
        XCTAssertEqual(match.merchant.identifier, noPlaceID.id)
        XCTAssertNil(match.merchant.placeID)
    }
}
