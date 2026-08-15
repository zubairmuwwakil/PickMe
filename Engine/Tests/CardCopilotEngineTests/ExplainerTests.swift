import XCTest
@testable import CardCopilotEngine

final class ExplainerTests: XCTestCase {
    var engine: RecommendationEngine!
    var explainer: RecommendationExplainer!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        engine = RecommendationEngine(catalogue: catalogue,
                                      ownerState: try SeedLoader.loadOwnerState())
        explainer = RecommendationExplainer(catalogue: catalogue)
    }

    func testGroceryExplanation() {
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertEqual(e.headline,
                       "Use American Express Cobalt Card — about $9.00 back on this $100.00 purchase.")
        XCTAssertEqual(e.runnerUpLine,
                       "Next best: MBNA Rewards World Elite Mastercard ($5.00) — you'd give up $4.00.")
    }

    func testTaxiSuppressionExplanation() {
        let p = PurchaseContext(amountCad: 12, category: "transit", mcc: 4121)
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertEqual(e.headline,
                       "Stay on Wealthsimple Visa Infinite Privilege Credit Card — about $0.24 back on this $12.00 purchase.")
        XCTAssertEqual(e.runnerUpLine,
                       "American Express Cobalt Card is marginally better (+$0.19) — not worth the wallet dig.")
    }

    func testDrawerCardWarningSurfaces() {
        let p = PurchaseContext(amountCad: 150, category: "ctFamily", mcc: 5200,
                                merchantBrand: "canadian-tire")
        let e = explainer.explain(engine.recommend(p, asOf: asOf), purchase: p)
        XCTAssertTrue(e.headline.hasPrefix("Use Triangle World Elite Mastercard"))
        XCTAssertTrue(e.warningLines.contains("This card is in your drawer — bring it or take the runner-up."))
    }
}
