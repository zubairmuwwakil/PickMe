import XCTest
@testable import CardCopilotEngine

/// The valuation-honesty layer: the engine ranks by the owner's declared point value, but it
/// must DETECT when the winner depends on that declaration and DISCLOSE the breakeven —
/// the cents-per-point at which the recommendation flips to the guaranteed-floor winner.
final class ValuationPolicyTests: XCTestCase {
    var engine: RecommendationEngine!
    var explainer: RecommendationExplainer!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        // Pinned above the floor: this suite documents behaviour when the owner declares a
        // value they cannot guarantee, independent of the live seed.
        let state = try SeedLoader.loadPinnedOwnerState()
        engine = RecommendationEngine(catalogue: catalogue, ownerState: state)
        explainer = RecommendationExplainer(catalogue: catalogue)
    }

    func testGroceryIsValuationProof() {
        // Cobalt 5x wins even at the 1.0¢ floor (700 pts = $7.00 ties MBNA, tie-break holds).
        let r = engine.recommend(PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411,
                                                 merchantBrand: "loblaws"), asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "amex-cobalt")
        XCTAssertFalse(r.valuationSensitive)
        XCTAssertNil(r.breakevenCentsPerPoint)
    }

    func testCoffeeIsValuationSensitiveAgainstDefault() {
        // Cobalt 30 pts vs WS $0.12; the $0.25 switch floor sets the breakeven:
        // (0.12 + 0.25) × 100 / 30 = 1.2333¢.
        let r = engine.recommend(PurchaseContext(amountCad: 6, category: "dining", mcc: 5814),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "amex-cobalt")
        XCTAssertTrue(r.valuationSensitive)
        XCTAssertEqual(r.alternateWinnerCardId, "wealthsimple-vip")
        XCTAssertEqual(r.valuationDirection, .below)
        XCTAssertEqual(r.breakevenCentsPerPoint ?? .nan, 1.2333, accuracy: 0.005)
    }

    func testNetflixIsValuationSensitiveAgainstMbna() {
        // Cobalt 46.47 pts vs MBNA $0.7745 (non-default rival): 0.7745 × 100 / 46.47 = 1.6667¢.
        let r = engine.recommend(PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                                                 merchantBrand: "netflix", channel: "online",
                                                 recurringIndicator: true), asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "amex-cobalt")
        XCTAssertTrue(r.valuationSensitive)
        XCTAssertEqual(r.alternateWinnerCardId, "mbna-rewards-we")
        XCTAssertEqual(r.valuationDirection, .below)
        XCTAssertEqual(r.breakevenCentsPerPoint ?? .nan, 1.6667, accuracy: 0.005)
    }

    func testGasBreakevenUsesPercentageFloorOfThreshold() {
        // Cobalt 140 pts vs WS $1.40; on $70 the 0.5pp leg ($0.35) exceeds the $0.25 leg:
        // (1.40 + 0.35) × 100 / 140 = 1.25¢.
        let r = engine.recommend(PurchaseContext(amountCad: 70, category: "gasStation", mcc: 5541),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "amex-cobalt")
        XCTAssertTrue(r.valuationSensitive)
        XCTAssertEqual(r.breakevenCentsPerPoint ?? .nan, 1.25, accuracy: 0.005)
    }

    func testNonPointsWinnerIsNeverSensitive() {
        // Pharmacy: WS wins outright; no valuation dependency to disclose.
        let r = engine.recommend(PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertFalse(r.valuationSensitive)
        XCTAssertNil(r.breakevenCentsPerPoint)
    }

    func testScorerExposesFloorNetValue() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadPinnedOwnerState()
        let cobalt = catalogue.cards.first { $0.cardId == "amex-cobalt" }!
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411,
                                merchantBrand: "loblaws")
        let s = Scorer.score(card: cobalt, purchase: p, ownerState: owner, asOf: asOf)
        XCTAssertEqual(s.netValueCad, 9.00, accuracy: 0.005, "500 pts at declared 1.8¢")
        XCTAssertEqual(s.floorNetValueCad, 5.00, accuracy: 0.005, "500 pts at the 1.0¢ cash floor")
    }

    func testExplainerDisclosesTheBreakeven() {
        let p = PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                                merchantBrand: "netflix", channel: "online", recurringIndicator: true)
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertEqual(e.valuationLine,
                       "Assumes your points are worth 1.80¢ each. Below about 1.67¢, MBNA Rewards World Elite Mastercard wins instead.")
    }

    func testExplainerSilentWhenValuationProof() {
        let p = PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411,
                                merchantBrand: "loblaws")
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertNil(e.valuationLine)
    }
}

/// The engine computes the breakeven analytically. This proves the formula agrees with the
/// engine's own behaviour by bisecting the real `recommend` call — if they ever diverge, the
/// disclosed number is lying to the user, which is worse than disclosing nothing.
final class BreakevenCrossValidationTests: XCTestCase {
    func testAnalyticBreakevenMatchesBisection() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadPinnedOwnerState()
        let mrCards = Set(catalogue.cards
            .filter { $0.program.programId == "amexMembershipRewards" }
            .map(\.cardId))
        let asOf = "2026-08-20"

        func winnerId(_ p: PurchaseContext, mr: Double) -> String {
            var s = owner
            s.withPointsValuation { $0.centsPerPoint = mr }
            return RecommendationEngine(catalogue: catalogue, ownerState: s)
                .recommend(p, asOf: asOf).winner.cardId
        }

        let purchases: [(String, PurchaseContext)] = [
            ("coffee", PurchaseContext(amountCad: 6, category: "dining", mcc: 5814)),
            ("gas", PurchaseContext(amountCad: 70, category: "gasStation", mcc: 5541)),
            ("taxi", PurchaseContext(amountCad: 25, category: "transit", mcc: 4121)),
            ("flight", PurchaseContext(amountCad: 600, category: "travel", mcc: 3000)),
            ("netflix", PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                                        merchantBrand: "netflix", channel: "online",
                                        recurringIndicator: true)),
        ]

        for (label, purchase) in purchases {
            let engine = RecommendationEngine(catalogue: catalogue, ownerState: owner)
            let rec = engine.recommend(purchase, asOf: asOf)
            guard let analytic = rec.breakevenCentsPerPoint else {
                XCTFail("\(label): expected a valuation-sensitive recommendation")
                continue
            }
            // Bisect the engine itself for the point where the winner becomes a points card.
            var low = 0.5, high = 6.0
            for _ in 0..<50 {
                let mid = (low + high) / 2
                if mrCards.contains(winnerId(purchase, mr: mid)) { high = mid } else { low = mid }
            }
            XCTAssertEqual(analytic, high, accuracy: 0.01,
                           "\(label): analytic breakeven disagrees with the engine's actual flip point")
        }
    }
}
