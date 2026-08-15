import XCTest
@testable import CardCopilotEngine

final class ScorerTests: XCTestCase {
    var catalogue: Catalogue!
    var owner: OwnerState!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        catalogue = try SeedLoader.loadCatalogue()
        owner = try SeedLoader.loadOwnerState()
    }

    private func card(_ id: String) -> CardProduct { catalogue.cards.first { $0.cardId == id }! }

    private func score(_ id: String, _ p: PurchaseContext, _ o: OwnerState? = nil) -> CandidateScore {
        Scorer.score(card: card(id), purchase: p, ownerState: o ?? owner, asOf: asOf)
    }

    func testCobaltGrocery100() {
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        let s = score("amex-cobalt", p)
        XCTAssertEqual(s.rewardUnits, 500, accuracy: 0.005)
        XCTAssertEqual(s.netValueCad, 9.00, accuracy: 0.005)
        XCTAssertEqual(s.appliedRuleId, "cobalt-eats-5x")
    }

    func testCobaltCapProration() {
        var o = owner!
        o.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"] = 2450
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        let s = score("amex-cobalt", p, o)
        XCTAssertEqual(s.rewardUnits, 300, accuracy: 0.005, "50 at 5x plus 50 at 1x")
        XCTAssertEqual(s.netValueCad, 5.40, accuracy: 0.005)
        XCTAssertTrue(s.warnings.contains(.capNearlyExhausted))
    }

    func testWealthsimpleUsdNoFx() {
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        let s = score("wealthsimple-vip", p)
        XCTAssertEqual(s.netValueCad, 3.30, accuracy: 0.005)
        XCTAssertEqual(s.fxCostCad, 0, accuracy: 0.005)
    }

    func testCobaltUsdGoesNegative() {
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        let s = score("amex-cobalt", p)
        XCTAssertEqual(s.netValueCad, -1.155, accuracy: 0.005, "2.97 gross minus 4.125 FX")
        XCTAssertTrue(s.warnings.contains(.negativeNetValue))
    }

    func testCryptoProAutoSell() {
        var o = owner!
        o.cardStates["cryptocom-royal-indigo"]?.cryptoLevelUpProActive = true
        o.cardStates["cryptocom-royal-indigo"]?.croHandling = "autoSell"
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        let s = score("cryptocom-royal-indigo", p, o)
        XCTAssertEqual(s.netValueCad, 4.95, accuracy: 0.005)
    }

    func testTriangleCtFamilyUsabilityHaircutAndDrawerWarning() {
        let p = PurchaseContext(amountCad: 150, category: "ctFamily", mcc: 5200,
                                merchantBrand: "canadian-tire")
        let s = score("triangle-we", p)
        XCTAssertEqual(s.netValueCad, 5.70, accuracy: 0.005, "4% of 150 is 6.00 CT, times 0.95")
        XCTAssertTrue(s.warnings.contains(.drawerCard))
    }

    func testBonvoyMarriott300() {
        let p = PurchaseContext(amountCad: 300, category: "marriottDirect", mcc: 3509,
                                merchantBrand: "marriott")
        XCTAssertEqual(score("amex-bonvoy", p).netValueCad, 12.00, accuracy: 0.005)
        XCTAssertEqual(score("amex-platinum", p).netValueCad, 10.80, accuracy: 0.005,
                       "marriottDirect inherits lodging, so Platinum earns 2x")
    }

    func testNetworkNotAcceptedExcludes() {
        let p = PurchaseContext(amountCad: 200, category: "wholesaleClub", mcc: 5300,
                                merchantBrand: "costco", acceptedNetworks: [.mastercard])
        let s = score("wealthsimple-vip", p)
        XCTAssertTrue(s.excluded)
        XCTAssertTrue(s.warnings.contains(.networkNotAccepted))
    }
}
