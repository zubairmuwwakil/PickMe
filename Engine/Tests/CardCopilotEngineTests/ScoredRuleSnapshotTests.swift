import XCTest
@testable import CardCopilotEngine

final class ScoredRuleSnapshotTests: XCTestCase {

    private func sampleRule() -> EarnRule {
        EarnRule(ruleId: "test-grocery-5x",
                 status: .current,
                 effectiveFrom: "2026-01-01",
                 sourceType: .issuerConfirmed,
                 earn: .points(pointsPerCad: 5),
                 predicate: Predicate())
    }

    private func sampleCard(rule: EarnRule) -> CardProduct {
        CardProduct(cardId: "amex-cobalt",
                    officialName: "Cobalt",
                    issuer: "American Express Canada",
                    network: .amex,
                    kind: .credit,
                    fee: Fee(annualCad: 156),
                    program: Program(programId: "amexMembershipRewards", unit: "point"),
                    fxRules: [],
                    earnRules: [rule],
                    caps: [],
                    perTransactionRewardVisibility: "none",
                    lastVerifiedAt: "2026-08-15",
                    credits: nil)
    }

    private func sampleScore(ruleId: String?) -> CandidateScore {
        CandidateScore(cardId: "amex-cobalt", appliedRuleId: ruleId, rewardUnits: 500,
                       grossRewardCad: 10, fxCostCad: 0, netValueCad: 10,
                       floorNetValueCad: 5, aspirationalNetValueCad: 12,
                       warnings: [.capNearlyExhausted], excluded: false, exclusionReason: nil)
    }

    /// The snapshot must survive a round trip through the exact encoding the store persists.
    func testRoundTripsThroughJSON() throws {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ScoredRuleSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    /// The whole rule is frozen, not a re-derived summary of it.
    func testFreezesTheRuleThatActuallyWon() {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        XCTAssertEqual(snapshot.appliedRule, rule)
        XCTAssertEqual(snapshot.appliedRule?.earn, .points(pointsPerCad: 5))
    }

    /// An excluded card has no applied rule. That is a real outcome, not a capture failure.
    func testCapturesAnExclusionWithNoRule() {
        let rule = sampleRule()
        var score = sampleScore(ruleId: nil)
        score = CandidateScore(cardId: "amex-cobalt", appliedRuleId: nil, rewardUnits: 0,
                               grossRewardCad: 0, fxCostCad: 0, netValueCad: 0,
                               floorNetValueCad: 0, aspirationalNetValueCad: 0,
                               warnings: [.networkNotAccepted], excluded: true,
                               exclusionReason: "amex not accepted")

        let snapshot = ScoredRuleSnapshot.capture(
            score: score, card: sampleCard(rule: rule), asOf: "2026-08-26",
            programId: "amexMembershipRewards", unit: "point", centsPerPoint: 2.0)

        XCTAssertNil(snapshot.appliedRule)
        XCTAssertTrue(snapshot.excluded)
        XCTAssertEqual(snapshot.exclusionReason, "amex not accepted")
    }

    /// The valuation is an input, and a changed valuation must not retroactively rewrite
    /// what a past prediction was based on.
    func testFreezesTheValuationUsed() {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        XCTAssertEqual(snapshot.programId, "amexMembershipRewards")
        XCTAssertEqual(snapshot.unit, "point")
        XCTAssertEqual(snapshot.centsPerPoint, 2.0)
    }

    func testDeclaresItsOwnVersion() {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        XCTAssertEqual(snapshot.snapshotVersion, ScoredRuleSnapshot.currentVersion)
    }
}
