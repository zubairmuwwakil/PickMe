import XCTest
@testable import CardCopilotStore
import CardCopilotEngine

final class OwnerStateSetupTests: XCTestCase {
    private func catalogue() throws -> Catalogue { try SeedLoader.loadCatalogue() }
    private func seed() throws -> OwnerState { try SeedLoader.loadOwnerState() }

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
}
