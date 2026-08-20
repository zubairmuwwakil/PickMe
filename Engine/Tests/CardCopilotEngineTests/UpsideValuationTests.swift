import XCTest
@testable import CardCopilotEngine

/// When the owner values points at the guaranteed cash floor — the honest setting for someone
/// who has never transferred — the engine recommends conservatively, but it must still say what
/// the conservatism is costing: the value at which a points card would take over.
final class UpsideValuationTests: XCTestCase {
    var engine: RecommendationEngine!
    var explainer: RecommendationExplainer!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        var state = try SeedLoader.loadOwnerState()
        state.withPointsValuation {
            $0.centsPerPoint = 1.0
            $0.aspirationalCentsPerPoint = 2.2
        }
        engine = RecommendationEngine(catalogue: catalogue, ownerState: state)
        explainer = RecommendationExplainer(catalogue: catalogue)
    }

    func testGasDisclosesWhatTransferringWouldBeWorth() {
        // Cobalt 2x ties WS at 1.0¢, so the default holds; Cobalt takes over at 1.25¢.
        let r = engine.recommend(PurchaseContext(amountCad: 70, category: "gasStation", mcc: 5541),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertTrue(r.valuationSensitive)
        XCTAssertEqual(r.valuationDirection, .above)
        XCTAssertEqual(r.alternateWinnerCardId, "amex-cobalt")
        XCTAssertEqual(r.breakevenCentsPerPoint ?? .nan, 1.25, accuracy: 0.005)
    }

    func testTaxiBreakevenUsesCashLegOfThreshold() {
        // On $25 the $0.25 leg exceeds the 0.5pp leg ($0.125): (0.50 + 0.25) × 100 / 50 = 1.50¢.
        let r = engine.recommend(PurchaseContext(amountCad: 25, category: "transit", mcc: 4121),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertEqual(r.valuationDirection, .above)
        XCTAssertEqual(r.breakevenCentsPerPoint ?? .nan, 1.50, accuracy: 0.005)
    }

    func testNetflixComparesAgainstTheNonDefaultIncumbent() {
        // MBNA wins at the floor; Cobalt overtakes it at 1.6667¢ — no threshold applies
        // between two non-default cards.
        let r = engine.recommend(PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                                                 merchantBrand: "netflix", channel: "online",
                                                 recurringIndicator: true), asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "mbna-rewards-we")
        XCTAssertEqual(r.valuationDirection, .above)
        XCTAssertEqual(r.alternateWinnerCardId, "amex-cobalt")
        XCTAssertEqual(r.breakevenCentsPerPoint ?? .nan, 1.6667, accuracy: 0.005)
    }

    func testGroceryStaysValuationProofEvenAtTheFloor() {
        // Cobalt 5x still wins at 1.0¢; nothing to disclose in either direction.
        let r = engine.recommend(PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411,
                                                 merchantBrand: "loblaws"), asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "amex-cobalt")
        XCTAssertFalse(r.valuationSensitive)
        XCTAssertNil(r.valuationDirection)
    }

    func testImplausibleBreakevenIsNotDisclosed() {
        // Pharmacy: Cobalt only overtakes above 2.83¢, beyond the 2.2¢ published benchmark.
        // Disclosing it would be noise, not information.
        let r = engine.recommend(PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertFalse(r.valuationSensitive)
        XCTAssertNil(r.breakevenCentsPerPoint)
    }

    func testExplainerStatesTheUpsideSymmetrically() {
        let p = PurchaseContext(amountCad: 70, category: "gasStation", mcc: 5541)
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertEqual(e.valuationLine,
                       "Assumes your points are worth 1.00¢ each. Above about 1.25¢, American Express Cobalt Card wins instead.")
    }
}
