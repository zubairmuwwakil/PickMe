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
}
