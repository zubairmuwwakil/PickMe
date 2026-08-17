import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class MoneyTalksSyncTests: XCTestCase {
    func testMergeConvertsMinorUnitsIntoTheExistingOwnerStateCapUnits() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()

        let merged = OwnerStateSyncService.merging(
            ["cobalt-eats-monthly": SpineCap(usedMinor: 249_975, periodKey: "2026-08")],
            into: owner, catalogue: catalogue)

        XCTAssertEqual(merged.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"], 2499.75)
    }

    func testMergeKeepsExistingCapProgressWhenTheResponseDoesNotContainThatCap() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let before = owner.cardStates["amex-cobalt"]?.capProgress

        let merged = OwnerStateSyncService.merging([:], into: owner, catalogue: catalogue)

        XCTAssertEqual(merged.cardStates["amex-cobalt"]?.capProgress, before)
    }
}
