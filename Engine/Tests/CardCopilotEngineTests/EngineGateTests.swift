import XCTest
@testable import CardCopilotEngine

final class EngineGateTests: XCTestCase {
    var engine: RecommendationEngine!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        engine = RecommendationEngine(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadPinnedOwnerState())
    }

    func testPharmacyHoldsDefault() {
        let r = engine.recommend(PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertFalse(r.switchedFromDefault)
        XCTAssertNil(r.suppressedBetterCard, "Tangerine only ties 2%, so nothing is strictly better")
    }

    func testTaxiSuppressionUnderBothSemantics() {
        let r = engine.recommend(PurchaseContext(amountCad: 12, category: "transit", mcc: 4121),
                                 asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "wealthsimple-vip")
        XCTAssertFalse(r.switchedFromDefault)
        XCTAssertEqual(r.suppressedBetterCard?.cardId, "amex-cobalt")
        XCTAssertEqual(r.suppressedBetterCard?.netValueCad ?? .nan, 0.432, accuracy: 0.005)
    }

    func testCostcoDefaultNotAccepted() {
        let r = engine.recommend(PurchaseContext(amountCad: 200, category: "wholesaleClub", mcc: 5300,
                                                 merchantBrand: "costco",
                                                 acceptedNetworks: [.mastercard]), asOf: asOf)
        XCTAssertTrue(r.defaultNotAccepted)
        XCTAssertEqual(r.winner.cardId, "rogers-red-we")
        XCTAssertEqual(r.winner.netValueCad, 3.00, accuracy: 0.005)
    }

    func testGroceryWinnerAndRunnerUp() {
        let r = engine.recommend(PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411,
                                                 merchantBrand: "loblaws"), asOf: asOf)
        XCTAssertEqual(r.winner.cardId, "amex-cobalt")
        XCTAssertTrue(r.switchedFromDefault)
        XCTAssertEqual(r.runnerUp?.cardId, "mbna-rewards-we")
        XCTAssertEqual(r.advantageOverDefaultCad ?? .nan, 7.00, accuracy: 0.005)
    }
}
