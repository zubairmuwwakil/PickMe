import XCTest
@testable import CardCopilotEngine

/// The keep/cancel report: what each of the ten cards is actually worth, and what the fee cards
/// need to be worth in benefits this engine refuses to price.
///
/// Unlike the behaviour spec in `PortfolioAnalyzerTests`, this runs on the **live** owner state.
/// Pinning would answer the question for a wallet Zubair doesn't have — and the valuation
/// dependency is handled the honest way instead, by running the whole analysis twice: once at the
/// declared cash floor and once at the published benchmark, then reporting which verdicts move.
///
/// Run with: swift test --filter PortfolioReportTests
final class PortfolioReportTests: XCTestCase {

    private var names: [String: String] = [:]

    /// The report's one load-bearing claim, asserted so it can't rot silently: Platinum's verdict
    /// does not depend on the Membership Rewards valuation. Even at the 2.2¢ published benchmark
    /// its marginal earn value is nowhere near $799 — so the card is a benefits question, full
    /// stop, and "your points might be worth more" is not an answer to it.
    func testPlatinumVerdictSurvivesBothEndsOfTheValuationRange() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let benchmark = owner.valuationsCad.amexMembershipRewards.aspirationalCentsPerPoint ?? 2.2

        for cents in [owner.valuationsCad.amexMembershipRewards.centsPerPoint, benchmark] {
            let platinum = try XCTUnwrap(
                PortfolioAnalyzer(catalogue: catalogue, ownerState: valued(owner, mr: cents))
                    .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
                    .contribution("amex-platinum"))
            XCTAssertEqual(platinum.verdict, .cancel,
                           "Platinum flips verdict at \(cents)¢/pt — the report's headline is stale")
            XCTAssertGreaterThan(platinum.requiredBenefitValueCad, 500,
                                 "at \(cents)¢/pt the fee is mostly a benefits bet")
        }
    }

    func testPrintPortfolioReport() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        names = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0.officialName) })
        let declared = owner.valuationsCad.amexMembershipRewards.centsPerPoint
        let benchmark = owner.valuationsCad.amexMembershipRewards.aspirationalCentsPerPoint ?? 2.2
        let profile = SpendDistribution.placeholderCanadianHousehold

        let atFloor = PortfolioAnalyzer(catalogue: catalogue, ownerState: valued(owner, mr: declared))
            .analyze(profile, asOf: "2026-08-20")
        let atBenchmark = PortfolioAnalyzer(catalogue: catalogue,
                                            ownerState: valued(owner, mr: benchmark))
            .analyze(profile, asOf: "2026-08-20")

        print("""

        ══════════════════════════════════════════════════════════════════════════════════
         KEEP / CANCEL — what each card is worth on top of the rest of the wallet
        ══════════════════════════════════════════════════════════════════════════════════
        Spend profile   \(profile.profileId) — \(cad(profile.totalAnnualCad))/yr across \
        \(profile.buckets.count) categories
                        ⚠️  \(profile.basis)
        Wallet earns    \(cad(atFloor.portfolioValueCad))/yr  ·  annual fees \
        \(cad(atFloor.totalAnnualFeesCad))  ·  net \(cad(atFloor.portfolioValueCad - atFloor.totalAnnualFeesCad))
        """)

        printBottomLine(atFloor, mrCents: declared)
        printTable(atFloor, mrCents: declared)
        printTable(atBenchmark, mrCents: benchmark)

        // ── Does the valuation change any verdict? ────────────────────────────────────
        print("\n─── Does the Membership Rewards valuation change the answer? "
              + "(\(fmt(declared))¢ vs \(fmt(benchmark))¢) ───\n")
        var moved = 0
        for a in atFloor.contributions {
            guard let b = atBenchmark.contribution(a.cardId) else { continue }
            let changed = a.verdict != b.verdict
            if changed { moved += 1 }
            guard changed || abs(a.marginalValueCad - b.marginalValueCad) > 1 else { continue }
            print("  " + (changed ? "⚠️ " : "   ") + pad(short(a.cardId), 24)
                  + pad("\(a.verdict.rawValue) → \(b.verdict.rawValue)", 26)
                  + "marginal \(cad(a.marginalValueCad)) → \(cad(b.marginalValueCad))")
        }
        print("\n  \(moved) of \(atFloor.contributions.count) verdicts depend on the MR valuation.")

        // ── Cards that only look disposable because another card covers for them ──────
        if !atFloor.redundantPairs.isEmpty {
            print("\n─── Redundant pairs: cancel one, not both ───\n")
            for pair in atFloor.redundantPairs {
                print("  \(pair.cardIds.map(short).joined(separator: "  +  "))")
                print(String(format: "     individually worth %@ combined, but %@ if you cancel "
                             + "both — against %@ of fees",
                             cad(pair.sumOfIndividualMarginalsCad) as NSString,
                             cad(pair.jointMarginalCad) as NSString,
                             cad(pair.combinedAnnualFeeCad) as NSString))
            }
        }

        printDistributionSensitivity(catalogue: catalogue, owner: valued(owner, mr: declared),
                                     base: profile, baseline: atFloor)

        print("""

        ─── What this report deliberately does not do ───

          It never prices a benefit. Lounge access, annual free-night awards, elite nights,
          insurance and statement credits are all worth something and none of them are worth a
          number this engine can defend, so each fee card publishes the annual benefit value it
          needs instead. That threshold is the deliverable; judging it is the owner's job.

          Same rule as breakevenCentsPerPoint: compute the threshold, disclose it, never guess.

        """)
    }

    // MARK: - Sections

    /// The answer, in the owner's terms, at the valuation the owner actually declared.
    private func printBottomLine(_ analysis: PortfolioAnalysis, mrCents: Double) {
        print("\n─── Bottom line at the declared \(fmt(mrCents))¢/pt ───\n")
        let byVerdict = Dictionary(grouping: analysis.contributions, by: \.verdict)
        let earnsItsFee = byVerdict[.keep] ?? []
        print("  Earns its own fee:      "
              + (earnsItsFee.isEmpty ? "none — no fee card pays for itself on rewards alone"
                 : earnsItsFee.map { short($0.cardId) }.joined(separator: ", ")))
        print("  Costs nothing to hold:  "
              + (byVerdict[.freeToKeep] ?? []).map { short($0.cardId) }.joined(separator: ", "))
        print("\n  Everything else is a benefits question. These are the annual benefit values")
        print("  each fee would need — the engine will not guess whether you get them:\n")
        for c in analysis.contributions
        where c.verdict == .cancel || c.verdict == .downgrade {
            print("    " + pad(short(c.cardId), 26) + rpad(cad(c.requiredBenefitValueCad), 10)
                  + "/yr   " + (c.verdict == .downgrade
                                ? "(the wallet's only card earning this currency — a cheaper "
                                  + "product in the family keeps it)"
                                : "(another card already earns this currency, so nothing is lost)"))
        }
    }

    private func printTable(_ analysis: PortfolioAnalysis, mrCents: Double) {
        print("\n─── Membership Rewards at \(fmt(mrCents))¢/pt ───\n")
        print("  " + pad("card", 26) + rpad("gross", 10) + rpad("marginal", 11)
              + rpad("fee", 10) + rpad("net", 10) + "  " + pad("verdict", 13)
              + "benefits must be worth")
        for c in analysis.contributions {
            let flag = c.neverScorable ? "⊘ " : (c.feeWaiverUnresolved ? "? " : "  ")
            print("  " + pad(flag + short(c.cardId), 26)
                  + rpad(cad(c.grossRewardValueCad), 10) + rpad(cad(c.marginalValueCad), 11)
                  + rpad(cad(c.annualFeeCad), 10) + rpad(cad(c.netContributionCad), 10)
                  + "  " + pad(c.verdict.rawValue, 13)
                  + (c.requiredBenefitValueCad > 0 ? cad(c.requiredBenefitValueCad) + "/yr" : "—"))
        }
        print("\n  ⊘ gated out by owner state — earns nothing on any purchase")
        print("  ? fee is conditional and the condition is unrecorded — verdict computed at the "
              + "stated fee, never assumed waived")

        // Why the fee cards fall short: name whoever is already covering their spend.
        for c in analysis.contributions
        where c.marginalValueCad < c.annualFeeCad && !c.backfilledBy.isEmpty {
            let takers = c.backfilledBy.prefix(2).map { short($0.cardId) }.joined(separator: " / ")
            print("    \(short(c.cardId)) → \(takers) already covers "
                  + ellipsised(c.winningBuckets.joined(separator: ", "), 72))
        }
        for c in analysis.contributions where c.feeWaiverUnresolved {
            print("    \(short(c.cardId)) → if the \(cad(c.annualFeeCad)) waiver is active the fee "
                  + "is $0 and this becomes freeToKeep. Unrecorded in owner state.")
        }
    }

    /// A verdict that only holds for the exact numbers we guessed is not a verdict. Rescaling the
    /// whole profile tests whether spending more or less changes the answer; dropping travel tests
    /// the categories the two most expensive cards depend on.
    private func printDistributionSensitivity(catalogue: Catalogue, owner: OwnerState,
                                              base: SpendDistribution,
                                              baseline: PortfolioAnalysis) {
        let travelLabels = ["Flights", "Hotels (non-Marriott)", "Marriott stays"]
        let variants: [SpendDistribution] = [
            base.scaled(0.5, profileId: "half the spend ($20,100)"),
            base.scaled(2.0, profileId: "double the spend ($80,400)"),
            SpendDistribution(profileId: "no travel at all",
                              basis: base.basis + " with travel removed",
                              buckets: base.buckets.filter { !travelLabels.contains($0.label) }),
        ]

        print("\n─── Which verdicts survive a different spend picture? ───\n")
        var unstable: Set<String> = []
        for variant in variants {
            let analysis = PortfolioAnalyzer(catalogue: catalogue, ownerState: owner)
                .analyze(variant, asOf: "2026-08-20")
            let changes = analysis.contributions.compactMap { c -> String? in
                guard let was = baseline.contribution(c.cardId)?.verdict, was != c.verdict
                else { return nil }
                unstable.insert(c.cardId)
                return "\(short(c.cardId)): \(was.rawValue) → \(c.verdict.rawValue)"
            }
            print("  " + pad(variant.profileId, 30)
                  + (changes.isEmpty ? "no verdict changes" : changes.joined(separator: ";  ")))
        }
        print("\n  Sensitive to the spend guess: "
              + (unstable.isEmpty ? "none — every verdict held"
                 : unstable.sorted().map(short).joined(separator: ", ")))
        print("  Everything else holds across all three, so those verdicts are about the cards, "
              + "not the guess.")
    }

    // MARK: - Helpers

    private func valued(_ owner: OwnerState, mr cents: Double) -> OwnerState {
        var copy = owner
        copy.valuationsCad.amexMembershipRewards.centsPerPoint = cents
        return copy
    }

    private func cad(_ v: Double) -> String {
        v < 0 ? String(format: "-$%.2f", -v) : String(format: "$%.2f", v)
    }
    private func ellipsised(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "…"
    }
    private func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s + " " : s + String(repeating: " ", count: n - s.count)
    }
    private func rpad(_ s: String, _ n: Int) -> String {
        s.count >= n ? " " + s : String(repeating: " ", count: n - s.count) + s
    }
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private func short(_ id: String) -> String {
        (names[id] ?? id)
            .replacingOccurrences(of: "The Platinum Card from American Express", with: "Amex Platinum")
            .replacingOccurrences(of: "American Express ", with: "Amex ")
            .replacingOccurrences(of: "Wealthsimple Visa Infinite Privilege Credit Card",
                                  with: "Wealthsimple")
            .replacingOccurrences(of: "Crypto.com Prepaid Visa Card (Royal Indigo)", with: "Crypto.com")
            .replacingOccurrences(of: "Tangerine Money-Back World", with: "Tangerine Money-Back")
            .replacingOccurrences(of: " World Elite", with: "")
            .replacingOccurrences(of: " Mastercard", with: "")
            .replacingOccurrences(of: " Visa Infinite +", with: "")
            .replacingOccurrences(of: " Card", with: "")
    }
}
