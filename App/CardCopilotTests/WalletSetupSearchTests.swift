import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

final class WalletSetupSearchTests: XCTestCase {

    private var catalogue: Catalogue!

    override func setUpWithError() throws {
        try super.setUpWithError()
        catalogue = try SeedLoader.loadCatalogue()
    }

    func testEmptyQueryReturnsAllCards() {
        let allCards = catalogue.cards
        XCTAssertFalse(allCards.isEmpty)

        let resultEmpty = WalletCardCatalogue.filter(allCards, matching: "")
        XCTAssertEqual(resultEmpty.count, allCards.count)

        let resultWhitespace = WalletCardCatalogue.filter(allCards, matching: "   ")
        XCTAssertEqual(resultWhitespace.count, allCards.count)
    }

    func testSearchByOfficialName() {
        let results = WalletCardCatalogue.filter(catalogue.cards, matching: "Cobalt")
        XCTAssertTrue(results.contains { $0.cardId == "amex-cobalt" })
        XCTAssertFalse(results.contains { $0.cardId == "scotia-momentum-vi-plus" })
    }

    func testSearchByIssuer() {
        let amexResults = WalletCardCatalogue.filter(catalogue.cards, matching: "American Express")
        XCTAssertFalse(amexResults.isEmpty)
        XCTAssertTrue(amexResults.contains { $0.cardId == "amex-cobalt" })
        XCTAssertTrue(amexResults.contains { $0.cardId == "amex-platinum" })

        let scotiaResults = WalletCardCatalogue.filter(catalogue.cards, matching: "Scotiabank")
        XCTAssertFalse(scotiaResults.isEmpty)
        XCTAssertTrue(scotiaResults.contains { $0.cardId == "scotia-momentum-vi-plus" })

        let tangerineResults = WalletCardCatalogue.filter(catalogue.cards, matching: "Tangerine")
        XCTAssertFalse(tangerineResults.isEmpty)
        XCTAssertTrue(tangerineResults.contains { $0.cardId == "tangerine-moneyback-world" })
    }

    func testSearchByNetwork() {
        let visaResults = WalletCardCatalogue.filter(catalogue.cards, matching: "Visa")
        XCTAssertFalse(visaResults.isEmpty)
        XCTAssertTrue(visaResults.contains { $0.cardId == "scotia-momentum-vi-plus" })

        let amexResults = WalletCardCatalogue.filter(catalogue.cards, matching: "AMEX")
        XCTAssertFalse(amexResults.isEmpty)
        XCTAssertTrue(amexResults.contains { $0.cardId == "amex-cobalt" })

        let mcResults = WalletCardCatalogue.filter(catalogue.cards, matching: "Mastercard")
        XCTAssertFalse(mcResults.isEmpty)
        XCTAssertTrue(mcResults.contains { $0.cardId == "rogers-red-we" })
    }

    func testMultiTokenSearch() {
        let results = WalletCardCatalogue.filter(catalogue.cards, matching: "scotia visa")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.cardId == "scotia-momentum-vi-plus" })
        XCTAssertFalse(results.contains { $0.cardId == "amex-cobalt" })

        let amexCobalt = WalletCardCatalogue.filter(catalogue.cards, matching: "amex cobalt")
        XCTAssertEqual(amexCobalt.count, 1)
        XCTAssertEqual(amexCobalt.first?.cardId, "amex-cobalt")
    }

    func testNoMatchReturnsEmpty() {
        let results = WalletCardCatalogue.filter(catalogue.cards, matching: "NonExistentCardXYZ123")
        XCTAssertTrue(results.isEmpty)
    }

    func testCaseInsensitiveMatching() {
        let lower = WalletCardCatalogue.filter(catalogue.cards, matching: "tangerine")
        let upper = WalletCardCatalogue.filter(catalogue.cards, matching: "TANGERINE")
        let mixed = WalletCardCatalogue.filter(catalogue.cards, matching: "TaNgErInE")

        XCTAssertEqual(lower.map(\.cardId), upper.map(\.cardId))
        XCTAssertEqual(lower.map(\.cardId), mixed.map(\.cardId))
        XCTAssertFalse(lower.isEmpty)
    }
}
