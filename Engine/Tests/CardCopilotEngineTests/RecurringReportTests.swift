import XCTest
@testable import CardCopilotEngine

/// The recurring-payment audit as an owner would read it: what to move, what it's worth, and
/// which lines are a bet on a network flag nobody has checked.
///
/// Like `PortfolioReportTests`, this runs on the **live** owner state — pinning would answer the
/// question for a wallet Zubair doesn't have. The valuation dependency is handled by asserting
/// the headline at both ends of the Membership Rewards range instead.
///
/// Run with: swift test --filter RecurringReportTests
final class RecurringReportTests: XCTestCase {

    private var names: [String: String] = [:]

    /// The report's load-bearing claim, asserted so it cannot rot silently: **Scotia's 4% never
    /// wins a recurring bill that MBNA's 5× categories reach.** Utilities, memberships and
    /// digital media all pay more on MBNA at any plausible Membership Rewards valuation, so the
    /// only bills Scotia's recurring rate wins are the ones nothing else accelerates — insurance
    /// — and those are exactly the ones that need the network flag to be real.
    ///
    /// This inverts the feature's premise in a way worth keeping honest: the headline is usually
    /// "move recurring spend off Scotia", not "you'll cross Scotia's cap in November".
    func testScotiaOnlyWinsBillsThatNothingElseAcceleratesAtEitherEndOfTheValuationRange() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let benchmark = owner.valuationsCad.amexMembershipRewards.aspirationalCentsPerPoint ?? 2.2

        for cents in [owner.valuationsCad.amexMembershipRewards.centsPerPoint, benchmark] {
            let audit = RecurringAuditor(catalogue: catalogue, ownerState: valued(owner, mr: cents))
                .audit(.placeholderSubscriptions, asOf: "2026-08-16")

            for assignment in audit.assignments
            where assignment.recommendedCardId == "scotia-momentum-vi-plus" {
                guard case .flagContingent = assignment.robustness else {
                    return XCTFail("at \(cents)¢/pt, \(assignment.label) lands on Scotia without "
                                   + "depending on the recurring flag — the report's headline is stale")
                }
            }
        }
    }

    func testPrintRecurringAuditReport() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        names = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0.officialName) })
        let plan = RecurringPlan.placeholderSubscriptions
        let audit = RecurringAuditor(catalogue: catalogue, ownerState: owner)
            .audit(plan, asOf: "2026-08-16")

        print("""

        ══════════════════════════════════════════════════════════════════════════════
        RECURRING PAYMENT AUDIT — \(audit.asOf)
        \(plan.basis)
        Declared: \(money(audit.totalAnnualDeclaredCad))/yr across \(plan.payments.count) bills
        ══════════════════════════════════════════════════════════════════════════════
        """)

        let moves = audit.assignments.filter { $0.action == .move }
        let recoverable = moves.compactMap(\.annualGainCad).reduce(0, +)
        print("\nDO THIS (\(moves.count) changes, \(money(recoverable))/yr recovered)")
        for assignment in moves.sorted(by: { ($0.annualGainCad ?? 0) > ($1.annualGainCad ?? 0) }) {
            print("  • " + line(assignment))
            if case .flagContingent(let contingency) = assignment.robustness,
               contingency.testWorthRunning {
                print("      ↳ this one is a test: \(money(contingency.annualGainIfFlaggedCad))/yr "
                      + "if the charge carries the network's recurring flag, "
                      + "\(money(contingency.oneCycleCostIfNotFlaggedCad)) once if it doesn't.")
                print("      ↳ CHECK NEXT STATEMENT — 4% posted confirms it; "
                      + "1% means move it to \(name(contingency.cardIfNotFlagged)).")
            }
            for disclosure in assignment.disclosures { print("      ⚠ " + text(disclosure)) }
        }

        let below = audit.assignments.filter { $0.action == .belowBar }
        if !below.isEmpty {
            print("\nNOT WORTH A LOGIN (below \(money(RecurringAuditor.minAnnualGainCad))/yr — "
                  + "listed so you can disagree)")
            for assignment in below { print("  · " + line(assignment)) }
        }

        let settled = audit.assignments.filter { $0.action == .alreadyOptimal }
        if !settled.isEmpty {
            print("\nALREADY RIGHT")
            for assignment in settled { print("  ✓ \(assignment.label) — \(name(assignment.recommendedCardId))") }
        }

        print("\nCAP BURN — where the caps land if nothing changes")
        report(audit.projectionsAtCurrentPlacement)
        print("\nCAP BURN — if you make the changes above")
        report(audit.projectionsAtRecommendedPlacement)

        print("""

        ──────────────────────────────────────────────────────────────────────────────
        Every figure above is a forecast built on declared amounts, not on transactions
        this app has seen. If a statement shows materially more burn than these bills
        account for, something is charging that card that isn't on this list.
        ──────────────────────────────────────────────────────────────────────────────
        """)
    }

    // MARK: - Rendering

    private func report(_ outcomes: [CapProjectionOutcome]) {
        if outcomes.isEmpty { print("  (no declared bill burns a capped rate)") }
        for outcome in outcomes {
            switch outcome {
            case .refused(let cardId, let capId, let reason):
                print("  ? \(name(cardId)) / \(capId): no projection — \(reason)")
            case .projected(let projection):
                let crossing = projection.crossingMonth
                    .map { "crosses \($0)" } ?? "does not cross within the window"
                print("  • \(name(projection.cardId)) / \(projection.capId): "
                      + "\(money(projection.startingUsageCad)) → "
                      + "\(money(projection.cumulativeAtWindowEndCad)) of "
                      + "\(money(projection.limitCad)) by \(projection.window.endMonth), \(crossing)")
                switch projection.coverage {
                case .allSpendOnCard:
                    print("      every purchase on this card burns this cap — declared bills are "
                          + "a small slice of it, so the crossing month is the latest possible")
                case .categories(let categories):
                    print("      covers " + categories.joined(separator: " + "))
                    if !projection.undeclaredCategories.isEmpty {
                        print("      ⚠ any "
                              + projection.undeclaredCategories.joined(separator: " or ")
                              + " spend on this card burns the same cap, and none was declared "
                              + "here — so the crossing month is the latest possible, not an "
                              + "estimate")
                    }
                }
                if !projection.startingUsageIsAnchored {
                    print("      ⚠ the starting figure carries no as-of date — it is seeded and "
                          + "flagged suspect in owner-state.json")
                }
                if projection.restsOnAssumedFlags {
                    print("      ⚠ rests on recurring flags no statement has confirmed")
                }
                if let contention = projection.contention {
                    print("      ⚠ contention: \(money(contention.declaredDemandCad)) of demand "
                          + "for \(money(contention.roomCad)) of room, shared by "
                          + contention.competingCategories.joined(separator: " + "))
                }
            }
        }
    }

    private func line(_ assignment: RecurringAssignment) -> String {
        let from: String
        switch assignment.currentPlacement {
        case .card(let id): from = name(id)
        case .offWallet: from = "chequing / off-wallet"
        case .unknown: from = "unknown"
        }
        let gain = assignment.annualGainCad.map { " (+\(money($0))/yr)" } ?? ""
        return "\(assignment.label): \(from) → \(name(assignment.recommendedCardId))\(gain)"
    }

    private func text(_ disclosure: RecurringDisclosure) -> String {
        switch disclosure {
        case .mccAssumed(let mcc):
            return "assumes this bill codes as MCC \(mcc)"
        case .mccGateUnverified(let ruleId):
            return "rule \(ruleId) is gated on an MCC list and no MCC was known — the gate was "
                 + "never actually tested"
        case .amexAcceptanceAssumed:
            return "assumes this biller takes Amex — many Canadian billers don't"
        case .valuationSensitive(let alternate):
            return "depends on your declared point value; at the cash floor "
                 + "\(name(alternate)) wins instead"
        case .hypotheticalTangerineSelection:
            return "assumes this is one of your selected Tangerine categories"
        }
    }

    private func name(_ cardId: String) -> String { names[cardId] ?? cardId }

    private func money(_ value: Double) -> String { String(format: "$%.2f", value) }

    private func valued(_ owner: OwnerState, mr cents: Double) -> OwnerState {
        var copy = owner
        copy.valuationsCad.amexMembershipRewards.centsPerPoint = cents
        return copy
    }
}
