import XCTest
@testable import CardCopilotStore

final class CategoryMapperTests: XCTestCase {

    func testKnownMerchantUsesVerifiedTruthGraphBeforeMapperFallback() {
        let merchant = StoredMerchant(name: "Walmart Supercentre", identifier: "poi-walmart",
                                      poiCategoryRaw: "MKPOICategoryFoodMarket", latitude: 43.7,
                                      longitude: -79.4, confirmedCategory: "other",
                                      confirmationCount: 2)
        let prediction = predictionForKnownMerchant(merchant)
        XCTAssertEqual(prediction.category, "other")
        XCTAssertEqual(prediction.confidenceSource, .repeatedTerminal)
        XCTAssertEqual(prediction.candidates, ["other"])
    }

    func testKnownMerchantWithoutTruthGraphFallsBackToMapper() {
        let merchant = StoredMerchant(name: "Costco Wholesale", identifier: "poi-costco",
                                      poiCategoryRaw: nil, latitude: 43.7, longitude: -79.4)
        let prediction = predictionForKnownMerchant(merchant)
        XCTAssertEqual(prediction.category, "wholesaleClub")
        XCTAssertEqual(prediction.confidenceSource, .brandPrior)
    }
    func testFoodMarketMapsToGroceryFromMapKitCategory() {
        let prediction = predict(poiCategoryRaw: "foodMarket", merchantName: "Loblaws")

        XCTAssertEqual(prediction.category, "grocery")
        XCTAssertEqual(prediction.confidenceSource, .mapKitCategory)
        XCTAssertEqual(prediction.candidates, ["grocery"])
    }

    func testGasStationKeepsPumpAndKioskBranchesAmbiguous() {
        let prediction = predict(poiCategoryRaw: "gasStation", merchantName: "Esso")

        XCTAssertEqual(prediction.category, "gasStation")
        XCTAssertEqual(prediction.confidenceSource, .mapKitCategory)
        XCTAssertEqual(prediction.candidates, ["gasStation", "other"])
    }

    func testRestaurantsCafesAndBakeriesMapToDining() {
        for rawCategory in ["restaurant", "cafe", "bakery"] {
            let prediction = predict(poiCategoryRaw: rawCategory, merchantName: "Neighbourhood \(rawCategory)")

            XCTAssertEqual(prediction.category, "dining", rawCategory)
            XCTAssertEqual(prediction.confidenceSource, .mapKitCategory, rawCategory)
            XCTAssertEqual(prediction.candidates, ["dining"], rawCategory)
        }
    }

    func testHighConfidenceBrandPriorsOverrideMapKitCategory() {
        let examples: [(merchantName: String, expectedCategory: String)] = [
            ("Canadian Tire", "ctFamily"),
            ("Sport Chek #123", "ctFamily"),
            ("Mark's Work Wearhouse", "ctFamily"),
            ("Atmosphere Toronto", "ctFamily"),
            ("Party City", "ctFamily"),
            ("Pro Hockey Life", "ctFamily"),
            ("Sports Experts", "ctFamily"),
            ("Costco Wholesale", "wholesaleClub"),
            ("Marriott Downtown", "marriottDirect"),
        ]

        for example in examples {
            let prediction = predict(poiCategoryRaw: "restaurant", merchantName: example.merchantName)

            XCTAssertEqual(prediction.category, example.expectedCategory, example.merchantName)
            XCTAssertEqual(prediction.confidenceSource, .brandPrior, example.merchantName)
            XCTAssertEqual(prediction.candidates, [example.expectedCategory], example.merchantName)
        }
    }

    func testBrandMatchingIgnoresCaseAndPunctuation() {
        let prediction = predict(poiCategoryRaw: "store", merchantName: "SPORT-CHEK #123")

        XCTAssertEqual(prediction.category, "ctFamily")
        XCTAssertEqual(prediction.confidenceSource, .brandPrior)
        XCTAssertEqual(prediction.candidates, ["ctFamily"])
    }

    func testWalmartFoodMarketStaysAmbiguous() {
        // Dossier §2.5/Scotia brand gotcha: never hard-code Walmart either way; only a learned
        // location/terminal that actually submits grocery MCC 5411 can promote it.
        let prediction = predict(poiCategoryRaw: "foodMarket", merchantName: "Walmart Supercentre")

        XCTAssertEqual(prediction.category, "grocery")
        XCTAssertEqual(prediction.confidenceSource, .mapKitCategory)
        XCTAssertEqual(prediction.candidates, ["grocery", "other"])
    }

    func testUnknownAndNilPoiFallBackToOther() {
        let unknown = predict(poiCategoryRaw: "planetarium", merchantName: "Mystery Shop")
        let nilCategory = predict(poiCategoryRaw: nil, merchantName: "Mystery Shop")

        XCTAssertEqual(unknown, CategoryPrediction(category: "other",
                                                   confidenceSource: .fallback,
                                                   candidates: ["other"]))
        XCTAssertEqual(nilCategory, CategoryPrediction(category: "other",
                                                       confidenceSource: .fallback,
                                                       candidates: ["other"]))
    }
}
