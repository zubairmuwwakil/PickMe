import XCTest
@testable import CardCopilotStore
import CardCopilotEngine

final class OwnerStateSetupTests: XCTestCase {
    private func catalogue() throws -> Catalogue { try SeedLoader.loadCatalogue() }
    private func seed() throws -> OwnerState { try SeedLoader.loadOwnerState() }

    func testEmptyWalletDoesNotAdoptBundledOwnerFixture() throws {
        let state = OwnerStateBuilder.empty(catalogue: try catalogue())

        XCTAssertTrue(state.ownedCardIds.isEmpty)
        XCTAssertEqual(state.defaultCardId, "")
        XCTAssertTrue(state.cardStates.isEmpty)
        XCTAssertTrue(state.carry.drawerCards.isEmpty)
        XCTAssertEqual(state.valuationsCad.programs, SeedLoader.programValuationDefaults,
                       "A new owner starts from catalogue defaults, not personal fixture values")
        XCTAssertNotEqual(state, try seed())
    }

    func testBuildsOnlySelectedCardsAndNeverImportsBundledOwnerProgress() throws {
        let setup = WalletSetup(ownedCardIds: ["amex-cobalt", "rogers-red-we"], defaultCardId: "rogers-red-we",
                                conditionAnswers: [:],
                                switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                                valuationsCad: try seed().valuationsCad)
        let state = OwnerStateBuilder.firstRun(setup: setup, catalogue: try catalogue())

        XCTAssertEqual(state.ownedCardIds, ["amex-cobalt", "rogers-red-we"])
        XCTAssertEqual(state.defaultCardId, "rogers-red-we")
        XCTAssertNil(state.cardStates["rogers-red-we"]?.rogersEligibleServiceLinked)
        XCTAssertEqual(state.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"], 0)
        XCTAssertEqual(state.cardStates["rogers-red-we"]?.capProgress?["rogers-enhanced-accountYear"], 0)
        XCTAssertNil(state.cardStates["scotia-momentum-vi-plus"])
    }

    func testTangerineRemainsUnresolvedUntilCategoriesAreConfirmed() throws {
        var setup = WalletSetup(ownedCardIds: ["tangerine-moneyback-world"], defaultCardId: "tangerine-moneyback-world",
                                switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                                valuationsCad: try seed().valuationsCad)
        var state = OwnerStateBuilder.firstRun(setup: setup, catalogue: try catalogue())
        XCTAssertNil(state.cardStates["tangerine-moneyback-world"]?.selectedCategories)

        setup.tangerineSelectedCategories = ["grocery", "dining"]
        state = OwnerStateBuilder.firstRun(setup: setup, catalogue: try catalogue())
        XCTAssertEqual(state.cardStates["tangerine-moneyback-world"]?.selectedCategories, ["grocery", "dining"])
    }

    func testLocalStoreRoundTripsState() throws {
        let defaults = UserDefaults(suiteName: "OwnerStateSetupTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.volatileDomainNames.first ?? "") }
        let store = OwnerStateLocalStore(defaults: defaults, key: "owner")
        let state = OwnerStateBuilder.firstRun(setup: OwnerStateBuilder.setup(from: try seed()), catalogue: try catalogue())
        try store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testRecommendationLoadRequiresAtLeastOneOwnedCard() throws {
        let defaults = UserDefaults(suiteName: "OwnerStateSetupTests.\(UUID().uuidString)")!
        let store = OwnerStateLocalStore(defaults: defaults, key: "owner")

        XCTAssertNil(store.loadForRecommendation())

        try store.save(OwnerStateBuilder.empty(catalogue: try catalogue()))
        XCTAssertNotNil(store.load(), "An empty wallet is still valid persisted owner state")
        XCTAssertNil(store.loadForRecommendation(),
                     "Extensions must not activate the engine's catalogue fallback")

        let owned = OwnerStateBuilder.firstRun(
            setup: WalletSetup(ownedCardIds: ["amex-cobalt"], defaultCardId: "amex-cobalt",
                               switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                               valuationsCad: Valuations()),
            catalogue: try catalogue())
        try store.save(owned)
        XCTAssertEqual(store.loadForRecommendation(), owned)
    }

    func testExactBundledFixtureIsRejectedButAnEditedWalletIsPreserved() throws {
        let defaults = UserDefaults(suiteName: "OwnerStateSetupTests.\(UUID().uuidString)")!
        let store = OwnerStateLocalStore(defaults: defaults, key: "owner")
        let fixture = try seed()

        try store.save(fixture)
        XCTAssertEqual(store.load(), fixture, "Raw decoding remains a lossless storage primitive")
        XCTAssertNil(store.loadUserWallet(), "The exact historically persisted fixture is poisoned")
        XCTAssertNil(store.loadForRecommendation())

        var edited = fixture
        edited.ownedCardIds.removeLast()
        try store.save(edited)
        XCTAssertEqual(store.loadUserWallet(), edited,
                       "Even a one-card edit proves this is owner data and must be preserved")
    }
}
