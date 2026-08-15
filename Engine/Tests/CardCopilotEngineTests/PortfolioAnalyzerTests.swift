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
}
