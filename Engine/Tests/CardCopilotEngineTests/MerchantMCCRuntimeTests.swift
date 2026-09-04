import XCTest
@testable import CardCopilotEngine

final class MerchantMCCRuntimeTests: XCTestCase {
    func testBundledRuntimeSeedLoadsAll500Merchants() throws {
        let seed = try SeedLoader.loadMerchantMCCRuntimeSeed()
        XCTAssertEqual(seed.graphVersion, "1.0")
        XCTAssertEqual(seed.merchants.count, 500)

        let walmart = try XCTUnwrap(seed.merchants.first { $0.id == "walmart" })
        XCTAssertEqual(walmart.seedMcc, 5411)
        XCTAssertTrue(walmart.candidateMccs.contains(5411))
        XCTAssertTrue(walmart.candidateMccs.contains(5441))
    }

    func testExactFeedbackMovesPosteriorWithoutBecomingNetworkEvidence() {
        let seed = MerchantMCCSeedMerchant(id: "merchant", name: "Merchant", seedMcc: 5411,
                                           candidateMccs: [5411, 5912], weights: [0.5, 0.5],
                                           confidence: 0.40)
        let evidence = [
            MerchantMCCRuntimeEvidence(merchantId: seed.id, mcc: 5912,
                                       type: .userEnteredExactMcc,
                                       sourceFingerprint: "purchase-1"),
            MerchantMCCRuntimeEvidence(merchantId: seed.id, mcc: 5912,
                                       type: .userEnteredExactMcc,
                                       sourceFingerprint: "purchase-2")
        ]

        let result = MerchantMCCPosteriorResolver.posterior(seed: seed, evidence: evidence)
        XCTAssertEqual(result.topMcc, 5912)
        XCTAssertGreaterThan(result.confidence, 0.80)
        XCTAssertEqual(result.evidenceCount, 2)
    }

    func testLocationEvidenceDoesNotLeakIntoBrandLevelPosterior() {
        let seed = MerchantMCCSeedMerchant(id: "merchant", name: "Merchant", seedMcc: 5411,
                                           candidateMccs: [5411], weights: [1], confidence: 0.30)
        let evidence = [
            MerchantMCCRuntimeEvidence(merchantId: seed.id, mcc: 5912,
                                       type: .userEnteredExactMcc,
                                       locationKey: "mapkit:one",
                                       sourceFingerprint: "purchase-1")
        ]

        let brand = MerchantMCCPosteriorResolver.posterior(seed: seed, evidence: evidence)
        let location = MerchantMCCPosteriorResolver.posterior(seed: seed, evidence: evidence,
                                                               locationKey: "mapkit:one")
        XCTAssertEqual(brand.topMcc, 5411)
        XCTAssertEqual(brand.evidenceCount, 0)
        XCTAssertEqual(location.topMcc, 5912)
        XCTAssertEqual(location.evidenceCount, 1)
    }
}
