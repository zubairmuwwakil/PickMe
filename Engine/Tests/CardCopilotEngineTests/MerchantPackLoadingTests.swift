import XCTest
@testable import CardCopilotEngine

/// `contracts/merchant-pack.json` becomes the source of truth for brand -> category facts
/// (spec: docs/superpowers/specs/2026-09-01-merchant-category-resolution-design.md). Until this
/// existed the pack was an export generated FROM a 127-row Swift array, with no consumer in this
/// repo — so its curated payment-descriptor `matchKeys` were unreachable from the app that needs
/// them most.
final class MerchantPackLoadingTests: XCTestCase {

    func testPackLoadsWithCuratedDescriptorKeysIntact() throws {
        let pack = try SeedLoader.loadMerchantPack()

        let amazon = try XCTUnwrap(pack.merchants.first { $0.id == "amazon-ca" })
        XCTAssertEqual(amazon.displayName, "Amazon.ca")
        XCTAssertTrue(amazon.matchKeys.contains("amzn mktp ca"),
                      "the descriptor needle Apple Pay actually emits must survive the load")
        XCTAssertEqual(amazon.mcc, 5999)
    }

    func testPackVersionRejectsAnUnknownMajor() {
        XCTAssertThrowsError(try SeedLoader.validate(packVersion: "2.0")) { error in
            XCTAssertEqual(error as? SeedLoaderError, .unsupportedCatalogueVersion("2.0"))
        }
    }

    func testPackVersionAcceptsTheKnownMajorRegardlessOfMinor() {
        XCTAssertNoThrow(try SeedLoader.validate(packVersion: "1.0"))
        XCTAssertNoThrow(try SeedLoader.validate(packVersion: "1.9"))
    }

    /// The pack must be a complete superset of the Swift array it replaces, or inverting the
    /// generator would silently drop facts. `merchantBrand` joins a row to the catalogue's
    /// scoring predicates and `notes` carries acceptance caveats the owner is shown.
    func testPackCarriesEveryFieldTheSwiftArrayHeld() throws {
        let pack = try SeedLoader.loadMerchantPack()
        XCTAssertEqual(pack.merchants.count, 127)

        let costco = try XCTUnwrap(pack.merchants.first { $0.id == "costco-wholesale" })
        XCTAssertEqual(costco.category, "wholesaleClub")
        XCTAssertEqual(costco.merchantBrand, "costco")
        XCTAssertEqual(costco.acceptedNetworks, [.mastercard])
        XCTAssertNotNil(costco.notes)
    }
}
