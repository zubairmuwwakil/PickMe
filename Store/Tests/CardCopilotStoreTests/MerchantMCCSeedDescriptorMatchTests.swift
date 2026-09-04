import XCTest
@testable import CardCopilotStore

final class MerchantMCCSeedDescriptorMatchTests: XCTestCase {
    func testMultiwordSeedMerchantAllowsDescriptorSuffixes() throws {
        let match = try XCTUnwrap(
            MerchantMCCSeedCatalogue.match(merchantName: "Healthy Planet #123 Toronto"))
        XCTAssertEqual(match.merchant.id, "healthy-planet")
    }

    func testOneWordSeedDoesNotSubstringMatchDifferentBusiness() {
        XCTAssertNil(MerchantMCCSeedCatalogue.match(merchantName: "Metro Pizza"),
                     "one-word seed names must not expand into unrelated businesses")
        XCTAssertNil(MerchantMCCSeedCatalogue.match(merchantName: "Metropolitan Hotel"))
    }
}
