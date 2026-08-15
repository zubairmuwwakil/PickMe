import XCTest
@testable import CardCopilotEngine

private struct FixtureFile: Decodable { let cases: [FixtureCase] }

private struct FixtureCase: Decodable {
    let caseId: String
    let purchase: PurchaseContext
    let ownerStateOverrides: Overrides?
    let expected: Expected

    struct Overrides: Decodable { let cardStates: [String: CardState]? }

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
    }
}

/// The executable spec: every case here was hand-computed from the verified catalogue.
/// A failure means either an engine bug or a wrong expectation — never tune one to the other
/// without re-deriving the arithmetic by hand.
final class FixtureHarnessTests: XCTestCase {
    func testAllFixtures() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine-fixtures",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"))
        let file = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.cases.count, 12)

        let catalogue = try SeedLoader.loadCatalogue()
        let baseState = try SeedLoader.loadOwnerState()

        for fixture in file.cases {
            var state = baseState
            if let overrides = fixture.ownerStateOverrides?.cardStates {
                for (cardId, override) in overrides {
                    var merged = state.cardStates[cardId] ?? CardState()
                    if let cap = override.capProgress {
                        merged.capProgress = (merged.capProgress ?? [:]).merging(cap) { _, new in new }
                    }
                    if let v = override.cryptoLevelUpProActive { merged.cryptoLevelUpProActive = v }
                    if let v = override.croHandling { merged.croHandling = v }
                    if let v = override.rogersEligibleServiceLinked { merged.rogersEligibleServiceLinked = v }
                    if let v = override.selectedCategories { merged.selectedCategories = v }
                    state.cardStates[cardId] = merged
                }
            }

            let engine = RecommendationEngine(catalogue: catalogue, ownerState: state)
            let r = engine.recommend(fixture.purchase, asOf: "2026-08-20")
            let e = fixture.expected
            let ctx = "case \(fixture.caseId)"

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
            if let warnings = e.warnings {
                for w in warnings {
                    XCTAssertTrue(r.winner.warnings.map(\.rawValue).contains(w), "\(ctx): missing \(w)")
                }
            }
        }
    }
}
