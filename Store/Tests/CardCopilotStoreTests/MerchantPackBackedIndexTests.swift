import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// `CanadianMerchantPreIndex` becomes a view over `contracts/merchant-pack.json` rather than a
/// hand-written Swift array (spec:
/// docs/superpowers/specs/2026-09-01-merchant-category-resolution-design.md).
final class MerchantPackBackedIndexTests: XCTestCase {

    /// The reason the pack is loaded at all: it carries the needles that appear in payment
    /// descriptors, which a storefront name never does.
    func testRowsCarryTheirCuratedDescriptorKeys() throws {
        let amazon = try XCTUnwrap(CanadianMerchantPreIndex.all.first { $0.name == "Amazon.ca" })
        XCTAssertTrue(amazon.matchKeys.contains("amzn mktp ca"))
    }

    func testIndexIsSourcedFromThePack() {
        XCTAssertEqual(CanadianMerchantPreIndex.all.count,
                       SeedLoader.merchantPack.merchants.count)
    }

    /// `PreIndexedMerchant.id` is PERSISTED: `MerchantPatronageStore` keys visit history on it and
    /// resolves display names back through it. The pack's slug ("amazon-ca") is a different string
    /// from the historical id ("amazon.ca"), so adopting the slug would silently orphan every
    /// owner's patronage record. The id stays derived from the name.
    func testIdRemainsTheHistoricalNameDerivedKeySoPatronageSurvives() throws {
        let amazon = try XCTUnwrap(CanadianMerchantPreIndex.all.first { $0.name == "Amazon.ca" })
        XCTAssertEqual(amazon.id, "amazon.ca")
    }

    func testCategoryAndMccSurviveTheMove() throws {
        let costco = try XCTUnwrap(CanadianMerchantPreIndex.all.first {
            $0.name == "Costco Wholesale"
        })
        XCTAssertEqual(costco.category, "wholesaleClub")
        XCTAssertEqual(costco.mcc, 5300)
        XCTAssertEqual(costco.acceptedNetworks, [.mastercard])
        XCTAssertEqual(costco.merchantBrand, "costco")
        XCTAssertNotNil(costco.notes)
    }
}
