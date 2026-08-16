import XCTest
@testable import CardCopilotEngine

/// The window a cap's usage accumulates in. A projection that gets this wrong reports a
/// crossing date for the wrong twelve months, which is worse than reporting none.
final class CapWindowTests: XCTestCase {

    private func cap(_ cardId: String, _ capId: String) throws -> (CardProduct, Cap) {
        let catalogue = try SeedLoader.loadCatalogue()
        let card = try XCTUnwrap(catalogue.cards.first { $0.cardId == cardId })
        return (card, try XCTUnwrap(card.caps.first { $0.capId == capId }))
    }

    /// Scotia's account year is anchored to the account-opening month (April, resolved
    /// 2026-08-15). An August date therefore sits in the April 2026 → March 2027 window,
    /// not in a calendar year.
    func testAccountYearWindowIsAnchoredToTheOwnersOpeningMonth() throws {
        let (card, cap) = try cap("scotia-momentum-vi-plus", "momentum-4pct-accountYear")

        let window = CapWindow.resolve(cap: cap, cardId: card.cardId,
                                       ownerState: try SeedLoader.loadOwnerState(),
                                       asOf: "2026-08-16")

        XCTAssertEqual(window, CapWindow.Window(startMonth: "2026-04", endMonth: "2027-03"))
    }

    /// February 2026 is still inside the account year that opened in April *2025* — the window
    /// rolls back a year rather than jumping forward to an April that has not happened yet.
    func testAccountYearWindowRollsBackWhenAsOfPrecedesTheAnchorMonth() throws {
        let (card, cap) = try cap("scotia-momentum-vi-plus", "momentum-4pct-accountYear")

        let window = CapWindow.resolve(cap: cap, cardId: card.cardId,
                                       ownerState: try SeedLoader.loadOwnerState(),
                                       asOf: "2026-02-10")

        XCTAssertEqual(window, CapWindow.Window(startMonth: "2025-04", endMonth: "2026-03"))
    }

    func testCalendarYearCapWindowIsTheCalendarYear() throws {
        let (card, cap) = try cap("mbna-rewards-we", "mbna-grocery-annual")

        let window = CapWindow.resolve(cap: cap, cardId: card.cardId,
                                       ownerState: try SeedLoader.loadOwnerState(),
                                       asOf: "2026-08-16")

        XCTAssertEqual(window, CapWindow.Window(startMonth: "2026-01", endMonth: "2026-12"))
    }

    func testCalendarMonthCapWindowIsTheSingleMonth() throws {
        let (card, cap) = try cap("amex-cobalt", "cobalt-eats-monthly")

        let window = CapWindow.resolve(cap: cap, cardId: card.cardId,
                                       ownerState: try SeedLoader.loadOwnerState(),
                                       asOf: "2026-08-16")

        XCTAssertEqual(window, CapWindow.Window(startMonth: "2026-08", endMonth: "2026-08"))
    }

    /// The anchor is owner-declared. Unresolved means unresolved: no window, so the projection
    /// above refuses to publish a date instead of defaulting to January.
    func testUnresolvedAccountYearAnchorProducesNoWindow() throws {
        let (card, cap) = try cap("scotia-momentum-vi-plus", "momentum-4pct-accountYear")
        var ownerState = try SeedLoader.loadOwnerState()
        ownerState.cardStates[card.cardId]?.scotiaAccountYearAnchorMonth = nil

        XCTAssertNil(CapWindow.resolve(cap: cap, cardId: card.cardId,
                                       ownerState: ownerState, asOf: "2026-08-16"))
    }
}
