import XCTest
@testable import CardCopilotStore
import CardCopilotEngine

/// `OwnerStateBuilder.make` rebuilt owner state from setup answers alone, so every "Save changes"
/// discarded everything `WalletSetup` cannot express. Cap progress is live data written by
/// `MoneyTalksSync.merging`, so an owner who added one card was scored as if every capped bonus
/// were unspent — until the next successful sync, and permanently while offline.
///
/// These are absence-of-loss tests. Each one adds or removes something via the editor's own
/// projection and then asserts that an untouched observation survived.
final class OwnerStateApplyTests: XCTestCase {

    private func catalogue() throws -> Catalogue { try SeedLoader.loadCatalogue() }
    private func seed() throws -> OwnerState { try SeedLoader.loadOwnerState() }

    /// A wallet carrying real observations, shaped the way `MoneyTalksSync.merging` leaves one:
    /// cap usage on a card, a card in the carry drawer, and a resolved market.
    private func existingWallet() throws -> OwnerState {
        var momentum = CardState()
        momentum.capProgress = ["momentum-4pct-accountYear": 1_250.00]
        return OwnerState(
            ownerStateVersion: "test-1",
            ownedCardIds: ["scotia-momentum-vi-plus", "amex-cobalt"],
            defaultCardId: "amex-cobalt",
            switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
            carry: Carry(drawerCards: ["amex-cobalt"]),
            cardStates: ["scotia-momentum-vi-plus": momentum],
            valuationsCad: try seed().valuationsCad,
            market: "CA")
    }

    // MARK: - What an edit must preserve

    func testApplyPreservesCapProgressForCardsStillOwned() throws {
        let existing = try existingWallet()
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.append("rogers-red-we")   // the edit: add one unrelated card

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        XCTAssertEqual(result.cardStates["scotia-momentum-vi-plus"]?
            .capProgress?["momentum-4pct-accountYear"], 1_250.00,
            "adding a card must not reset another card's cap progress")
    }

    /// A cap the owner has no figure for is filled at zero; one already tracked keeps its number.
    /// Both halves matter — the first handles a cap added to the catalogue since the last save.
    func testApplyFillsOnlyUntrackedCaps() throws {
        let existing = try existingWallet()
        let setup = OwnerStateBuilder.setup(from: existing)

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        let progress = try XCTUnwrap(result.cardStates["scotia-momentum-vi-plus"]?.capProgress)
        XCTAssertEqual(progress["momentum-4pct-accountYear"], 1_250.00)
        XCTAssertEqual(progress["momentum-2pct-accountYear"], 0)
    }

    func testApplyPreservesCarry() throws {
        let existing = try existingWallet()
        let setup = OwnerStateBuilder.setup(from: existing)

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        XCTAssertEqual(result.carry.drawerCards, ["amex-cobalt"])
    }

    func testApplyPreservesMarket() throws {
        let existing = try existingWallet()
        let setup = OwnerStateBuilder.setup(from: existing)

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        XCTAssertEqual(result.market, "CA")
        XCTAssertEqual(result.resolvedMarket, .ca)
    }

    func testSetupRoundTripsMarket() throws {
        XCTAssertEqual(OwnerStateBuilder.setup(from: try existingWallet()).market, .ca,
                       "market must survive the OwnerState -> WalletSetup projection")
    }

    // MARK: - What an edit must NOT preserve

    /// A card the owner did not previously hold has no history, so it starts clean.
    func testNewlyAddedCardStartsWithZeroedCaps() throws {
        let existing = try existingWallet()
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.append("scotia-gold-amex")

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        let added = try XCTUnwrap(result.cardStates["scotia-gold-amex"])
        XCTAssertEqual(added.capProgress?["scotia-gold-accelerated-calendarYear"], 0)
    }

    /// A removed card's state goes with it — it is not owner history worth keeping.
    func testRemovedCardStateIsDropped() throws {
        let existing = try existingWallet()
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.removeAll { $0 == "scotia-momentum-vi-plus" }
        setup.defaultCardId = "amex-cobalt"

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        XCTAssertNil(result.cardStates["scotia-momentum-vi-plus"])
    }

    // MARK: - First run has nothing to preserve

    /// The behaviour the old `make` documented and got right, now stated in the name so it can
    /// never be reached from an edit by accident.
    func testFirstRunStartsEverythingAtZero() throws {
        let setup = WalletSetup(ownedCardIds: ["scotia-momentum-vi-plus"],
                                defaultCardId: "scotia-momentum-vi-plus",
                                switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                                valuationsCad: try seed().valuationsCad,
                                market: .ca)

        let result = OwnerStateBuilder.firstRun(setup: setup, catalogue: try catalogue())

        XCTAssertEqual(result.carry.drawerCards, [])
        let progress = try XCTUnwrap(result.cardStates["scotia-momentum-vi-plus"]?.capProgress)
        XCTAssertTrue(progress.values.allSatisfy { $0 == 0 })
    }

    // MARK: - Condition answers

    func testConditionAnswersRoundTripThroughFlags() throws {
        let existing = try existingWallet()
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.append("rogers-red-we")
        setup.conditionAnswers["rogers-red-we"] = ["rogersEligibleServiceLinked": true]

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        XCTAssertEqual(result.cardStates["rogers-red-we"]?
            .resolvedFlags["rogersEligibleServiceLinked"], true)
        XCTAssertEqual(OwnerStateBuilder.setup(from: result)
            .conditionAnswers["rogers-red-we"]?["rogersEligibleServiceLinked"], true)
    }

    /// "Not asked" and "no" buy the owner different rates: `RuleMatcher` skips the rule either
    /// way, but only one of them is an answer the owner gave.
    func testUnansweredConditionStaysUnresolved() throws {
        let existing = try existingWallet()
        var setup = OwnerStateBuilder.setup(from: existing)
        setup.ownedCardIds.append("rogers-red-we")

        let result = OwnerStateBuilder.apply(setup, to: existing, catalogue: try catalogue())

        XCTAssertNil(result.cardStates["rogers-red-we"]?
            .resolvedFlags["rogersEligibleServiceLinked"])
    }
}
