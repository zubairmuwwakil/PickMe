import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class CanadianMerchantPreIndexTests: XCTestCase {
    func testCostcoIsPreIndexedWithMastercardOnlyRestriction() {
        let results = CanadianMerchantPreIndex.search("costco")
        XCTAssertFalse(results.isEmpty)
        let costco = results.first!
        XCTAssertEqual(costco.mcc, 5300)
        XCTAssertEqual(costco.category, "wholesaleClub")
        XCTAssertEqual(costco.acceptedNetworks, [.mastercard])
    }

    func testTimHortonsSearchMatchesPrefix() {
        let results = CanadianMerchantPreIndex.search("Tim")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.name == "Tim Hortons" })
    }

    func testLoblawsAndNoFrillsCategories() {
        let results = CanadianMerchantPreIndex.search("No Frills")
        XCTAssertFalse(results.isEmpty)
        let noFrills = results.first!
        XCTAssertEqual(noFrills.category, "grocery")
        XCTAssertEqual(noFrills.acceptedNetworks, [.mastercard, .visa])
    }

    func testEmptyQueryReturnsEmpty() {
        XCTAssertTrue(CanadianMerchantPreIndex.search("").isEmpty)
        XCTAssertTrue(CanadianMerchantPreIndex.search("   ").isEmpty)
    }
}
