import XCTest
@testable import CardCopilot
import CardCopilotEngine

final class WalletConditionsTests: XCTestCase {

    func testConditionIdsComeFromTheCardsOwnRules() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(WalletConditions.ids(for: "rogers-red-we", catalogue: catalogue),
                       ["rogersEligibleServiceLinked"])
        XCTAssertEqual(WalletConditions.ids(for: "cryptocom-royal-indigo", catalogue: catalogue),
                       ["cryptoLevelUpProActive"])
    }

    func testACardWithNoConditionsReturnsNothing() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertTrue(WalletConditions.ids(for: "amex-cobalt", catalogue: catalogue).isEmpty)
    }

    /// No card id is hardcoded anywhere: adding a conditional card to the catalogue must make
    /// its question appear with no App change at all.
    func testAmazonCardSurfacesItsConditionWithNoCodeChange() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(WalletConditions.ids(for: "amazon-ca-rewards-mastercard", catalogue: catalogue),
                       ["amazonEligiblePrimeLinked"])
    }

    func testPromptFallsBackToTheRegistryWhenUntranslated() {
        let prompt = WalletConditions.prompt(for: "amazonEligiblePrimeLinked")
        XCTAssertFalse(prompt.isEmpty)
    }
}
