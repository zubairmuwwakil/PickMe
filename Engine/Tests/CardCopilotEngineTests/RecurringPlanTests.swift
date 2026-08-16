import XCTest
@testable import CardCopilotEngine

final class RecurringPlanTests: XCTestCase {

    private let netflix = RecurringPayment(id: "netflix", label: "Netflix", amountCad: 16.99,
                                           cadence: .monthly, category: "streaming",
                                           placement: .card("wealthsimple-vip"))
    private let insurance = RecurringPayment(id: "insurance", label: "Insurance", amountCad: 200,
                                             cadence: .monthly, category: "recurring", mcc: 6300,
                                             placement: .offWallet)

    func testAnnualisationFollowsCadence() {
        XCTAssertEqual(netflix.annualCad, 203.88, accuracy: 0.01)
        XCTAssertEqual(RecurringPayment(id: "q", label: "Quarterly", amountCad: 90,
                                        cadence: .quarterly, category: "recurring",
                                        placement: .unknown).annualCad, 360, accuracy: 0.01)
    }

    /// The bridge into the keep/cancel layer. `PortfolioAnalyzer` has only ever run on the
    /// placeholder household profile, which is a documented guess (decision #19). Declared
    /// recurring bills are the owner's own numbers — the first input to that layer that isn't
    /// an assumption about them.
    func testPlanConvertsToASpendDistributionCarryingMccAndTheRecurringFlag() {
        let plan = RecurringPlan(planId: "declared-2026", basis: "owner's subscription list",
                                 payments: [netflix, insurance])

        let distribution = plan.asSpendDistribution()

        XCTAssertEqual(distribution.totalAnnualCad, 203.88 + 2_400, accuracy: 0.01)
        let streaming = distribution.buckets.first { $0.label == "Netflix" }
        XCTAssertEqual(streaming?.context.mcc, 5968, "representative MCC should be carried across")
        XCTAssertEqual(streaming?.context.recurringIndicator, true)
        XCTAssertTrue(distribution.basis.contains("owner's subscription list"), distribution.basis)
    }

    /// A refuted flag has to survive the conversion, or the keep/cancel layer would re-earn
    /// Scotia's 4% on a bill a statement already proved doesn't get it.
    func testRefutedFlagCrossesIntoTheDistributionAsNotRecurring() {
        var refuted = insurance
        refuted = RecurringPayment(id: refuted.id, label: refuted.label, amountCad: refuted.amountCad,
                                   cadence: refuted.cadence, category: refuted.category,
                                   mcc: refuted.mcc, placement: refuted.placement,
                                   flagStatus: .refuted)
        let plan = RecurringPlan(planId: "p", basis: "b", payments: [refuted])

        XCTAssertEqual(plan.asSpendDistribution().buckets.first?.context.recurringIndicator, false)
    }

    /// The converted plan has to be something `PortfolioAnalyzer` can actually consume — that
    /// is the entire point of the bridge, and a shape mismatch would only show up here.
    func testConvertedPlanRunsThroughThePortfolioAnalyzer() throws {
        let plan = RecurringPlan(planId: "declared", basis: "owner's list",
                                 payments: [netflix, insurance])
        let analyzer = PortfolioAnalyzer(catalogue: try SeedLoader.loadCatalogue(),
                                         ownerState: try SeedLoader.loadPinnedOwnerState())

        let analysis = analyzer.analyze(plan.asSpendDistribution(), asOf: "2026-08-16")

        XCTAssertEqual(analysis.totalAnnualSpendCad, 203.88 + 2_400, accuracy: 0.01)
        XCTAssertGreaterThan(analysis.portfolioValueCad, 0)
    }

    /// The shipped placeholder is scaffolding, and it has to keep exercising the cases the
    /// audit exists to surface — the same coverage guard decision #19 puts on the placeholder
    /// spend profile. If a future edit leaves every bill flag-independent and on a card, the
    /// report stops demonstrating anything.
    func testPlaceholderPlanExercisesEveryCaseTheAuditReportsOn() throws {
        let plan = RecurringPlan.placeholderSubscriptions
        XCTAssertTrue(plan.basis.uppercased().contains("ASSUMPTION"), plan.basis)
        XCTAssertTrue(plan.payments.contains { $0.placement == .offWallet },
                      "needs a bill paid off-wallet — the largest single win the audit finds")

        let audit = RecurringAuditor(catalogue: try SeedLoader.loadCatalogue(),
                                     ownerState: try SeedLoader.loadPinnedOwnerState())
            .audit(plan, asOf: "2026-08-16")

        XCTAssertTrue(audit.assignments.contains { $0.robustness == .flagIndependent })
        XCTAssertTrue(audit.assignments.contains {
            if case .flagContingent = $0.robustness { return true }
            return false
        }, "needs a bill whose answer depends on the network's recurring flag")
    }
}
