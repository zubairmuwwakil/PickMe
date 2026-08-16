import XCTest
@testable import CardCopilotEngine

/// The recurring-payment assignment audit. Every case defends one claim: the engine may not
/// assert the network's recurring-payment indicator, because it has never seen a transaction.
/// Pinned valuation per decision #16.
final class RecurringAuditorTests: XCTestCase {

    private func auditor(mrCentsPerPoint: Double = 1.8) throws -> RecurringAuditor {
        RecurringAuditor(catalogue: try SeedLoader.loadCatalogue(),
                         ownerState: try SeedLoader.loadPinnedOwnerState(mrCentsPerPoint: mrCentsPerPoint))
    }

    private func plan(_ payments: RecurringPayment...) -> RecurringPlan {
        RecurringPlan(planId: "test", basis: "synthetic test plan", payments: payments)
    }

    /// A $85/month phone bill. MBNA's 5× utilities rule (MCC 4814) pays 5% whether or not the
    /// network flags the charge as recurring; Scotia's 4% needs the flag. Same winner in both
    /// worlds, so the owner can act today without waiting for a statement.
    ///   Wealthsimple 2% of $1,020 = $20.40 · MBNA 5% = $51.00 → gain $30.60/yr, 3.0pp
    func testAssignmentIsFlagIndependentWhenBothWorldsPickTheSameCard() throws {
        let phone = RecurringPayment(id: "phone", label: "Phone", amountCad: 85, cadence: .monthly,
                                     category: "householdUtilities", mcc: 4814,
                                     placement: .card("wealthsimple-vip"))

        let audit = try auditor().audit(plan(phone), asOf: "2026-08-16")
        let assignment = try XCTUnwrap(audit.assignment("phone"))

        XCTAssertEqual(assignment.recommendedCardId, "mbna-rewards-we")
        XCTAssertEqual(assignment.robustness, .flagIndependent)
        XCTAssertEqual(assignment.annualGainCad ?? 0, 30.60, accuracy: 0.01)
        XCTAssertEqual(assignment.action, .move)
    }

    /// $200/month home & auto insurance, MCC 6300, category `recurring`. The case the whole
    /// design turns on: Scotia's 4% needs the network flag and nothing else in the wallet
    /// accelerates insurance, so the two worlds pick different cards.
    ///   flagged:   Scotia 4% of $2,400 = $96/yr   ·  unflagged: Wealthsimple 2% = $48/yr
    ///   gain if the flag is real ............... $96 − $48 = $48/yr
    ///   cost of finding out (one cycle wrong) .. ($4.00 − $2.00) = $2.00, once
    /// Risking $2 once to learn something worth $48 a year is worth doing, so the engine says
    /// put it on Scotia and read next month's statement.
    func testFlagContingentBillPublishesTheBoundedRegretTest() throws {
        let insurance = RecurringPayment(id: "insurance", label: "Home & auto insurance",
                                         amountCad: 200, cadence: .monthly, category: "recurring",
                                         mcc: 6300, placement: .card("wealthsimple-vip"))

        let audit = try auditor().audit(plan(insurance), asOf: "2026-08-16")
        let assignment = try XCTUnwrap(audit.assignment("insurance"))

        guard case .flagContingent(let contingency) = assignment.robustness else {
            return XCTFail("expected a flag-contingent verdict, got \(assignment.robustness)")
        }
        XCTAssertEqual(contingency.cardIfFlagged, "scotia-momentum-vi-plus")
        XCTAssertEqual(contingency.cardIfNotFlagged, "wealthsimple-vip")
        XCTAssertEqual(contingency.annualGainIfFlaggedCad, 48, accuracy: 0.01)
        XCTAssertEqual(contingency.oneCycleCostIfNotFlaggedCad, 2, accuracy: 0.01)
        XCTAssertTrue(contingency.testWorthRunning)
        XCTAssertEqual(assignment.recommendedCardId, "scotia-momentum-vi-plus")
        XCTAssertEqual(assignment.action, .move)
    }

    /// The bounded-regret test has to be able to say no, and cadence is what makes it say so.
    /// An annual transit pass, MCC 4121, MR pinned at 1.8¢:
    ///   flagged:   Scotia's 4% recurring rule outranks its own 2% transit rule → $72/yr
    ///   unflagged: Cobalt 2× MR @ 1.8¢ = 3.6% → $64.80/yr (Scotia falls back to 2% = $36)
    ///   gain if the flag is real ............... $72.00 − $64.80 = $7.20/yr
    ///   cost of finding out .................... $64.80 − $36.00 = $28.80, and one billing
    ///                                            cycle here is a whole year
    /// Paying $28.80 to discover a $7.20 edge is a bad trade, so the engine keeps the pass on
    /// the card that does not depend on the flag.
    func testBoundedRegretTestDeclinesWhenOneCycleCostsMoreThanAYearOfBeingRight() throws {
        let pass = RecurringPayment(id: "transit-pass", label: "Annual transit pass",
                                    amountCad: 1_800, cadence: .annual, category: "transit",
                                    mcc: 4121, placement: .card("wealthsimple-vip"))

        let audit = try auditor().audit(plan(pass), asOf: "2026-08-16")
        let assignment = try XCTUnwrap(audit.assignment("transit-pass"))

        guard case .flagContingent(let contingency) = assignment.robustness else {
            return XCTFail("expected a flag-contingent verdict, got \(assignment.robustness)")
        }
        XCTAssertEqual(contingency.cardIfFlagged, "scotia-momentum-vi-plus")
        XCTAssertEqual(contingency.cardIfNotFlagged, "amex-cobalt")
        XCTAssertEqual(contingency.annualGainIfFlaggedCad, 7.20, accuracy: 0.01)
        XCTAssertEqual(contingency.oneCycleCostIfNotFlaggedCad, 28.80, accuracy: 0.01)
        XCTAssertFalse(contingency.testWorthRunning)
        XCTAssertEqual(assignment.recommendedCardId, "amex-cobalt")
    }

    /// A statement already answered the question. No branching, no experiment — the refuted
    /// flag means Scotia's 4% simply does not apply to this bill.
    func testRefutedFlagScoresOnlyTheUnflaggedWorld() throws {
        let insurance = RecurringPayment(id: "insurance", label: "Insurance", amountCad: 200,
                                         cadence: .monthly, category: "recurring", mcc: 6300,
                                         placement: .card("scotia-momentum-vi-plus"),
                                         flagStatus: .refuted)

        let audit = try auditor().audit(plan(insurance), asOf: "2026-08-16")
        let assignment = try XCTUnwrap(audit.assignment("insurance"))

        XCTAssertEqual(assignment.robustness, .flagRefuted)
        XCTAssertEqual(assignment.recommendedCardId, "wealthsimple-vip")
        XCTAssertEqual(assignment.annualGainCad ?? 0, 24, accuracy: 0.01)
        XCTAssertEqual(assignment.action, .move)
    }

    /// A bill paid by preauthorized debit from a chequing account earns nothing, so the whole
    /// reward is recoverable — the largest single win this audit can find.
    ///   $200/month insurance, nothing earned today → Scotia's flagged 4% is $96/yr of pure gain
    func testOffWalletBillCountsTheWholeRewardAsRecoverable() throws {
        let insurance = RecurringPayment(id: "insurance", label: "Insurance", amountCad: 200,
                                         cadence: .monthly, category: "recurring", mcc: 6300,
                                         placement: .offWallet)

        let assignment = try XCTUnwrap(try auditor().audit(plan(insurance), asOf: "2026-08-16")
            .assignment("insurance"))

        XCTAssertEqual(assignment.currentAnnualValueCad, 0)
        XCTAssertEqual(assignment.annualGainCad ?? 0, 96, accuracy: 0.01)
        XCTAssertEqual(assignment.action, .move)
    }

    /// The owner didn't say which card the bill sits on. The engine names the best card but
    /// publishes no gain — it will not substitute the default card for an answer it wasn't given.
    func testUnknownPlacementNamesTheBestCardButPublishesNoGain() throws {
        let phone = RecurringPayment(id: "phone", label: "Phone", amountCad: 85, cadence: .monthly,
                                     category: "householdUtilities", mcc: 4814,
                                     placement: .unknown)

        let assignment = try XCTUnwrap(try auditor().audit(plan(phone), asOf: "2026-08-16")
            .assignment("phone"))

        XCTAssertEqual(assignment.recommendedCardId, "mbna-rewards-we")
        XCTAssertNil(assignment.annualGainCad)
        XCTAssertNil(assignment.currentAnnualValueCad)
        XCTAssertEqual(assignment.action, .baselineUnknown)
    }

    /// A $5/month subscription moving to a 5.4% card gains $3.24 a year. That clears the
    /// percentage-point floor easily and still isn't worth a login, so it is reported as
    /// below the bar rather than dropped — the owner decides, but sees the number.
    func testGainUnderTheAnnualFloorIsListedRatherThanRecommended() throws {
        let small = RecurringPayment(id: "small", label: "Small subscription", amountCad: 5,
                                     cadence: .monthly, category: "streaming", mcc: 5968,
                                     placement: .offWallet)

        let assignment = try XCTUnwrap(try auditor().audit(plan(small), asOf: "2026-08-16")
            .assignment("small"))

        XCTAssertEqual(assignment.recommendedCardId, "amex-cobalt")
        XCTAssertEqual(assignment.annualGainCad ?? 0, 3.24, accuracy: 0.01)
        XCTAssertGreaterThan(assignment.advantagePercentagePoints ?? 0,
                             RecurringAuditor.minAdvantagePercentagePoints)
        XCTAssertEqual(assignment.action, .belowBar)
    }

    func testBillAlreadyOnTheWinningCardNeedsNoAction() throws {
        let phone = RecurringPayment(id: "phone", label: "Phone", amountCad: 85, cadence: .monthly,
                                     category: "householdUtilities", mcc: 4814,
                                     placement: .card("mbna-rewards-we"))

        let assignment = try XCTUnwrap(try auditor().audit(plan(phone), asOf: "2026-08-16")
            .assignment("phone"))

        XCTAssertEqual(assignment.action, .alreadyOptimal)
        XCTAssertEqual(assignment.annualGainCad ?? -1, 0, accuracy: 0.001)
    }

    // MARK: - Disclosures

    /// The owner knows the bill, not its MCC. The engine supplies a representative one and says
    /// so, rather than passing `nil` — which `RuleMatcher` reads as "gate not tested" and lets
    /// every MCC-gated 5× through.
    func testMissingMccIsSuppliedFromTheStatedTableAndDisclosed() throws {
        let netflix = RecurringPayment(id: "netflix", label: "Netflix", amountCad: 16.99,
                                       cadence: .monthly, category: "streaming",
                                       placement: .offWallet)

        let assignment = try XCTUnwrap(try auditor().audit(plan(netflix), asOf: "2026-08-16")
            .assignment("netflix"))

        XCTAssertTrue(assignment.disclosures.contains(.mccAssumed(5968)),
                      "expected a disclosed representative MCC, got \(assignment.disclosures)")
    }

    /// A meal-kit subscription the owner filed under `dining`, from a biller that doesn't take
    /// Amex. No MCC is known and `dining` is deliberately absent from the representative table,
    /// so MBNA's 5× wins on a gate that was never actually tested. That has to be said out loud:
    /// if the box codes as anything but 5812/5814, the 5% never arrives.
    func testWinningOnAnMccGateThatWasNeverTestedIsDisclosed() throws {
        let mealKit = RecurringPayment(id: "meal-kit", label: "Meal kit", amountCad: 120,
                                       cadence: .monthly, category: "dining",
                                       placement: .offWallet,
                                       declaredAcceptedNetworks: [.visa, .mastercard])

        let assignment = try XCTUnwrap(try auditor().audit(plan(mealKit), asOf: "2026-08-16")
            .assignment("meal-kit"))

        XCTAssertEqual(assignment.recommendedCardId, "mbna-rewards-we")
        XCTAssertTrue(assignment.disclosures.contains(.mccGateUnverified(ruleId: "mbna-restaurants-5x")),
                      "expected an untested MCC gate to be disclosed, got \(assignment.disclosures)")
    }

    /// Amex acceptance among Canadian billers is the live question that Visa and Mastercard
    /// acceptance is not. When an Amex card wins and the owner never said the biller takes Amex,
    /// the recommendation is contingent on something nobody checked.
    func testAmexWinnerWithUndeclaredAcceptanceIsDisclosed() throws {
        let netflix = RecurringPayment(id: "netflix", label: "Netflix", amountCad: 16.99,
                                       cadence: .monthly, category: "streaming", mcc: 5968,
                                       placement: .offWallet)

        let assignment = try XCTUnwrap(try auditor().audit(plan(netflix), asOf: "2026-08-16")
            .assignment("netflix"))

        XCTAssertEqual(assignment.recommendedCardId, "amex-cobalt")
        XCTAssertTrue(assignment.disclosures.contains(.amexAcceptanceAssumed),
                      "expected undeclared Amex acceptance to be disclosed, got \(assignment.disclosures)")
    }

    /// Decision #14 one layer up. Cobalt takes streaming at 3× MR only because MR is declared
    /// above its cash floor; at the floor, MBNA's 5× wins instead. The owner is told which
    /// assumption their autopay is resting on.
    func testWinnerThatDependsOnTheDeclaredPointValuationIsDisclosed() throws {
        let netflix = RecurringPayment(id: "netflix", label: "Netflix", amountCad: 16.99,
                                       cadence: .monthly, category: "streaming", mcc: 5968,
                                       placement: .offWallet)

        let assignment = try XCTUnwrap(try auditor().audit(plan(netflix), asOf: "2026-08-16")
            .assignment("netflix"))

        XCTAssertTrue(assignment.disclosures.contains(.valuationSensitive(alternateCardId: "mbna-rewards-we")),
                      "expected valuation sensitivity to be disclosed, got \(assignment.disclosures)")
    }

    // MARK: - Cap projection

    /// Before and after. "Following this checklist stops the cap crossing" is the actionable
    /// form of the answer, and it needs both projections to say it.
    ///   $2,000/month of utilities sitting on Scotia burns the shared 4% bucket from $12,500 and
    ///   crosses $25,000 in February 2027. MBNA's 5× utilities cap is $50,000 a year and pays
    ///   more anyway, so the recommended placement crosses nothing.
    func testAuditProjectsCapBurnAtBothCurrentAndRecommendedPlacements() throws {
        let utilities = RecurringPayment(id: "utilities", label: "Utilities", amountCad: 2_000,
                                         cadence: .monthly, category: "householdUtilities",
                                         mcc: 4814, placement: .card("scotia-momentum-vi-plus"))

        let audit = try auditor().audit(plan(utilities), asOf: "2026-08-16")

        let before = try XCTUnwrap(audit.projectionsAtCurrentPlacement
            .compactMap { if case .projected(let p) = $0 { return p } else { return nil } }
            .first { $0.capId == "momentum-4pct-accountYear" })
        XCTAssertEqual(before.crossingMonth, "2027-02")

        let after = audit.projectionsAtRecommendedPlacement
            .compactMap { outcome -> CapProjection? in
                if case .projected(let p) = outcome { return p } else { return nil }
            }
        XCTAssertEqual(after.map(\.capId), ["mbna-utilities-annual"])
        XCTAssertNil(after[0].crossingMonth)
    }

    /// A crossing month computed from bills whose recurring flag nobody has ever confirmed is
    /// resting on two unverified things, not one. The projection says so.
    func testProjectionSaysWhenItsCrossingMonthRestsOnUnverifiedFlags() throws {
        let insurance = RecurringPayment(id: "insurance", label: "Insurance", amountCad: 2_000,
                                         cadence: .monthly, category: "recurring", mcc: 6300,
                                         placement: .card("scotia-momentum-vi-plus"))

        let audit = try auditor().audit(plan(insurance), asOf: "2026-08-16")
        let projection = try XCTUnwrap(audit.projectionsAtCurrentPlacement
            .compactMap { if case .projected(let p) = $0 { return p } else { return nil } }
            .first)

        XCTAssertEqual(projection.crossingMonth, "2027-02")
        XCTAssertTrue(projection.restsOnAssumedFlags)
    }
}
