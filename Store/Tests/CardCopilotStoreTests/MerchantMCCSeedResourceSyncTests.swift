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
        copies += stride(from: 1, through: 451, by: 50).map { start in
            let end = start + 49
            let shard = String(format: "merchants-%03d-%03d.json", start, end)
            return (shard, "merchant-mcc-\(shard)")
        }

        for pair in copies {
            let source = canonical.appendingPathComponent(pair.canonical)
            let copy = bundled.appendingPathComponent(pair.bundled)
            XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: source),
                           "Bundled MCC graph drifted: \(pair.bundled). Run scripts/sync-merchant-mcc-graph-into-store.sh")
        }
    }
}
