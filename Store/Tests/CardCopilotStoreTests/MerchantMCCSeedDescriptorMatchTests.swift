import XCTest
@testable import CardCopilotStore

final class MerchantMCCSeedDescriptorMatchTests: XCTestCase {
    func testMultiwordSeedMerchantAllowsDescriptorSuffixes() throws {
        let match = try XCTUnwrap(
            MerchantMCCSeedCatalogue.match(merchantName: "Healthy Planet #123 Toronto"))
        XCTAssertEqual(match.merchant.id, "healthy-planet")
    }

    func testSeedMatchingDoesNotUseRawSubstrings() {
        XCTAssertNil(MerchantMCCSeedCatalogue.match(merchantName: "Metropolitan Hotel"),
                     "Metro must not leak into unrelated words")
    }
}
