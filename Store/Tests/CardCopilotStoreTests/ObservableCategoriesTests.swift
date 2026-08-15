import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// The reconcile picker's vocabulary. Derived, never hand-listed: the failure mode this guards
/// against is the app predicting a category the owner then cannot select when correcting it,
/// which would quietly push real misses into whatever neighbouring option was available.
final class ObservableCategoriesTests: XCTestCase {
    private var catalogue: Catalogue!

    override func setUpWithError() throws {
        catalogue = try SeedLoader.loadCatalogue()
    }

    func testEveryCategoryTheCatalogueScoresIsOfferable() {
        let offered = Set(observableCategories(in: catalogue))
        XCTAssertTrue(offered.isSuperset(of: ["grocery", "dining", "gasStation", "streaming",
                                              "ctFamily", "marriottDirect", "transit"]))
    }

    func testEveryCategoryTheMapperCanPredictIsOfferable() {
        let offered = Set(observableCategories(in: catalogue))
        let pois = ["MKPOICategoryFoodMarket", "MKPOICategoryGasStation", "MKPOICategoryRestaurant",
                    "MKPOICategoryCafe", "MKPOICategoryBakery", "MKPOICategoryPharmacy",
                    "MKPOICategoryPublicTransport", "MKPOICategoryHotel",
                    "MKPOICategoryMovieTheater", "MKPOICategoryFitnessCenter",
                    "MKPOICategoryStore", "MKPOICategoryAnimalService"]
        for poi in pois {
            for candidate in predict(poiCategoryRaw: poi, merchantName: "Somewhere").candidates {
                XCTAssertTrue(offered.contains(candidate),
                              "\(candidate) is predictable but not reconcilable")
            }
        }
        for brand in ["Canadian Tire", "Costco Wholesale", "Marriott Downtown", "Sport Chek"] {
            let predicted = predict(poiCategoryRaw: nil, merchantName: brand).category
            XCTAssertTrue(offered.contains(predicted),
                          "\(predicted) is predictable but not reconcilable")
        }
    }

    func testRuleSideMarkersAreNotOffered() {
        XCTAssertFalse(observableCategories(in: catalogue).contains("ownerSelectedTangerineCategory"),
                       "that is a stand-in for whichever categories the owner picked on Tangerine — no statement ever shows it")
    }

    func testCategoryTokensRenderAsHumanLabels() {
        XCTAssertEqual(categoryDisplayName("grocery"), "Grocery")
        XCTAssertEqual(categoryDisplayName("gasStation"), "Gas station")
        XCTAssertEqual(categoryDisplayName("ctFamily"), "Canadian Tire family")
        XCTAssertEqual(categoryDisplayName("other"), "General merchandise",
                       "'other' is what the app tells the owner a Walmart might code as — the label has to say that")
    }

    func testAnUnknownCategoryStillReadsAsEnglish() {
        // A catalogue that grows a category must not surface a raw token in the picker.
        XCTAssertEqual(categoryDisplayName("homeImprovement"), "Home improvement")
    }

    func testTheListIsStableAndDeduplicated() {
        let categories = observableCategories(in: catalogue)
        XCTAssertEqual(categories, categories.sorted(), "a picker that reorders itself is a picker that gets mis-tapped")
        XCTAssertEqual(Set(categories).count, categories.count)
    }
}
