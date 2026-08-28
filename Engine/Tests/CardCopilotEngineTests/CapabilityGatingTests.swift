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
        // One corpus: the catalogue already holds candidates, so there is no second list to union.
        let all = try SeedLoader.loadCatalogue().cards.flatMap(\.earnRules)
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

/// Gating a rule out silently is the same defect as valuing a program at zero: an answer the
/// owner cannot tell apart from a considered one. A capability-blocked rule has to say so.
extension CapabilityGatingTests {

    /// A real, valued card with its earn rules replaced — cheaper than hand-building a
    /// CardProduct, and it keeps the network, program and fee fields honest.
    private func card(rules: [EarnRule]) throws -> CardProduct {
        var card = try XCTUnwrap(SeedLoader.loadCatalogue().cards
            .first { $0.cardId == "scotia-momentum-vi-plus" })
        card.earnRules = rules
        card.caps = []
        return card
    }

    private func groceryRule(_ ruleId: String, rate: Double,
                             requires: [String]? = nil,
                             outOfScope: OutOfScope? = nil) -> EarnRule {
        var predicate = Predicate()
        predicate.categories = ["grocery"]
        return EarnRule(ruleId: ruleId, status: .current, sourceType: .issuerConfirmed,
                        earn: .cashback(rate: rate, rewardCurrency: nil), predicate: predicate,
                        requires: requires, outOfScope: outOfScope)
    }

    private var grocery: PurchaseContext { PurchaseContext(amountCad: 100, category: "grocery") }

    private func score(_ card: CardProduct) throws -> CandidateScore {
        Scorer.score(card: card, purchase: grocery,
                     ownerState: try SeedLoader.loadPinnedOwnerState(), asOf: "2026-08-20")
    }

    /// The card still scores on the rule the engine can honour — but the owner is told a better
    /// rule exists that this build cannot check, rather than being shown the lesser number as
    /// though it were the whole story.
    func testCapabilityBlockedRuleWarnsOnACardThatStillScores() throws {
        let s = try score(card(rules: [
            groceryRule("live-2pct", rate: 0.02),
            groceryRule("blocked-6pct", rate: 0.06, requires: ["cap.statementYear"]),
        ]))

        XCTAssertFalse(s.excluded)
        XCTAssertEqual(s.appliedRuleId, "live-2pct", "the blocked rule must not win")
        XCTAssertEqual(s.netValueCad, 2.00, accuracy: 0.005)
        XCTAssertTrue(s.warnings.contains(.unsupportedCapability))
    }

    /// When the blocked rule was the only one that matched, the card drops out — and the reason
    /// must name the capability. "unresolved or inactive owner state" would send the owner to
    /// check settings that have nothing to do with it.
    func testCardWithOnlyCapabilityBlockedRulesExcludesAndNamesTheCapability() throws {
        let s = try score(card(rules: [
            groceryRule("blocked-6pct", rate: 0.06, requires: ["cap.statementYear"]),
        ]))

        XCTAssertTrue(s.excluded)
        XCTAssertTrue(s.warnings.contains(.unsupportedCapability))
        XCTAssertFalse(s.warnings.contains(.unresolvedOwnerState))
        XCTAssertTrue(try XCTUnwrap(s.exclusionReason).contains("cap.statementYear"),
                      "the reason must name what is missing: \(s.exclusionReason ?? "nil")")
    }

    /// An unknown capability name is a data error, and the owner-facing symptom must be the same
    /// as a known-but-unbuilt one — never a silently scored rule.
    func testUnknownCapabilityAlsoWarnsRatherThanScoring() throws {
        let s = try score(card(rules: [
            groceryRule("live-2pct", rate: 0.02),
            groceryRule("typo-6pct", rate: 0.06, requires: ["cap.inventedYesterday"]),
        ]))

        XCTAssertEqual(s.appliedRuleId, "live-2pct")
        XCTAssertTrue(s.warnings.contains(.unsupportedCapability))
    }

    /// "Never" must not surface as "not yet". An out-of-scope rule is not a gap waiting to be
    /// filled, and warning about it would advertise work nobody intends to do.
    func testOutOfScopeRuleDoesNotWarnAboutACapability() throws {
        let s = try score(card(rules: [
            groceryRule("live-2pct", rate: 0.02),
            groceryRule("never-6pct", rate: 0.06,
                        outOfScope: OutOfScope(reason: "online booking channel")),
        ]))

        XCTAssertEqual(s.appliedRuleId, "live-2pct")
        XCTAssertFalse(s.warnings.contains(.unsupportedCapability))
    }

    /// Every gap is reported once, in a stable order, however many rules named it.
    func testReportedGapsAreDeduplicatedAndSorted() throws {
        let resolution = RuleMatcher.resolve(
            card: try card(rules: [
                groceryRule("live", rate: 0.02),
                groceryRule("a", rate: 0.03, requires: ["cap.statementYear"]),
                groceryRule("b", rate: 0.04, requires: ["cap.statementYear", "cap.globalGroup"]),
            ]),
            purchase: grocery, ownerState: try SeedLoader.loadPinnedOwnerState(),
            asOf: "2026-08-20")

        guard case .applied(_, let gaps) = resolution else { return XCTFail("expected .applied") }
        XCTAssertEqual(gaps, ["cap.globalGroup", "cap.statementYear"])
    }

    /// A rule the owner could never trigger anyway is not a capability gap. Warning about it
    /// would report a gap closing which would change nothing for this owner.
    func testCapabilityGapIsNotReportedForARuleThatWouldNotHaveMatched() throws {
        let s = try score(card(rules: [
            groceryRule("live-2pct", rate: 0.02),
            {
                var r = groceryRule("blocked-but-irrelevant", rate: 0.09,
                                    requires: ["cap.statementYear"])
                r.predicate.categories = ["dining"]
                return r
            }(),
        ]))

        XCTAssertEqual(s.appliedRuleId, "live-2pct")
        XCTAssertFalse(s.warnings.contains(.unsupportedCapability),
                       "a dining rule is no gap on a grocery purchase")
    }

    /// Every rule the engine skips must say why in a machine-readable way. A bare
    /// scoredInV1:false carries no reason and cannot turn itself on when the blocker is fixed.
    func testNoRuleIsDisabledWithoutAMachineReadableReason() throws {
        let allowed: Set<String> = [
            "scotia-gold-gas-transit-3x",      // spec §9.1 — blocker unconfirmed
        ]
        let allRules: [EarnRule] = try SeedLoader.loadCatalogue().cards.flatMap(\.earnRules)
        let undeclared: [EarnRule] = allRules.filter { rule in
            rule.scoredInV1 == false && rule.requires == nil && rule.outOfScope == nil
        }
        let bare: [String] = undeclared.map(\.ruleId).filter { !allowed.contains($0) }
        XCTAssertTrue(bare.isEmpty, "rules disabled with no declared blocker: \(bare.sorted())")
    }

    /// A wallet where nothing can be scored must refuse, not crash and not invent a winner.
    func testWalletOfEntirelyUnvaluedCardsCannotAdvise() throws {
        var catalogue = try SeedLoader.loadCatalogue()
        catalogue.cards = catalogue.cards.map { card in
            var c = card
            c.program = Program(programId: "unknownProgram", unit: "point")
            return c
        }
        var owner = try SeedLoader.loadPinnedOwnerState()
        owner.ownedCardIds = catalogue.cards.map(\.cardId)

        let outcome = RecommendationEngine(catalogue: catalogue, ownerState: owner)
            .recommend(PurchaseContext(amountCad: 50, category: "grocery"), asOf: "2026-08-20")

        guard case .cannotAdvise(let reasons) = outcome
        else { return XCTFail("expected .cannotAdvise, got \(outcome)") }
        XCTAssertFalse(reasons.isEmpty, "a refusal must say why")
    }
}
