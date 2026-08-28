import XCTest
@testable import CardCopilotEngine

/// The registry is the answer to "adding an owner condition took six edits across two languages".
///
/// Its one hard invariant: every id the catalogue references must be declared here, or nothing can
/// ask the question and the rule fails closed forever. That is not hypothetical —
/// `amazonEligiblePrimeLinked` shipped in the catalogue with no `RuleMatcher` case and no schema
/// complaint, so `amazon-ca-prime-2_5x` could not fire in any build that ever existed.
final class OwnerConditionRegistryTests: XCTestCase {

    // MARK: - The registry file

    func testRegistryDecodes() throws {
        let registry = try SeedLoader.loadOwnerConditions()
        XCTAssertFalse(registry.conditions.isEmpty)
        XCTAssertFalse(registry.conditionsVersion.isEmpty)
    }

    func testEveryCatalogueConditionIsDeclared() throws {
        let declared = Set(try SeedLoader.loadOwnerConditions().conditions.keys)
        let referenced = Set(try SeedLoader.loadCatalogue().cards
            .flatMap(\.earnRules)
            .compactMap(\.ownerConditions)
            .flatMap { $0 })
        XCTAssertFalse(referenced.isEmpty, "the catalogue should reference at least one condition")
        XCTAssertEqual(referenced.subtracting(declared), [],
                       "catalogue references a condition the registry does not declare")
    }

    /// A yes/no condition with no question is one nobody can answer, which is indistinguishable
    /// from not declaring it at all.
    func testBooleanConditionsCarryAPrompt() throws {
        let registry = try SeedLoader.loadOwnerConditions()
        for (id, condition) in registry.conditions where condition.answerKind == .boolean {
            XCTAssertFalse((condition.prompt ?? "").isEmpty,
                           "\(id) is answered yes/no but has no question to ask")
        }
    }

    func testAmazonPrimeIsDeclared() throws {
        let registry = try SeedLoader.loadOwnerConditions()
        let condition = try XCTUnwrap(registry.conditions["amazonEligiblePrimeLinked"],
                                      "the condition that shipped unanswerable is why this exists")
        XCTAssertEqual(condition.answerKind, .boolean)
    }

    func testTangerineIsACategorySelectionWithItsIssuerLimit() throws {
        let registry = try SeedLoader.loadOwnerConditions()
        let condition = try XCTUnwrap(registry.conditions["tangerineCategorySelected"])
        XCTAssertEqual(condition.answerKind, .categorySelection)
        XCTAssertEqual(condition.maxSelections, 3)
    }

    func testCachedAccessorMatchesTheFile() throws {
        XCTAssertEqual(SeedLoader.ownerConditions, try SeedLoader.loadOwnerConditions().conditions)
    }

    // MARK: - flags and the legacy migration

    /// An owner state written before `flags` existed must keep working untouched. The legacy named
    /// booleans are deliberately NOT deleted: MoneyTalks stores owner state and has not been
    /// audited for which keys it reads, so they stay, mirrored, for one release.
    func testLegacyNamedBooleansFoldIntoResolvedFlags() throws {
        let json = #"{"rogersEligibleServiceLinked":true,"cryptoLevelUpProActive":false}"#
        let state = try JSONDecoder().decode(CardState.self, from: Data(json.utf8))
        XCTAssertEqual(state.resolvedFlags["rogersEligibleServiceLinked"], true)
        XCTAssertEqual(state.resolvedFlags["cryptoLevelUpProActive"], false)
    }

    func testFlagsWinOverAStaleMirroredLegacyKey() throws {
        let json = #"{"rogersEligibleServiceLinked":false,"flags":{"rogersEligibleServiceLinked":true}}"#
        let state = try JSONDecoder().decode(CardState.self, from: Data(json.utf8))
        XCTAssertEqual(state.resolvedFlags["rogersEligibleServiceLinked"], true,
                       "flags is the newer field and must not be overwritten by a stale mirror")
    }

    /// "Not asked" and "no" buy the owner different rates. `RuleMatcher` skips the rule either
    /// way, but only one of them is an answer, and a UI needs to know which.
    func testUnansweredConditionIsAbsentNotFalse() throws {
        let state = try JSONDecoder().decode(CardState.self, from: Data("{}".utf8))
        XCTAssertNil(state.resolvedFlags["rogersEligibleServiceLinked"])
        XCTAssertNil(state.flags)
    }

    func testFlagsRoundTrip() throws {
        var state = CardState()
        state.flags = ["amazonEligiblePrimeLinked": true]
        let decoded = try JSONDecoder().decode(CardState.self,
                                               from: try JSONEncoder().encode(state))
        XCTAssertEqual(decoded.resolvedFlags["amazonEligiblePrimeLinked"], true)
    }

    // MARK: - RuleMatcher dispatch

    /// The pin. This assertion could not have passed in any build before card-contracts@2.8:
    /// `amazonEligiblePrimeLinked` hit `default: return false` in every one of them.
    func testAnyDeclaredConditionResolvesFromFlags() {
        var state = CardState()
        state.flags = ["amazonEligiblePrimeLinked": true]
        XCTAssertTrue(RuleMatcher.conditionsResolveTrue(["amazonEligiblePrimeLinked"], state: state))
    }

    func testUnansweredConditionFailsClosed() {
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(["amazonEligiblePrimeLinked"],
                                                         state: CardState()))
    }

    func testExplicitNoFailsClosed() {
        var state = CardState()
        state.flags = ["rogersEligibleServiceLinked": false]
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(["rogersEligibleServiceLinked"], state: state))
    }

    func testLegacyStateStillGatesItsRule() {
        var state = CardState()
        state.rogersEligibleServiceLinked = true
        XCTAssertTrue(RuleMatcher.conditionsResolveTrue(["rogersEligibleServiceLinked"], state: state),
                      "a wallet saved by a pre-2.8 build must not lose its Rogers 2%")
    }

    func testTangerineStaysOnItsStructuralField() {
        var state = CardState()
        state.selectedCategories = ["grocery"]
        XCTAssertTrue(RuleMatcher.conditionsResolveTrue(["tangerineCategorySelected"], state: state))
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(["tangerineCategorySelected"],
                                                         state: CardState()))
    }

    func testAllConditionsMustHoldTogether() {
        var state = CardState()
        state.flags = ["rogersEligibleServiceLinked": true]
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(
            ["rogersEligibleServiceLinked", "amazonEligiblePrimeLinked"], state: state))
    }

    /// An id in no registry and no switch still fails closed rather than throwing or matching.
    func testUnknownConditionFailsClosed() {
        var state = CardState()
        state.flags = ["somethingElse": true]
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(["neverDeclaredAnywhere"], state: state))
    }

    // MARK: - End to end on the card that motivated all of this

    /// Amazon's three-rule ladder resolves entirely from the flag: base 1x always, 1.5x at
    /// Amazon/Whole Foods, 2.5x there only while Prime is linked. Asserted at the rule level
    /// rather than through a cross-catalogue winner, so the expectation is derived from the
    /// card's own rules rather than from whatever the engine happens to output.
    func testAmazonPrimeRuleIsLiveOnlyWithTheFlag() throws {
        let card = try XCTUnwrap(SeedLoader.loadCatalogue().cards
            .first { $0.cardId == "amazon-ca-rewards-mastercard" })
        let primeRule = try XCTUnwrap(card.earnRules.first { $0.ruleId == "amazon-ca-prime-2_5x" })

        var linked = CardState()
        linked.flags = ["amazonEligiblePrimeLinked": true]

        XCTAssertTrue(RuleMatcher.conditionsResolveTrue(primeRule.ownerConditions, state: linked))
        XCTAssertFalse(RuleMatcher.conditionsResolveTrue(primeRule.ownerConditions,
                                                         state: CardState()))
    }
}
