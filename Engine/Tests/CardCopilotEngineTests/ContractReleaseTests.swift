import XCTest
@testable import CardCopilotEngine

final class ContractReleaseTests: XCTestCase {

    /// The stamp must be reachable from running code, not just from CI. Without this, a
    /// prediction can record which rules it used only by implication from the build.
    func testReleaseStampLoadsFromBundle() throws {
        let stamp = try SeedLoader.loadContractRelease()
        XCTAssertFalse(stamp.release.isEmpty)
        XCTAssertTrue(stamp.digest.hasPrefix("sha256:"),
                      "digest is content-addressed and carries its algorithm prefix")
        XCTAssertFalse(stamp.files.isEmpty)
    }

    /// The stamp travels with the bytes it describes. If these disagree, the stamp is
    /// describing a catalogue that is not the one loaded.
    func testStampAgreesWithTheLoadedCatalogue() throws {
        let stamp = try SeedLoader.loadContractRelease()
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(stamp.catalogueVersion, catalogue.catalogueVersion)
    }

    /// Every file the release claims to cover must be one this build can name.
    func testStampCoversTheCardCatalogue() throws {
        let stamp = try SeedLoader.loadContractRelease()
        XCTAssertNotNil(stamp.files["card-catalogue.json"])
    }
}
