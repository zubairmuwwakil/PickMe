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

    func testBankFilterAllReturnsUnfiltered() {
        let all = WalletCardCatalogue.filter(catalogue.cards, bankFilter: "All")
        XCTAssertEqual(all.count, catalogue.cards.count)
    }

    func testBankFilterCanadaIssuers() {
        let caCards = WalletCardCatalogue.selectable(catalogue.cards, scope: .canada)

        // MBNA
        let mbna = WalletCardCatalogue.filter(caCards, bankFilter: "MBNA")
        XCTAssertFalse(mbna.isEmpty)
        XCTAssertTrue(mbna.contains { $0.cardId == "mbna-rewards-we" })
        XCTAssertTrue(mbna.contains { $0.cardId == "amazon-ca-rewards-mastercard" })

        // Tangerine
        let tangerine = WalletCardCatalogue.filter(caCards, bankFilter: "Tangerine")
        XCTAssertFalse(tangerine.isEmpty)
        XCTAssertTrue(tangerine.contains { $0.cardId == "tangerine-moneyback-world" })

        // Rogers
        let rogers = WalletCardCatalogue.filter(caCards, bankFilter: "Rogers")
        XCTAssertFalse(rogers.isEmpty)
        XCTAssertTrue(rogers.contains { $0.cardId == "rogers-red-we" })

        // Desjardins
        let desjardins = WalletCardCatalogue.filter(caCards, bankFilter: "Desjardins")
        XCTAssertFalse(desjardins.isEmpty)
        XCTAssertTrue(desjardins.contains { $0.cardId == "desjardins-odyssey-world-elite" })

        // National Bank
        let nationalBank = WalletCardCatalogue.filter(caCards, bankFilter: "National Bank")
        XCTAssertFalse(nationalBank.isEmpty)
        XCTAssertTrue(nationalBank.contains { $0.cardId == "national-bank-world-elite" })

        // PC Financial
        let pc = WalletCardCatalogue.filter(caCards, bankFilter: "PC Financial")
        XCTAssertFalse(pc.isEmpty)
        XCTAssertTrue(pc.contains { $0.cardId == "pc-financial-world-elite" })

        // Triangle
        let triangle = WalletCardCatalogue.filter(caCards, bankFilter: "Triangle")
        XCTAssertFalse(triangle.isEmpty)
        XCTAssertTrue(triangle.contains { $0.cardId == "triangle-we" })

        // Wealthsimple
        let wealthsimple = WalletCardCatalogue.filter(caCards, bankFilter: "Wealthsimple")
        XCTAssertFalse(wealthsimple.isEmpty)
        XCTAssertTrue(wealthsimple.contains { $0.cardId == "wealthsimple-vip" })

        // Neo
        let neo = WalletCardCatalogue.filter(caCards, bankFilter: "Neo")
        XCTAssertFalse(neo.isEmpty)
        XCTAssertTrue(neo.contains { $0.cardId == "neo-financial-neo-world-mastercard" })

        // Amex
        let amex = WalletCardCatalogue.filter(caCards, bankFilter: "Amex")
        XCTAssertFalse(amex.isEmpty)
        XCTAssertTrue(amex.contains { $0.cardId == "amex-cobalt" })

        // Scotiabank
        let scotia = WalletCardCatalogue.filter(caCards, bankFilter: "Scotiabank")
        XCTAssertFalse(scotia.isEmpty)
        XCTAssertTrue(scotia.contains { $0.cardId == "scotia-momentum-vi-plus" })

        // RBC
        let rbc = WalletCardCatalogue.filter(caCards, bankFilter: "RBC")
        XCTAssertFalse(rbc.isEmpty)
        XCTAssertTrue(rbc.contains { $0.cardId == "rbc-avion-visa-infinite" })

        // TD
        let td = WalletCardCatalogue.filter(caCards, bankFilter: "TD")
        XCTAssertFalse(td.isEmpty)
        XCTAssertTrue(td.contains { $0.cardId == "td-aeroplan-visa-infinite" })

        // BMO
        let bmo = WalletCardCatalogue.filter(caCards, bankFilter: "BMO")
        XCTAssertFalse(bmo.isEmpty)
        XCTAssertTrue(bmo.contains { $0.cardId == "bmo-eclipse-visa-infinite" })

        // CIBC
        let cibc = WalletCardCatalogue.filter(caCards, bankFilter: "CIBC")
        XCTAssertFalse(cibc.isEmpty)
        XCTAssertTrue(cibc.contains { $0.cardId == "cibc-dividend-visa-infinite" })

        // Capital One
        let capOne = WalletCardCatalogue.filter(caCards, bankFilter: "Capital One")
        XCTAssertFalse(capOne.isEmpty)
        XCTAssertTrue(capOne.contains { $0.cardId == "capital-one-canada-capital-one-guaranteed" })
    }

    func testBankFilterUSIssuers() {
        let usCards = WalletCardCatalogue.selectable(catalogue.cards, scope: .unitedStates)

        // Chase (Published)
        let chase = WalletCardCatalogue.filter(usCards, bankFilter: "Chase")
        XCTAssertFalse(chase.isEmpty)
        XCTAssertTrue(chase.contains { $0.cardId == "chase-sapphire-preferred-card" })

        // Amex (Published)
        let amex = WalletCardCatalogue.filter(usCards, bankFilter: "Amex")
        XCTAssertFalse(amex.isEmpty)
        XCTAssertTrue(amex.contains { $0.cardId == "american-express-gold-card" })

        // Citi (Published)
        let citi = WalletCardCatalogue.filter(usCards, bankFilter: "Citi")
        XCTAssertFalse(citi.isEmpty)
        XCTAssertTrue(citi.contains { $0.cardId == "citi-double-cash-card" })

        // Test with full catalogue to verify draft US bank mappings
        let allCards = catalogue.cards

        // Capital One
        let capOne = WalletCardCatalogue.filter(allCards, bankFilter: "Capital One")
        XCTAssertFalse(capOne.isEmpty)
        XCTAssertTrue(capOne.contains { $0.cardId == "capital-one-venture-rewards-credit-card" })

        // Bank of America
        let bofa = WalletCardCatalogue.filter(allCards, bankFilter: "Bank of America")
        XCTAssertFalse(bofa.isEmpty)
        XCTAssertTrue(bofa.contains { $0.cardId == "bank-of-america-business-advantage-customized" })

        // Discover
        let discover = WalletCardCatalogue.filter(allCards, bankFilter: "Discover")
        XCTAssertFalse(discover.isEmpty)
        XCTAssertTrue(discover.contains { $0.cardId == "discover-it-cash-back" })

        // Wells Fargo
        let wells = WalletCardCatalogue.filter(allCards, bankFilter: "Wells Fargo")
        XCTAssertFalse(wells.isEmpty)
        XCTAssertTrue(wells.contains { $0.cardId == "wells-fargo-active-cash-business" })

        // Barclays
        let barclays = WalletCardCatalogue.filter(allCards, bankFilter: "Barclays")
        XCTAssertFalse(barclays.isEmpty)
        XCTAssertTrue(barclays.contains { $0.cardId == "barclays-hawaiian-airlines-world-elite" })

        // U.S. Bank
        let usbank = WalletCardCatalogue.filter(allCards, bankFilter: "U.S. Bank")
        XCTAssertFalse(usbank.isEmpty)
        XCTAssertTrue(usbank.contains { $0.cardId == "u-s-bank-shopper-cash-rewards-visa-signature" })

        // Apple
        let apple = WalletCardCatalogue.filter(allCards, bankFilter: "Apple")
        XCTAssertFalse(apple.isEmpty)
        XCTAssertTrue(apple.contains { $0.cardId == "goldman-sachs-apple-card" })

        // Bilt
        let bilt = WalletCardCatalogue.filter(allCards, bankFilter: "Bilt")
        XCTAssertFalse(bilt.isEmpty)
        XCTAssertTrue(bilt.contains { $0.cardId == "column-n-a-bilt-blue-card" })
    }

    func testBankFilterNoFee() {
        let caCards = WalletCardCatalogue.selectable(catalogue.cards, scope: .canada)
        let noFeeCa = WalletCardCatalogue.filter(caCards, bankFilter: "No Fee")
        XCTAssertFalse(noFeeCa.isEmpty)
        XCTAssertTrue(noFeeCa.allSatisfy { ($0.fee.annual?.amount ?? 0) == 0 })
        XCTAssertTrue(noFeeCa.contains { $0.cardId == "tangerine-moneyback-world" })
        XCTAssertTrue(noFeeCa.contains { $0.cardId == "rogers-red-we" })
        XCTAssertTrue(noFeeCa.contains { $0.cardId == "triangle-we" })
    }
}

