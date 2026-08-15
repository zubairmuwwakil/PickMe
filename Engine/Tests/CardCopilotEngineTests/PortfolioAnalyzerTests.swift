import XCTest
@testable import CardCopilotEngine

/// The keep/cancel layer. Every case here exists to defend one claim: a card is worth what the
/// wallet would lose without it, not what it earns.
/// Pinned valuation per decision #16 — a preference change must never re-baseline these numbers.
final class PortfolioAnalyzerTests: XCTestCase {

    private func analyzer(mrCentsPerPoint: Double = 1.8) throws -> PortfolioAnalyzer {
        PortfolioAnalyzer(catalogue: try SeedLoader.loadCatalogue(),
                          ownerState: try SeedLoader.loadPinnedOwnerState(mrCentsPerPoint: mrCentsPerPoint))
    }

    /// $12,000/yr of restaurant spend, MR pinned at 1.8¢.
    ///   Cobalt   5× MR @ 1.8¢ = 9.0%  → $1,080 gross
    ///   MBNA     5× MBNA @ 1.0¢ = 5.0% → $600 if Cobalt were gone
    /// Cobalt is worth the $480 gap, not the $1,080 it earns. Fee $191.88 → $288.12 net.
    func testMarginalValueIsTheGapToTheNextBestCardNotGrossRewards() throws {
        let distribution = SpendDistribution(
            profileId: "dining-only",
            basis: "synthetic: one category, sized to stay under every cap",
            buckets: [.init(label: "Restaurants", annualCad: 12_000, category: "dining", mcc: 5812)])

        let analysis = try analyzer().analyze(distribution, asOf: "2026-08-20")
        let cobalt = try XCTUnwrap(analysis.contributions.first { $0.cardId == "amex-cobalt" })

        XCTAssertEqual(cobalt.grossRewardValueCad, 1_080, accuracy: 0.01)
        XCTAssertEqual(cobalt.marginalValueCad, 480, accuracy: 0.01)
        XCTAssertEqual(cobalt.annualFeeCad, 191.88, accuracy: 0.01)
        XCTAssertEqual(cobalt.netContributionCad, 288.12, accuracy: 0.01)
    }

    /// $60,000/yr of restaurant spend — $5,000 a month — deliberately blows through two caps of
    /// different shapes, and the answer has to survive both.
    ///   Cobalt: $2,500/mo at 5×, the rest at 1× → 15,000 pts/mo @ 1.8¢ = $270 → $3,240/yr
    ///   Without Cobalt the wallet cannot simply fall to MBNA: MBNA's $50,000 *annual* 5× cap is
    ///   spent by the end of month 10, after which Platinum's uncapped 2× @ 1.8¢ ($180/mo) beats
    ///   MBNA's post-cap 1× ($50/mo). So the fallback is $250×10 + $180×2 = $2,860, and Cobalt is
    ///   worth $380 — not the $3,240 it earns, and not the $640 a fallback that ignored MBNA's
    ///   annual cap would have claimed.
    func testMarginalValueHonoursMonthlyAndAnnualCapsAndRecoversWhenACapRunsOut() throws {
        let distribution = SpendDistribution(
            profileId: "dining-over-cap",
            basis: "synthetic: sized to exhaust Cobalt's monthly cap and MBNA's annual cap",
            buckets: [.init(label: "Restaurants", annualCad: 60_000, category: "dining", mcc: 5812)])

        let analyzer = try analyzer()
        let analysis = analyzer.analyze(distribution, asOf: "2026-08-20")
        let cobalt = try XCTUnwrap(analysis.contribution("amex-cobalt"))

        XCTAssertEqual(cobalt.grossRewardValueCad, 3_240, accuracy: 0.01)
        XCTAssertEqual(cobalt.marginalValueCad, 380, accuracy: 0.01)

        // The fallback is not one card — MBNA carries ten months, Platinum the last two.
        let without = analyzer.run(distribution, excluding: ["amex-cobalt"], asOf: "2026-08-20")
        XCTAssertEqual(without.totalValueCad, 2_860, accuracy: 0.01)
        XCTAssertEqual(without.winnersByBucket["Restaurants"], ["mbna-rewards-we", "amex-platinum"])
    }

    // MARK: - Verdicts

    /// A $0 fee card cannot cost the owner anything, so there is no decision to make and no
    /// benefit value it needs to justify — however little it earns.
    func testZeroFeeCardIsFreeToKeepHoweverLittleItEarns() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let tangerine = try XCTUnwrap(analysis.contribution("tangerine-moneyback-world"))

        XCTAssertEqual(tangerine.annualFeeCad, 0)
        XCTAssertEqual(tangerine.verdict, .freeToKeep)
        XCTAssertEqual(tangerine.requiredBenefitValueCad, 0)
    }

    func testCardWhoseMarginalValueClearsItsFeeIsAKeepAndNeedsNoBenefits() throws {
        let distribution = SpendDistribution(
            profileId: "dining-only", basis: "synthetic",
            buckets: [.init(label: "Restaurants", annualCad: 12_000, category: "dining", mcc: 5812)])

        let cobalt = try XCTUnwrap(try analyzer().analyze(distribution, asOf: "2026-08-20")
            .contribution("amex-cobalt"))

        XCTAssertEqual(cobalt.verdict, .keep)
        XCTAssertEqual(cobalt.requiredBenefitValueCad, 0)
    }

    /// Platinum at the MR cash floor: Cobalt already out-earns it everywhere it could win, so the
    /// $799 rests entirely on lounges, credits and insurance — which this engine refuses to price.
    /// The deliverable is the threshold, not a guess at what those are worth.
    func testPlatinumFeeIsDisclosedAsARequiredBenefitValueNotAnInventedOne() throws {
        let platinum = try XCTUnwrap(try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
            .contribution("amex-platinum"))

        XCTAssertEqual(platinum.annualFeeCad, 799)
        XCTAssertLessThan(platinum.marginalValueCad, platinum.annualFeeCad)
        XCTAssertEqual(platinum.requiredBenefitValueCad,
                       799 - platinum.marginalValueCad, accuracy: 0.01)
        // Cancel, not downgrade: Cobalt keeps the Membership Rewards balance alive without it.
        XCTAssertEqual(platinum.verdict, .cancel)
    }

    /// Bonvoy earns something no other card can (5× at Marriott) but nowhere near its $120, and it
    /// is the wallet's only Bonvoy card — cancelling outright forfeits the currency, so the honest
    /// verdict is "cheaper product in the same family", not "cancel".
    func testSoleHolderOfARewardsProgramIsADowngradeRatherThanACancel() throws {
        let bonvoy = try XCTUnwrap(try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
            .contribution("amex-bonvoy"))

        XCTAssertGreaterThan(bonvoy.marginalValueCad, 0)
        XCTAssertLessThan(bonvoy.marginalValueCad, 120)
        XCTAssertEqual(bonvoy.verdict, .downgrade)
    }

    /// Crypto.com is gated out by owner state (Level Up Pro inactive), so it earns nothing on any
    /// purchase. That has to read as "not in play", not as a card that happens to score zero.
    func testCardGatedOutByOwnerStateIsMarkedNeverScorable() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let crypto = try XCTUnwrap(analysis.contribution("cryptocom-royal-indigo"))

        XCTAssertTrue(crypto.neverScorable)
        XCTAssertEqual(crypto.marginalValueCad, 0, accuracy: 0.01)
        XCTAssertTrue(analysis.contributions.filter(\.neverScorable).map(\.cardId)
            == ["cryptocom-royal-indigo"])
    }

    /// Wealthsimple's $240 is waived on assets or direct deposit and the owner hasn't told us
    /// which — so the verdict is computed at the stated fee and flagged, never guessed either way.
    func testConditionalFeeIsFlaggedRatherThanAssumedWaived() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let wealthsimple = try XCTUnwrap(analysis.contribution("wealthsimple-vip"))

        XCTAssertTrue(wealthsimple.feeWaiverUnresolved)
        XCTAssertEqual(wealthsimple.annualFeeCad, 240)
        XCTAssertFalse(try XCTUnwrap(analysis.contribution("amex-cobalt")).feeWaiverUnresolved)
    }

    // MARK: - Why a marginal value is what it is

    /// A marginal value on its own is an unexplained number. Naming the card that absorbs the
    /// spend is what turns "$480" into an argument the owner can check.
    func testMarginalValueNamesTheCardThatAbsorbsTheSpend() throws {
        let distribution = SpendDistribution(
            profileId: "dining-only", basis: "synthetic",
            buckets: [.init(label: "Restaurants", annualCad: 12_000, category: "dining", mcc: 5812)])

        let cobalt = try XCTUnwrap(try analyzer().analyze(distribution, asOf: "2026-08-20")
            .contribution("amex-cobalt"))

        XCTAssertEqual(cobalt.backfilledBy.map(\.cardId), ["mbna-rewards-we"])
        XCTAssertEqual(cobalt.backfilledBy.first?.valueRetainedCad ?? 0, 600, accuracy: 0.01)
        XCTAssertEqual(cobalt.backfilledBy.first?.bucketLabels, ["Restaurants"])
    }

    /// The failure mode that makes a marginal-value table dangerous on its own. At the MR cash
    /// floor Cobalt's 5× and MBNA's 5× pay identically on groceries and dining, so each card's
    /// individual marginal value is tiny — cancel either one and nothing much happens. Cancel both
    /// and the wallet falls to Scotia's 4% and a 2% floor. A report that prints only the individual
    /// numbers reads as "cancel both", which is wrong by hundreds of dollars a year.
    func testTwoCardsThatCoverForEachOtherAreReportedAsAPairNotTwoCancels() throws {
        let analyzer = try analyzer(mrCentsPerPoint: 1.0)
        let analysis = analyzer.analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let cobalt = try XCTUnwrap(analysis.contribution("amex-cobalt"))
        let mbna = try XCTUnwrap(analysis.contribution("mbna-rewards-we"))

        XCTAssertLessThan(cobalt.marginalValueCad, cobalt.annualFeeCad)
        XCTAssertLessThan(mbna.marginalValueCad, mbna.annualFeeCad)

        let pair = try XCTUnwrap(analysis.redundantPairs
            .first { $0.cardIds == ["amex-cobalt", "mbna-rewards-we"] })
        XCTAssertGreaterThan(pair.jointMarginalCad, pair.sumOfIndividualMarginalsCad + 100)
        XCTAssertEqual(pair.combinedAnnualFeeCad, 311.88, accuracy: 0.01)
        XCTAssertEqual(pair.jointMarginalCad,
                       analyzer.marginalValue(ofRemoving: ["amex-cobalt", "mbna-rewards-we"],
                                              from: .placeholderCanadianHousehold,
                                              asOf: "2026-08-20"),
                       accuracy: 0.01)
    }

    /// Almost any two cards overlap by a few dollars. Reporting every such pair buries the two
    /// that matter, so a pair has to be materially redundant — worth at least a tenth of the fees
    /// at stake — before it earns a line.
    func testTrivialOverlapIsNotReportedAsRedundancy() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")

        for pair in analysis.redundantPairs {
            let overlap = pair.jointMarginalCad - pair.sumOfIndividualMarginalsCad
            XCTAssertGreaterThanOrEqual(overlap, 0.1 * pair.combinedAnnualFeeCad,
                                        "\(pair.cardIds) overlap by only \(overlap) against "
                                        + "\(pair.combinedAnnualFeeCad) of fees — noise, not a pair")
        }
        // MBNA and Wealthsimple overlap by about a dollar against $360 of fees.
        XCTAssertNil(analysis.redundantPairs
            .first { $0.cardIds == ["mbna-rewards-we", "wealthsimple-vip"] })
        // ...while Cobalt and MBNA, which pay the same 5x on the same categories, do qualify.
        XCTAssertNotNil(analysis.redundantPairs
            .first { $0.cardIds == ["amex-cobalt", "mbna-rewards-we"] })
    }
}
