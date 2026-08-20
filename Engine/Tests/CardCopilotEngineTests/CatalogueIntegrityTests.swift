import XCTest
@testable import CardCopilotEngine

/// Data may not outrun code silently. Every catalogue value the engine dispatches on must have a
/// handler; anything that does not is listed here explicitly, so a reviewer sees the gap at
/// authoring time instead of an owner discovering it as a $0.00 recommendation months later.
///
/// These lists may only SHRINK. Adding an entry means shipping a card the engine cannot score —
/// if that is genuinely intended, say so in contracts/CHANGELOG.md in the same commit.
final class CatalogueIntegrityTests: XCTestCase {

    /// Programs with no valuation. Each scores every purchase at $0.00 CAD today.
    /// Deleted by Task 7 as programs.json gains defaults.
    static let knownUnvaluedPrograms: Set<String> = [
        "scenePlus", "aeroplan", "rbcAvion", "tdRewards", "bmoRewards",
        "aventura", "nbcRewards", "pcOptimum", "westJetPoints", "amazonRewards",
    ]

    /// Owner conditions declared in the catalogue with no case in RuleMatcher.
    /// Each fails closed silently. Deleted when CardState.flags lands (spec §3.2).
    static let knownUnhandledConditions: Set<String> = ["amazonEligiblePrimeLinked"]

    /// Mirrors RuleMatcher.conditionsResolveTrue's switch. Kept here rather than made internal
    /// so the test fails when the switch and this list drift, which is the point.
    static let handledConditions: Set<String> = [
        "rogersEligibleServiceLinked", "cryptoLevelUpProActive", "tangerineCategorySelected",
    ]

    /// Mirrors CapWindow.anchorMonth's switch.
    static let resolvableAnchors: Set<String> = [
        "ownerState.scotiaAccountYearAnchorMonth", "ownerState.rogersAccountAnniversaryMonth",
    ]

    /// Cap anchors declared in the catalogue with no case in CapWindow.anchorMonth.
    /// Their windows return nil today. Deleted when CardState.anchors lands (spec §3.3).
    static let knownUnresolvableAnchors: Set<String> = [
        "ownerState.amexAccountAnniversaryMonth", "ownerState.rbcAccountAnniversaryMonth",
    ]

    private func allCards() throws -> [CardProduct] {
        try SeedLoader.loadCatalogue().cards + SeedLoader.loadCandidateCatalogue().cards
    }

    func testEveryProgramIdIsValuedOrKnownUnvalued() throws {
        let valued: Set<String> = [
            "amexMembershipRewards", "marriottBonvoy", "mbnaRewards", "ctMoney", "cro", "cashback",
        ]
        let unhandled = Set(try allCards().map(\.program.programId))
            .subtracting(valued)
            .subtracting(Self.knownUnvaluedPrograms)
        XCTAssertTrue(unhandled.isEmpty,
            "programId(s) with no valuation and not on the known-gap list: \(unhandled.sorted()). "
          + "Scorer.valueCad would value these at $0.00. Add a valuation, or add to "
          + "knownUnvaluedPrograms with a CHANGELOG entry saying why.")
    }

    func testEveryOwnerConditionHasAHandler() throws {
        let declared = Set(try allCards().flatMap { $0.earnRules.compactMap(\.ownerConditions).flatMap { $0 } })
        let unhandled = declared
            .subtracting(Self.handledConditions)
            .subtracting(Self.knownUnhandledConditions)
        XCTAssertTrue(unhandled.isEmpty,
            "ownerCondition(s) with no handler in RuleMatcher: \(unhandled.sorted()). "
          + "These fail closed silently.")
    }

    func testEveryCapAnchorIsResolvable() throws {
        let declared = Set(try allCards().flatMap { $0.caps.compactMap(\.anchor) })
        let unresolvable = declared
            .subtracting(Self.resolvableAnchors)
            .subtracting(Self.knownUnresolvableAnchors)
        XCTAssertTrue(unresolvable.isEmpty,
            "cap.anchor path(s) CapWindow cannot resolve: \(unresolvable.sorted()). "
          + "Their windows return nil and the cap never applies.")
    }

    /// The allowlists are debt, not design. This pins their size so growth is a deliberate,
    /// reviewed act rather than a quiet regression.
    func testKnownGapListsDoNotGrow() {
        XCTAssertLessThanOrEqual(Self.knownUnvaluedPrograms.count, 10)
        XCTAssertLessThanOrEqual(Self.knownUnhandledConditions.count, 1)
        XCTAssertLessThanOrEqual(Self.knownUnresolvableAnchors.count, 2)
    }
}
