import Foundation
import XCTest
@testable import CardCopilotStore

/// Store bundles the canonical merchant-MCC seed for offline checkout. These copies are runtime
/// packaging only: `contracts/merchant-mcc-graph` remains the one place the data may be authored.
final class MerchantMCCSeedResourceSyncTests: XCTestCase {
    func testBundledGraphBytesMatchCanonicalContracts() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let canonical = repoRoot.appendingPathComponent("contracts/merchant-mcc-graph")
        let bundled = repoRoot.appendingPathComponent("Store/Sources/CardCopilotStore/Resources")

        var copies: [(canonical: String, bundled: String)] = [
            ("manifest.json", "merchant-mcc-manifest.json"),
            ("profiles.json", "merchant-mcc-profiles.json"),
            ("observations.json", "merchant-mcc-observations.json")
        ]
        struct Manifest: Decodable {
            struct Files: Decodable { let merchantShards: [String] }
            let files: Files
        }
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: canonical.appendingPathComponent("manifest.json")))
        copies += manifest.files.merchantShards.map { ($0, "merchant-mcc-\($0)") }

        for pair in copies {
            let source = canonical.appendingPathComponent(pair.canonical)
            let copy = bundled.appendingPathComponent(pair.bundled)
            XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: source),
                           "Bundled MCC graph drifted: \(pair.bundled). Run scripts/sync-merchant-mcc-graph-into-store.sh")
        }
    }
}
