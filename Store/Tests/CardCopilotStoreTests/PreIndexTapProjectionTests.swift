import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// Projecting a tapped pre-index row into the `NearbyMerchant` the rest of the app scores.
///
/// This existed twice — `HomeView`'s offline dropdown and `LiveMerchantProvider.fallbackSearch` —
/// and both copies made the same mistake: they put the row's canonical taxonomy category into
/// `poiCategoryRaw`, a field that means "Apple's place-type vocabulary", and dropped `mcc`
/// entirely. `canonicalPoiCategory("grocery")` matches none of the MapKit cases, so the tap
/// resolved to `other`/`.fallback` and every card scored base earn.
final class PreIndexTapProjectionTests: XCTestCase {

    private func row(_ name: String) throws -> PreIndexedMerchant {
        try XCTUnwrap(CanadianMerchantPreIndex.all.first { $0.name == name })
    }

    func testProjectionCarriesTheMccAndClaimsNoPoiSignal() throws {
        let merchant = NearbyMerchant(preIndexed: try row("Loblaws"))

        XCTAssertEqual(merchant.name, "Loblaws")
        XCTAssertEqual(merchant.merchantCategoryCode, 5411)
        XCTAssertNil(merchant.poiCategoryRaw,
                     "a pre-index tap carries no MapKit signal; claiming one is how the category was lost")
    }

    func testIdKeepsThePreindexPrefixSoStoredRowsStayJoinable() throws {
        XCTAssertEqual(NearbyMerchant(preIndexed: try row("Loblaws")).id, "preindex:loblaws")
    }

    /// A grocery brand must score as grocery. This is the reported failure.
    func testATappedGroceryBrandResolvesToGrocery() throws {
        let prediction = predict(poiCategoryRaw: nil, merchantName: "Loblaws",
                                 merchantCategoryCode: NearbyMerchant(preIndexed: try row("Loblaws"))
                                    .merchantCategoryCode)
        XCTAssertEqual(prediction.category, "grocery")
        XCTAssertNotEqual(prediction.confidenceSource, .fallback)
    }

    /// The invariant, not a spot check. A row the owner can tap but whose category the app cannot
    /// recover is a row that silently scores base earn — the exact failure this change exists to
    /// fix. Rows the pack itself declares `other` are excluded: they name a brand without settling
    /// how it codes (Walmart), and asserting a category for them would be the opposite mistake.
    func testEveryTappableRowResolvesToItsOwnCategory() throws {
        var unresolved: [String] = []
        for row in CanadianMerchantPreIndex.all where row.category != "other" {
            let merchant = NearbyMerchant(preIndexed: row)
            let resolved = resolveDiscoveredMerchant(name: merchant.name,
                                                     poiCategoryRaw: merchant.poiCategoryRaw)
            if resolved.prediction.category != row.category {
                unresolved.append("\(row.name): expected \(row.category), got \(resolved.prediction.category)")
            }
        }
        XCTAssertEqual(unresolved, [], "tappable rows whose category the app cannot recover")
    }

    /// One ladder, one entry point. Home's answer card computed its own prediction and dropped
    /// both the MCC and the pack, so a tapped Netflix scored `streaming` while the card above the
    /// recommendation said `other`. The two must not be able to disagree.
    func testTheSharedLadderResolvesWhatTheScoringPathResolves() throws {
        let netflix = NearbyMerchant(preIndexed: try row("Netflix"))
        XCTAssertEqual(resolveCategory(for: netflix).category, "streaming")
    }

    /// Better evidence still wins. A real POI signal must not be overridden by an editorial row.
    func testAPoiSignalStillOutranksThePack() {
        let cafe = NearbyMerchant(id: "poi-1", name: "Some Independent Cafe",
                                  poiCategoryRaw: "MKPOICategoryCafe",
                                  latitude: 43.65, longitude: -79.38, distanceMeters: 30)
        let resolved = resolveCategory(for: cafe)
        XCTAssertEqual(resolved.category, "dining")
        XCTAssertEqual(resolved.confidenceSource, .mapKitCategory)
    }
}
