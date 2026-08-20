import XCTest
@testable import CardCopilotEngine

private struct FixtureFile: Decodable {
    let cases: [FixtureCase]
    let pinnedValuations: PinnedValuations

    struct PinnedValuations: Decodable { let amexMembershipRewards: Double }
}

private struct FixtureCase: Decodable {
    let caseId: String
    let purchase: PurchaseContext
    /// Evaluation date. Defaults to the suite-wide date so the original 12 cases are unaffected;
    /// set per case to exercise effective-dating boundaries (earn rules and FX records).
    let asOf: String?
    let ownerStateOverrides: Overrides?
    let expected: Expected

    struct Overrides: Decodable { let cardStates: [String: CardStateOverride]? }

    /// A `CardState` plus the list of fields to force back to `nil`. Needed because merging a
    /// partial override onto the base owner state can only ever *set* a field — but "unresolved"
    /// (nil) is a distinct, load-bearing input to `RuleMatcher.conditionsResolveTrue`, and
    /// owner-state.json resolves most conditions to `false` rather than leaving them nil.
    struct CardStateOverride: Decodable {
        let state: CardState
        let unsetFields: [String]?

        private enum CodingKeys: String, CodingKey { case unsetFields }

        init(from decoder: Decoder) throws {
            // CardState's synthesized decoder ignores the extra `unsetFields` key.
            state = try CardState(from: decoder)
            unsetFields = try decoder.container(keyedBy: CodingKeys.self)
                .decodeIfPresent([String].self, forKey: .unsetFields)
        }
    }

    struct Expected: Decodable {
        let winner: String
        let winnerValueCad: Double
        let winnerRule: String?
        let runnerUp: String?
        let runnerUpValueCad: Double?
        let switchFromDefault: Bool?
        let advantageOverDefaultCad: Double?
        let defaultNotAccepted: Bool?
        let suppressedBetterCard: String?
        let suppressedValueCad: Double?
        let warnings: [String]?
        /// Warnings that must NOT be on the winner. The only way to pin behaviour whose entire
        /// signal is a warning — e.g. an announced FX record being ignored before its
        /// `effectiveFrom`, which is dollar-identical to the record it replaces.
        let warningsAbsent: [String]?
        let valuationSensitive: Bool?
        let valuationDirection: String?
        let alternateWinner: String?
        let breakevenCentsPerPoint: Double?
    }
}

/// The executable spec: every case here was hand-computed from the verified catalogue.
/// A failure means either an engine bug or a wrong expectation — never tune one to the other
/// without re-deriving the arithmetic by hand.
final class FixtureHarnessTests: XCTestCase {
    private static let defaultAsOf = "2026-08-20"

    func testAllFixtures() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine-fixtures",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"))
        let file = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.cases.count, 27)
        XCTAssertEqual(Set(file.cases.map(\.caseId)).count, file.cases.count, "duplicate caseId")

        let catalogue = try SeedLoader.loadCatalogue()
        var baseState = try SeedLoader.loadOwnerState()
        // Pinned rather than inherited — see pinnedValuations._why in the fixture file.
        baseState.withPointsValuation { $0.centsPerPoint = file.pinnedValuations.amexMembershipRewards }

        for fixture in file.cases {
            var state = baseState
            let ctx = "case \(fixture.caseId)"
            if let overrides = fixture.ownerStateOverrides?.cardStates {
                for (cardId, override) in overrides {
                    var merged = state.cardStates[cardId] ?? CardState()
                    if let cap = override.state.capProgress {
                        merged.capProgress = (merged.capProgress ?? [:]).merging(cap) { _, new in new }
                    }
                    if let v = override.state.cryptoLevelUpProActive { merged.cryptoLevelUpProActive = v }
                    if let v = override.state.croHandling { merged.croHandling = v }
                    if let v = override.state.rogersEligibleServiceLinked { merged.rogersEligibleServiceLinked = v }
                    if let v = override.state.selectedCategories { merged.selectedCategories = v }
                    for field in override.unsetFields ?? [] {
                        switch field {
                        case "capProgress": merged.capProgress = nil
                        case "cryptoLevelUpProActive": merged.cryptoLevelUpProActive = nil
                        case "croHandling": merged.croHandling = nil
                        case "rogersEligibleServiceLinked": merged.rogersEligibleServiceLinked = nil
                        case "selectedCategories": merged.selectedCategories = nil
                        case "treatAsAllSelected": merged.treatAsAllSelected = nil
                        default: XCTFail("\(ctx): unknown unsetFields entry '\(field)'")
                        }
                    }
                    state.cardStates[cardId] = merged
                }
            }

            let engine = RecommendationEngine(catalogue: catalogue, ownerState: state)
            let r = engine.recommend(fixture.purchase, asOf: fixture.asOf ?? Self.defaultAsOf)
            let e = fixture.expected

            XCTAssertEqual(r.winner.cardId, e.winner, ctx)
            XCTAssertEqual(r.winner.netValueCad, e.winnerValueCad, accuracy: 0.005, ctx)
            if let rule = e.winnerRule { XCTAssertEqual(r.winner.appliedRuleId, rule, ctx) }
            if let runnerUp = e.runnerUp { XCTAssertEqual(r.runnerUp?.cardId, runnerUp, ctx) }
            if let v = e.runnerUpValueCad {
                XCTAssertEqual(r.runnerUp?.netValueCad ?? .nan, v, accuracy: 0.005, ctx)
            }
            if let s = e.switchFromDefault { XCTAssertEqual(r.switchedFromDefault, s, ctx) }
            if let a = e.advantageOverDefaultCad {
                XCTAssertEqual(r.advantageOverDefaultCad ?? .nan, a, accuracy: 0.005, ctx)
            }
            if let d = e.defaultNotAccepted { XCTAssertEqual(r.defaultNotAccepted, d, ctx) }
            if let s = e.suppressedBetterCard { XCTAssertEqual(r.suppressedBetterCard?.cardId, s, ctx) }
            if let v = e.suppressedValueCad {
                XCTAssertEqual(r.suppressedBetterCard?.netValueCad ?? .nan, v, accuracy: 0.005, ctx)
            }
            let actualWarnings = r.winner.warnings.map(\.rawValue)
            for w in e.warnings ?? [] {
                XCTAssertTrue(actualWarnings.contains(w), "\(ctx): missing \(w)")
            }
            for w in e.warningsAbsent ?? [] {
                XCTAssertFalse(actualWarnings.contains(w), "\(ctx): unexpected \(w)")
            }
            if let s = e.valuationSensitive { XCTAssertEqual(r.valuationSensitive, s, ctx) }
            if let d = e.valuationDirection {
                XCTAssertEqual(r.valuationDirection.map(String.init(describing:)), d, ctx)
            }
            if let a = e.alternateWinner { XCTAssertEqual(r.alternateWinnerCardId, a, ctx) }
            if let b = e.breakevenCentsPerPoint {
                XCTAssertEqual(r.breakevenCentsPerPoint ?? .nan, b, accuracy: 0.005, ctx)
            }
        }
    }
}
