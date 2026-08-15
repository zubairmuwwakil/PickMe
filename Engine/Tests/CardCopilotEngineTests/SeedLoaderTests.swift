import XCTest
@testable import CardCopilotEngine

final class SeedLoaderTests: XCTestCase {
    func testCatalogueLoadsAllTenCards() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(catalogue.cards.count, 10)
        let cobalt = try XCTUnwrap(catalogue.cards.first { $0.cardId == "amex-cobalt" })
        XCTAssertEqual(cobalt.fee.annualCad ?? 0, 191.88, accuracy: 0.005)
        XCTAssertEqual(cobalt.network, .amex)
        XCTAssertEqual(cobalt.caps.first?.capId, "cobalt-eats-monthly")
        guard case .points(let ppc) = try XCTUnwrap(
            cobalt.earnRules.first { $0.ruleId == "cobalt-eats-5x" }).earn
        else { return XCTFail("expected points earn") }
        XCTAssertEqual(ppc, 5)
        let crypto = try XCTUnwrap(catalogue.cards.first { $0.cardId == "cryptocom-royal-indigo" })
        XCTAssertEqual(crypto.fxRules.count, 2, "current + announced FX records")
        XCTAssertEqual(crypto.kind, .prepaid)
    }

    func testOwnerStateLoads() throws {
        let state = try SeedLoader.loadOwnerState()
        XCTAssertEqual(state.defaultCardId, "wealthsimple-vip")
        XCTAssertEqual(state.switchThreshold.semantics, "both")
        XCTAssertEqual(state.valuationsCad.amexMembershipRewards.centsPerPoint, 1.8, accuracy: 0.005)
        XCTAssertTrue(state.carry.drawerCards.contains("triangle-we"))
        XCTAssertEqual(state.cardStates["rogers-red-we"]?.rogersEligibleServiceLinked, false)
        XCTAssertEqual(state.cardStates["cryptocom-royal-indigo"]?.cryptoLevelUpProActive, false)
        XCTAssertNil(state.cardStates["cryptocom-royal-indigo"]?.croHandling,
                     "unset onboarding fields must decode as nil, never a default")
        XCTAssertEqual(state.cardStates["scotia-momentum-vi-plus"]?
            .capProgress?["momentum-4pct-accountYear"] ?? 0, 12500, accuracy: 0.005)
        XCTAssertEqual(state.cardStates["tangerine-moneyback-world"]?.selectedCategories?.count, 13,
                       "treat-as-all-selected: 13 eligible Tangerine categories")
    }
}
