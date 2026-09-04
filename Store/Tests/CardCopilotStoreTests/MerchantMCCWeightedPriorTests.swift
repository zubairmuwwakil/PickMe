import XCTest
@testable import CardCopilotStore

final class MerchantMCCWeightedPriorTests: XCTestCase {
    func testWeightedSeedProfilePreservesCandidateDistribution() throws {
        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Example Merchant"),
            seedCandidates: [
                MerchantMCCPriorCandidate(mcc: 5411, weight: 0.7),
                MerchantMCCPriorCandidate(mcc: 5912, weight: 0.3)
            ],
            seedConfidence: 0.40,
            evidence: [])

        XCTAssertEqual(prediction.bestMCC, 5411)
        let grocery = try XCTUnwrap(prediction.candidates.first { $0.mcc == 5411 })
        let pharmacy = try XCTUnwrap(prediction.candidates.first { $0.mcc == 5912 })
        XCTAssertEqual(grocery.share, 0.7, accuracy: 0.0001)
        XCTAssertEqual(pharmacy.share, 0.3, accuracy: 0.0001)
        XCTAssertFalse(prediction.isObserved)
        XCTAssertFalse(prediction.isTrusted)
    }

    func testAddingCandidateMCCsDoesNotMultiplyPriorStrength() throws {
        let one = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "One"),
            seedCandidates: [MerchantMCCPriorCandidate(mcc: 5411, weight: 1)],
            seedConfidence: 0.40,
            evidence: [])
        let many = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Many"),
            seedCandidates: [
                MerchantMCCPriorCandidate(mcc: 5411, weight: 0.5),
                MerchantMCCPriorCandidate(mcc: 5912, weight: 0.5)
            ],
            seedConfidence: 0.40,
            evidence: [])

        XCTAssertEqual(one.candidates.reduce(0) { $0 + $1.score }, 0.40, accuracy: 0.0001)
        XCTAssertEqual(many.candidates.reduce(0) { $0 + $1.score }, 0.40, accuracy: 0.0001)
    }
}
