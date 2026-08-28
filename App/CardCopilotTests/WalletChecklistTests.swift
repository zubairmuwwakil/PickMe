import XCTest
@testable import CardCopilot
import CardCopilotEngine
import CardCopilotStore

/// RuleMatcher fails closed, so an unanswered condition costs the owner a bonus rate silently
/// and permanently. The banner exists to make that visible, and to KEEP being visible — a card
/// added six months after onboarding raises its question the same way.
final class WalletChecklistTests: XCTestCase {

    private func setup(cards: [String], answers: [String: [String: Bool]] = [:],
                       defaultCard: String = "") -> WalletSetup {
        WalletSetup(ownedCardIds: cards, defaultCardId: defaultCard,
                    conditionAnswers: answers,
                    switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                    valuationsCad: Valuations(programs: [:]))
    }

    func testEmptyWalletAsksForACard() throws {
        let items = WalletChecklist.items(setup: setup(cards: []),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.contains { $0.kind == .addCards })
    }

    func testUnansweredConditionAppears() throws {
        let items = WalletChecklist.items(setup: setup(cards: ["rogers-red-we"],
                                                       defaultCard: "rogers-red-we"),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.contains { $0.kind == .answerCondition })
    }

    func testAnsweredConditionDisappears() throws {
        let answers = ["rogers-red-we": ["rogersEligibleServiceLinked": false]]
        let items = WalletChecklist.items(setup: setup(cards: ["rogers-red-we"],
                                                       answers: answers,
                                                       defaultCard: "rogers-red-we"),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertFalse(items.contains { $0.kind == .answerCondition },
                       "'no' is an answer — the item is done, not still outstanding")
    }

    func testFullySetUpWalletHasNoItems() throws {
        let items = WalletChecklist.items(setup: setup(cards: ["amex-cobalt"],
                                                       defaultCard: "amex-cobalt"),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.isEmpty)
    }

    func testMissingDefaultCardIsFlagged() throws {
        let items = WalletChecklist.items(setup: setup(cards: ["amex-cobalt"], defaultCard: ""),
                                          catalogue: try SeedLoader.loadCatalogue())
        XCTAssertTrue(items.contains { $0.kind == .chooseDefault })
    }
}
