import XCTest
@testable import CardCopilotEngine

/// Adding a card is the reverse counterfactual of removing one: only the portfolio delta counts.
/// These tests pin the separation between owned cards and researched candidates as tightly as the
/// keep/cancel suite pins marginal value.
final class AcquisitionAnalyzerTests: XCTestCase {
    private func analyzer(ownerState: OwnerState? = nil) throws -> AcquisitionAnalyzer {
        AcquisitionAnalyzer(catalogue: try SeedLoader.loadCatalogue(),
                            candidateCardIds: try SeedLoader.loadCandidateCatalogue().cardIds,
                            ownerState: try ownerState ?? SeedLoader.loadOwnerState())
    }

    /// Replaces `testCandidateCatalogueIsSeparateFromTheOwnedWallet`, whose two assertions both
    /// encoded the conflation removed on 2026-08-24: that the catalogue IS the owner's wallet, and
    /// that candidates live in a second card corpus. Neither holds now — the catalogue is every
    /// supported product, and candidates are ids into it.
    ///
    /// What must still hold is the property those assertions were protecting: ownership, not file
    /// membership, decides eligibility. A candidate is by definition unowned, and
    /// RecommendationEngine scores only `ownedCardIds` (RecommendationEngine.swift), so widening
    /// the corpus cannot put an unowned product in front of someone at a till. The 27 golden
    /// fixtures are the empirical half of that claim.
    func testCandidatesResolveInTheCorpusAndAreNeverOwned() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let candidates = try SeedLoader.loadCandidateCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let known = Set(catalogue.cards.map(\.cardId))
        let owned = Set(owner.ownedCardIds)

        XCTAssertEqual(candidates.cardIds.count, 6)
        XCTAssertTrue(Set(candidates.cardIds).isSubset(of: known),
                      "a candidate must name a product the catalogue defines")
        XCTAssertTrue(Set(candidates.cardIds).isDisjoint(with: owned),
                      "a candidate is by definition a card the owner does not hold")
        XCTAssertTrue(owned.isSubset(of: known),
                      "the owner cannot hold a card the catalogue does not define")
        XCTAssertEqual(known.count, catalogue.cards.count, "no duplicate cardIds in the corpus")
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
        owner.ownedCardIds.append("simplii-cashback-visa")

        let result = try analyzer(ownerState: owner)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")

        XCTAssertNil(result.candidate("simplii-cashback-visa"))
        XCTAssertTrue(result.walletCardIds.contains("simplii-cashback-visa"),
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
