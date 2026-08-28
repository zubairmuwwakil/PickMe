import XCTest
@testable import CardCopilot
import CardCopilotEngine

/// The picker used to render the whole catalogue. A draft record is excluded by Scorer with
/// "should not have been scorable" — a message written assuming the state was unreachable, which
/// an unfiltered picker made reachable in one tap.
final class WalletCardCatalogueTests: XCTestCase {

    private func allCards() throws -> [CardProduct] { try SeedLoader.loadCatalogue().cards }

    func testDraftCardsAreNeverSelectable() throws {
        let selectable = WalletCardCatalogue.selectable(try allCards(), scope: .both)
        XCTAssertFalse(selectable.contains { !$0.isPublished },
                       "a draft record cannot be scored, so it must not be selectable")
    }

    func testCanadaScopeExcludesUnitedStatesCards() throws {
        let selectable = WalletCardCatalogue.selectable(try allCards(), scope: .canada)
        XCTAssertFalse(selectable.isEmpty)
        XCTAssertTrue(selectable.allSatisfy { $0.market == .ca })
    }

    func testUnitedStatesScopeExcludesCanadianCards() throws {
        let selectable = WalletCardCatalogue.selectable(try allCards(), scope: .unitedStates)
        XCTAssertTrue(selectable.allSatisfy { $0.market == .us })
    }

    func testBothScopeIsTheUnionAndStillPublishedOnly() throws {
        let cards = try allCards()
        let both = WalletCardCatalogue.selectable(cards, scope: .both)
        let ca = WalletCardCatalogue.selectable(cards, scope: .canada)
        let us = WalletCardCatalogue.selectable(cards, scope: .unitedStates)
        XCTAssertEqual(both.count, ca.count + us.count)
        XCTAssertTrue(both.allSatisfy(\.isPublished))
    }

    func testScopeDefaultsToResidency() {
        XCTAssertEqual(MarketScope.default(for: .ca), .canada)
        XCTAssertEqual(MarketScope.default(for: .us), .unitedStates)
    }

    func testGroupingByIssuerIsAlphabeticalAndComplete() throws {
        let cards = WalletCardCatalogue.selectable(try allCards(), scope: .canada)
        let groups = WalletCardCatalogue.groupedByIssuer(cards)
        XCTAssertEqual(groups.map(\.issuer), groups.map(\.issuer).sorted())
        XCTAssertEqual(groups.reduce(0) { $0 + $1.cards.count }, cards.count,
                       "grouping must not drop or duplicate a card")
    }

    /// Search runs over an already-scoped array, so a draft can never re-enter through search.
    func testSearchCannotResurrectADraft() throws {
        let scoped = WalletCardCatalogue.selectable(try allCards(), scope: .canada)
        let results = WalletCardCatalogue.filter(scoped, matching: "visa")
        XCTAssertTrue(results.allSatisfy { $0.isPublished && $0.market == .ca })
    }
}
