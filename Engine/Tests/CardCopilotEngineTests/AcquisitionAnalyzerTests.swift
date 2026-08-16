import XCTest
@testable import CardCopilotEngine

/// Adding a card is the reverse counterfactual of removing one: only the portfolio delta counts.
/// These tests pin the separation between owned cards and researched candidates as tightly as the
/// keep/cancel suite pins marginal value.
final class AcquisitionAnalyzerTests: XCTestCase {
    private func analyzer(ownerState: OwnerState? = nil) throws -> AcquisitionAnalyzer {
        AcquisitionAnalyzer(walletCatalogue: try SeedLoader.loadCatalogue(),
                            candidateCatalogue: try SeedLoader.loadCandidateCatalogue(),
                            ownerState: try ownerState ?? SeedLoader.loadOwnerState())
    }

    func testCandidateCatalogueIsSeparateFromTheOwnedWallet() throws {
        let wallet = try SeedLoader.loadCatalogue()
        let candidates = try SeedLoader.loadCandidateCatalogue()
        let owner = try SeedLoader.loadOwnerState()

        XCTAssertEqual(Set(wallet.cards.map(\.cardId)), Set(owner.ownedCardIds))
        XCTAssertTrue(Set(wallet.cards.map(\.cardId))
            .isDisjoint(with: candidates.cards.map(\.cardId)))
        XCTAssertEqual(candidates.cards.count, 6)
    }

    /// BMO earns $120 gross across gas and transit, but the existing wallet already earns $72 on
    /// that spend. Its acquisition value is only the $48 gap, then the recurring fee is charged.
    func testAcquisitionUsesPortfolioDeltaNotCandidateGrossRewards() throws {
        let result = try analyzer().analyze(.placeholderCanadianHousehold,
                                            asOf: "2026-08-20")
        let bmo = try XCTUnwrap(result.candidate("bmo-cashback-world-elite"))

        XCTAssertEqual(bmo.grossRewardValueCad, 120, accuracy: 0.01)
        XCTAssertEqual(bmo.marginalRewardValueCad, 48, accuracy: 0.01)
        XCTAssertEqual(bmo.annualFeeCad, 139, accuracy: 0.01)
        XCTAssertEqual(bmo.netAnnualValueCad, -91, accuracy: 0.01)
        XCTAssertEqual(bmo.requiredBenefitValueCad, 91, accuracy: 0.01)
        XCTAssertEqual(bmo.verdict, .benefitsRequired)
        XCTAssertEqual(bmo.bucketGains.map(\.label), ["Gas", "Transit & rideshare"])
        XCTAssertEqual(bmo.bucketGains.first?.displacedCardIds, ["wealthsimple-vip"])
    }

    /// This is the differentiated answer, even when it is commercially inconvenient: against an
    /// already broad ten-card wallet, none of the researched products earns its recurring fee.
    func testAnalyzerCanHonestlyRecommendNoNewCard() throws {
        let result = try analyzer().analyze(.placeholderCanadianHousehold,
                                            asOf: "2026-08-20")

        XCTAssertTrue(result.recommended.isEmpty)
        XCTAssertEqual(result.candidates.count, 6)
        XCTAssertEqual(result.candidates.map(\.cardId).first,
                       "home-trust-preferred-visa")
        XCTAssertTrue(result.candidates.allSatisfy { $0.netAnnualValueCad <= 0.01 })
    }

    func testOwnedCandidateIsNeverPresentedAsSomethingToAcquire() throws {
        var owner = try SeedLoader.loadOwnerState()
        owner.ownedCardIds.append("simplii-cash-back-visa")

        let result = try analyzer(ownerState: owner)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")

        XCTAssertNil(result.candidate("simplii-cash-back-visa"))
        XCTAssertTrue(result.walletCardIds.contains("simplii-cash-back-visa"),
                      "an owned former candidate belongs in the baseline, not merely off the list")
        XCTAssertEqual(result.candidates.count, 5)
    }

    /// The engine simulates the actual monthly cap, not 4% across the whole category.
    func testCandidateCounterfactualCarriesCapProgressForward() throws {
        let transit = SpendDistribution(
            profileId: "heavy-transit", basis: "synthetic",
            buckets: [.init(label: "Transit", annualCad: 12_000,
                            category: "transit", mcc: 4121)])
        let bmo = try XCTUnwrap(try analyzer().analyze(transit, asOf: "2026-08-20")
            .candidate("bmo-cashback-world-elite"))

        // $300/mo × 4% + $700/mo × 1% = $228, below the wallet's existing $240. An
        // implementation that ignored the cap would claim $480 and falsely recommend the card.
        XCTAssertEqual(bmo.grossRewardValueCad, 0, accuracy: 0.01)
        XCTAssertEqual(bmo.marginalRewardValueCad, 0, accuracy: 0.01)
        XCTAssertEqual(bmo.verdict, .noEarnAdvantage)
    }
}
