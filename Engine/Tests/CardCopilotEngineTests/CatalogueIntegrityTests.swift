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

    /// The valued set is read from programs.json, not mirrored here. A hand-copied list would be
    /// one more place for the catalogue to outrun the code — inside the very gate meant to catch
    /// that. Adding a sourced valuation to programs.json now tightens this test on its own.
    func testEveryProgramIdIsValuedOrKnownUnvalued() throws {
        let valued = Set(try SeedLoader.loadPrograms().defaults.keys)
        let unhandled = Set(try allCards().map(\.program.programId))
            .subtracting(valued)
            .subtracting(Self.knownUnvaluedPrograms)
        XCTAssertTrue(unhandled.isEmpty,
            "programId(s) with no valuation and not on the known-gap list: \(unhandled.sorted()). "
          + "Scorer.valueCad would value these at $0.00. Add a default to contracts/programs.json, "
          + "or add to knownUnvaluedPrograms with a CHANGELOG entry saying why.")
    }

    /// The ratchet only ratchets if valuing a program also retires its allowlist entry. Without
    /// this, Task 7 could add aeroplan to programs.json, leave it listed as a known gap, and the
    /// suite would report the debt as unpaid forever while quietly passing.
    func testKnownUnvaluedListRetiresProgramsThatGainedAValuation() throws {
        let valued = Set(try SeedLoader.loadPrograms().defaults.keys)
        let stale = valued.intersection(Self.knownUnvaluedPrograms)
        XCTAssertTrue(stale.isEmpty,
            "programs.json now values \(stale.sorted()), which is still listed as a known gap. "
          + "Remove from knownUnvaluedPrograms.")
    }

    /// A default keyed to a programId no card declares values nothing and reads as coverage.
    /// A single typo in programs.json would otherwise be invisible.
    func testEveryProgramDefaultKeyIsARealCatalogueProgramId() throws {
        let declared = Set(try allCards().map(\.program.programId))
        let orphans = Set(try SeedLoader.loadPrograms().defaults.keys).subtracting(declared)
        XCTAssertTrue(orphans.isEmpty,
            "contracts/programs.json values programId(s) no card declares: \(orphans.sorted()). "
          + "Likely a typo — the valuation will never be used.")
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
