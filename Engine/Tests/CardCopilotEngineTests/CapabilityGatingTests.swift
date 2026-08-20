import XCTest
@testable import CardCopilotEngine

/// Rules declare what they need; the engine declares what it has. A mismatch must skip the rule,
/// never score it — a rule the engine cannot honour produces a number nobody can defend.
final class CapabilityGatingTests: XCTestCase {

    private func rule(requires: [String]? = nil, outOfScope: OutOfScope? = nil) -> EarnRule {
        EarnRule(ruleId: "r", status: .current, effectiveFrom: nil, effectiveTo: nil,
                 sourceType: .issuerConfirmed, earn: .cashback(rate: 0.02, rewardCurrency: nil),
                 predicate: Predicate(), capId: nil, ownerConditions: nil, scoredInV1: nil,
                 requires: requires, outOfScope: outOfScope)
    }

    func testRuleRequiringASupportedCapabilityIsLive() {
        XCTAssertTrue(RuleMatcher.isLive(rule(requires: ["cap.calendarYear"]), asOf: "2026-08-20"))
    }

    func testRuleRequiringAnUnsupportedCapabilityIsNotLive() {
        XCTAssertFalse(RuleMatcher.isLive(rule(requires: ["cap.statementYear"]), asOf: "2026-08-20"))
    }

    /// An unknown capability string is a data error and must fail closed — never be assumed
    /// supported because the engine does not recognise it.
    func testUnknownCapabilityStringIsNotLive() {
        XCTAssertFalse(RuleMatcher.isLive(rule(requires: ["cap.inventedYesterday"]),
                                          asOf: "2026-08-20"))
    }

    func testOutOfScopeRuleIsNeverLive() {
        XCTAssertFalse(RuleMatcher.isLive(
            rule(outOfScope: OutOfScope(reason: "online booking channel")), asOf: "2026-08-20"))
    }

    /// "Not yet" and "never" must stay distinguishable, or a future reader builds a capability
    /// because an out-of-scope rule appeared to ask for it.
    func testOutOfScopeIsNotExpressedAsARequirement() throws {
        let all = try SeedLoader.loadCatalogue().cards.flatMap(\.earnRules)
            + SeedLoader.loadCandidateCatalogue().cards.flatMap(\.earnRules)
        for r in all where r.outOfScope != nil {
            XCTAssertNil(r.requires,
                "\(r.ruleId): a permanently out-of-scope rule must not also declare requires")
        }
        for name in all.compactMap(\.requires).flatMap({ $0 }) {
            XCTAssertNotNil(EngineCapability(rawValue: name),
                            "\(name) is not a known EngineCapability")
        }
    }
}
