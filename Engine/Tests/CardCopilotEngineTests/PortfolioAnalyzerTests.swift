import XCTest
@testable import CardCopilotEngine

/// The keep/cancel layer. Every case here exists to defend one claim: a card is worth what the
/// wallet would lose without it, not what it earns.
/// Pinned valuation per decision #16 — a preference change must never re-baseline these numbers.
final class PortfolioAnalyzerTests: XCTestCase {

    private func analyzer(mrCentsPerPoint: Double = 1.8) throws -> PortfolioAnalyzer {
        PortfolioAnalyzer(catalogue: try SeedLoader.loadCatalogue(),
                          ownerState: try SeedLoader.loadPinnedOwnerState(mrCentsPerPoint: mrCentsPerPoint))
    }

    /// $12,000/yr of restaurant spend, MR pinned at 1.8¢.
    ///   Cobalt   5× MR @ 1.8¢ = 9.0%  → $1,080 gross
    ///   MBNA     5× MBNA @ 1.0¢ = 5.0% → $600 if Cobalt were gone
    /// Cobalt is worth the $480 gap, not the $1,080 it earns. Fee $191.88 → $288.12 net.
    func testMarginalValueIsTheGapToTheNextBestCardNotGrossRewards() throws {
        let distribution = SpendDistribution(
            profileId: "dining-only",
            basis: "synthetic: one category, sized to stay under every cap",
            buckets: [.init(label: "Restaurants", annualCad: 12_000, category: "dining", mcc: 5812)])

        let analysis = try analyzer().analyze(distribution, asOf: "2026-08-20")
        let cobalt = try XCTUnwrap(analysis.contributions.first { $0.cardId == "amex-cobalt" })

        XCTAssertEqual(cobalt.grossRewardValueCad, 1_080, accuracy: 0.01)
        XCTAssertEqual(cobalt.marginalValueCad, 480, accuracy: 0.01)
        XCTAssertEqual(cobalt.annualFeeCad, 191.88, accuracy: 0.01)
        XCTAssertEqual(cobalt.netContributionCad, 288.12, accuracy: 0.01)
    }

    /// $60,000/yr of restaurant spend — $5,000 a month — deliberately blows through two caps of
    /// different shapes, and the answer has to survive both.
    ///   Cobalt: $2,500/mo at 5×, the rest at 1× → 15,000 pts/mo @ 1.8¢ = $270 → $3,240/yr
    ///   Without Cobalt the wallet cannot simply fall to MBNA: MBNA's $50,000 *annual* 5× cap is
    ///   spent by the end of month 10, after which Platinum's uncapped 2× @ 1.8¢ ($180/mo) beats
    ///   MBNA's post-cap 1× ($50/mo). So the fallback is $250×10 + $180×2 = $2,860, and Cobalt is
    ///   worth $380 — not the $3,240 it earns, and not the $640 a fallback that ignored MBNA's
    ///   annual cap would have claimed.
    func testMarginalValueHonoursMonthlyAndAnnualCapsAndRecoversWhenACapRunsOut() throws {
        let distribution = SpendDistribution(
            profileId: "dining-over-cap",
            basis: "synthetic: sized to exhaust Cobalt's monthly cap and MBNA's annual cap",
            buckets: [.init(label: "Restaurants", annualCad: 60_000, category: "dining", mcc: 5812)])

        let analyzer = try analyzer()
        let analysis = analyzer.analyze(distribution, asOf: "2026-08-20")
        let cobalt = try XCTUnwrap(analysis.contribution("amex-cobalt"))

        XCTAssertEqual(cobalt.grossRewardValueCad, 3_240, accuracy: 0.01)
        XCTAssertEqual(cobalt.marginalValueCad, 380, accuracy: 0.01)

        // The fallback is not one card — MBNA carries ten months, Platinum the last two.
        let without = analyzer.run(distribution, excluding: ["amex-cobalt"], asOf: "2026-08-20")
        XCTAssertEqual(without.totalValueCad, 2_860, accuracy: 0.01)
        XCTAssertEqual(without.winnersByBucket["Restaurants"], ["mbna-rewards-we", "amex-platinum"])
    }

    // MARK: - Verdicts

    /// A $0 fee card cannot cost the owner anything, so there is no decision to make and no
    /// benefit value it needs to justify — however little it earns.
    func testZeroFeeCardIsFreeToKeepHoweverLittleItEarns() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let tangerine = try XCTUnwrap(analysis.contribution("tangerine-moneyback-world"))

        XCTAssertEqual(tangerine.annualFeeCad, 0)
        XCTAssertEqual(tangerine.verdict, .freeToKeep)
        XCTAssertEqual(tangerine.requiredBenefitValueCad, 0)
    }

    func testCardWhoseMarginalValueClearsItsFeeIsAKeepAndNeedsNoBenefits() throws {
        let distribution = SpendDistribution(
            profileId: "dining-only", basis: "synthetic",
            buckets: [.init(label: "Restaurants", annualCad: 12_000, category: "dining", mcc: 5812)])

        let cobalt = try XCTUnwrap(try analyzer().analyze(distribution, asOf: "2026-08-20")
            .contribution("amex-cobalt"))

        XCTAssertEqual(cobalt.verdict, .keep)
        XCTAssertEqual(cobalt.requiredBenefitValueCad, 0)
    }

    /// Platinum at the MR cash floor: Cobalt already out-earns it everywhere it could win, so the
    /// $799 rests entirely on lounges, credits and insurance — which this engine refuses to price.
    /// The deliverable is the threshold, not a guess at what those are worth.
    func testPlatinumFeeIsDisclosedAsARequiredBenefitValueNotAnInventedOne() throws {
        let platinum = try XCTUnwrap(try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
            .contribution("amex-platinum"))

        XCTAssertEqual(platinum.annualFeeCad, 799)
        XCTAssertLessThan(platinum.marginalValueCad, platinum.annualFeeCad)
        XCTAssertEqual(platinum.requiredBenefitValueCad,
                       799 - platinum.marginalValueCad, accuracy: 0.01)
        // Cancel, not downgrade: Cobalt keeps the Membership Rewards balance alive without it.
        XCTAssertEqual(platinum.verdict, .cancel)
    }

    /// Bonvoy earns something no other card can (5× at Marriott) but nowhere near its $120, and it
    /// is the wallet's only Bonvoy card — cancelling outright forfeits the currency, so the honest
    /// verdict is "cheaper product in the same family", not "cancel".
    func testSoleHolderOfARewardsProgramIsADowngradeRatherThanACancel() throws {
        let bonvoy = try XCTUnwrap(try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
            .contribution("amex-bonvoy"))

        XCTAssertGreaterThan(bonvoy.marginalValueCad, 0)
        XCTAssertLessThan(bonvoy.marginalValueCad, 120)
        XCTAssertEqual(bonvoy.verdict, .downgrade)
    }

    /// Crypto.com is gated out by owner state (Level Up Pro inactive), so it earns nothing on any
    /// purchase. That has to read as "not in play", not as a card that happens to score zero.
    func testCardGatedOutByOwnerStateIsMarkedNeverScorable() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let crypto = try XCTUnwrap(analysis.contribution("cryptocom-royal-indigo"))

        XCTAssertTrue(crypto.neverScorable)
        XCTAssertEqual(crypto.marginalValueCad, 0, accuracy: 0.01)

        // Every OTHER never-scorable card must be one the catalogue ratchet already admits it
        // cannot value. Derived from knownUnvaluedPrograms rather than listed again here, so
        // Task 7 tightens this back to exactly [crypto] by emptying that allowlist — a second
        // hand-kept list would have to be remembered, and would rot into a rubber stamp.
        let cannotBeValued = Set(try SeedLoader.loadCatalogue().cards
            .filter { CatalogueIntegrityTests.knownUnvaluedPrograms.contains($0.program.programId) }
            .map(\.cardId))
        XCTAssertEqual(Set(analysis.contributions.filter(\.neverScorable).map(\.cardId)),
                       cannotBeValued.union(["cryptocom-royal-indigo"]),
                       "a card is never-scorable only if owner state gates it out or its program "
                     + "has no valuation — anything else here is the engine losing a card silently")
    }

    /// Wealthsimple's $240 is waived on assets or direct deposit and the owner hasn't told us
    /// which — so the verdict is computed at the stated fee and flagged, never guessed either way.
    func testConditionalFeeIsFlaggedRatherThanAssumedWaived() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let wealthsimple = try XCTUnwrap(analysis.contribution("wealthsimple-vip"))

        XCTAssertTrue(wealthsimple.feeWaiverUnresolved)
        XCTAssertEqual(wealthsimple.annualFeeCad, 240)
        XCTAssertFalse(try XCTUnwrap(analysis.contribution("amex-cobalt")).feeWaiverUnresolved)
    }

    // MARK: - Why a marginal value is what it is

    /// A marginal value on its own is an unexplained number. Naming the card that absorbs the
    /// spend is what turns "$480" into an argument the owner can check.
    func testMarginalValueNamesTheCardThatAbsorbsTheSpend() throws {
        let distribution = SpendDistribution(
            profileId: "dining-only", basis: "synthetic",
            buckets: [.init(label: "Restaurants", annualCad: 12_000, category: "dining", mcc: 5812)])

        let cobalt = try XCTUnwrap(try analyzer().analyze(distribution, asOf: "2026-08-20")
            .contribution("amex-cobalt"))

        XCTAssertEqual(cobalt.backfilledBy.map(\.cardId), ["mbna-rewards-we"])
        XCTAssertEqual(cobalt.backfilledBy.first?.valueRetainedCad ?? 0, 600, accuracy: 0.01)
        XCTAssertEqual(cobalt.backfilledBy.first?.bucketLabels, ["Restaurants"])
    }

    /// The failure mode that makes a marginal-value table dangerous on its own. At the MR cash
    /// floor Cobalt's 5× and MBNA's 5× pay identically on groceries and dining, so each card's
    /// individual marginal value is tiny — cancel either one and nothing much happens. Cancel both
    /// and the wallet falls to Scotia's 4% and a 2% floor. A report that prints only the individual
    /// numbers reads as "cancel both", which is wrong by hundreds of dollars a year.
    func testTwoCardsThatCoverForEachOtherAreReportedAsAPairNotTwoCancels() throws {
        let analyzer = try analyzer(mrCentsPerPoint: 1.0)
        let analysis = analyzer.analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")
        let cobalt = try XCTUnwrap(analysis.contribution("amex-cobalt"))
        let mbna = try XCTUnwrap(analysis.contribution("mbna-rewards-we"))

        XCTAssertLessThan(cobalt.marginalValueCad, cobalt.annualFeeCad)
        XCTAssertLessThan(mbna.marginalValueCad, mbna.annualFeeCad)

        let pair = try XCTUnwrap(analysis.redundantPairs
            .first { $0.cardIds == ["amex-cobalt", "mbna-rewards-we"] })
        XCTAssertGreaterThan(pair.jointMarginalCad, pair.sumOfIndividualMarginalsCad + 100)
        XCTAssertEqual(pair.combinedAnnualFeeCad, 311.88, accuracy: 0.01)
        XCTAssertEqual(pair.jointMarginalCad,
                       analyzer.marginalValue(ofRemoving: ["amex-cobalt", "mbna-rewards-we"],
                                              from: .placeholderCanadianHousehold,
                                              asOf: "2026-08-20"),
                       accuracy: 0.01)
    }

    /// Almost any two cards overlap by a few dollars. Reporting every such pair buries the two
    /// that matter, so a pair has to be materially redundant — worth at least a tenth of the fees
    /// at stake — before it earns a line.
    func testTrivialOverlapIsNotReportedAsRedundancy() throws {
        let analysis = try analyzer(mrCentsPerPoint: 1.0)
            .analyze(.placeholderCanadianHousehold, asOf: "2026-08-20")

        for pair in analysis.redundantPairs {
            let overlap = pair.jointMarginalCad - pair.sumOfIndividualMarginalsCad
            XCTAssertGreaterThanOrEqual(overlap, 0.1 * pair.combinedAnnualFeeCad,
                                        "\(pair.cardIds) overlap by only \(overlap) against "
                                        + "\(pair.combinedAnnualFeeCad) of fees — noise, not a pair")
        }
        // MBNA and Wealthsimple overlap by about a dollar against $360 of fees.
        XCTAssertNil(analysis.redundantPairs
            .first { $0.cardIds == ["mbna-rewards-we", "wealthsimple-vip"] })
        // ...while Cobalt and MBNA, which pay the same 5x on the same categories, do qualify.
        XCTAssertNotNil(analysis.redundantPairs
            .first { $0.cardIds == ["amex-cobalt", "mbna-rewards-we"] })
    }

    // MARK: - Multi-market: quarterly caps and native-currency accrual across the simulated year

    /// A USD-billing card with a $1,500 USD/quarter grocery cap — the annual simulation's own
    /// synthetic fixture, not the shared CAD-only catalogue. `amountCad` is deliberately NOT
    /// `usdEquivalent * 1.37` in the tidy way a real FX rate would produce; it's picked so the two
    /// numbers are far enough apart that a currency mix-up in cap accrual is impossible to miss.
    private func quarterlyUsdCashbackCard() -> CardProduct {
        CardProduct(
            cardId: "usd-cashback-quarterly-test",
            officialName: "Test USD Quarterly Cashback Card",
            issuer: "Test Bank",
            market: .us,
            billingCurrency: .usd,
            network: .visa,
            kind: .credit,
            fee: Fee(),
            program: Program(programId: "cashback", unit: "cashback"),
            fxRules: [FxRule(status: .current, effectiveFrom: nil, effectiveTo: nil, rate: 0.025,
                             freeAllowanceCadPerCalendarMonth: nil, postAllowanceRate: nil)],
            earnRules: [
                EarnRule(ruleId: "grocery-5x-quarterly", status: .current,
                         sourceType: .issuerConfirmed,
                         earn: .cashback(rate: 0.05, rewardCurrency: nil),
                         predicate: {
                             var p = Predicate()
                             p.categories = ["grocery"]
                             return p
                         }(),
                         capId: "grocery-cap"),
            ],
            caps: [
                Cap(capId: "grocery-cap", measure: .spendNative, limit: 1500, period: .calendarQuarter,
                    anchor: nil, resetTimeZone: "UTC",
                    postCapEarn: .cashback(rate: 0.01, rewardCurrency: nil), proration: true),
            ],
            perTransactionRewardVisibility: "issuerConfirmed",
            lastVerifiedAt: "2026-08-26",
            credits: nil)
    }

    /// Twelve months of grocery spend sized to blow through the $1,500 USD quarterly cap by the
    /// third month of every quarter — so a full year is four identical quarters *only if* the cap
    /// actually resets every three months and is checked against the same currency it accrues in.
    ///
    /// Before this fix: `resetMonthlyCaps` never reset a `.calendarQuarter` cap at all, so month 4
    /// onward stayed permanently over-cap; separately, `accrueCapProgress` recorded
    /// `purchase.amountCad` (here, a CAD figure picked to diverge sharply from the $600 USD
    /// actually spent) against a limit denominated in the card's own USD billing currency. Either
    /// bug alone moves the annual total far from the value below; this pins the fixed number so
    /// neither can silently come back.
    func testQuarterlyCapsResetAndAccrueInTheCardsNativeCurrencyOverAFullYear() throws {
        let catalogue = Catalogue(cards: [quarterlyUsdCashbackCard()])
        let ownerState = OwnerState(
            ownerStateVersion: "test", ownedCardIds: [], defaultCardId: "usd-cashback-quarterly-test",
            switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0, minAdvantageCad: 0,
                                             semantics: "either"),
            carry: Carry(drawerCards: []), cardStates: [:],
            valuationsCad: Valuations(programs: ["cashback": .cashback(CashBackValuation(cadPerDollar: 1))]))

        let distribution = SpendDistribution(
            profileId: "quarterly-cap-currency-check",
            basis: "synthetic: $600 USD/mo of grocery spend against a $1,500 USD/quarter cap, "
                 + "quoted at a CAD amount ($822/mo) chosen to diverge sharply from $600 so a "
                 + "currency mix-up in cap accrual cannot cancel out unnoticed",
            buckets: [.init(label: "Groceries", annualCad: 822.0 * 12, category: "grocery",
                            usdEquivalent: 600.0 * 12)])

        let analyzer = PortfolioAnalyzer(catalogue: catalogue, ownerState: ownerState)
        let run = analyzer.run(distribution, excluding: [], asOf: "2026-01-01")

        // Every quarter: $600 in-cap at 5% for two months, then a 3rd month split $300 in-cap /
        // $300 over-cap (300×0.05 + 300×0.01) — 78 USD cashback units/quarter, ×4 quarters, minus
        // the 2.5% FX spread charged every month on the full $600 USD (never gated by the cap),
        // all converted to CAD at the pinned USD→CAD rate. Broken into named sub-expressions
        // (rather than one long sum) so the type checker isn't asked to solve it all at once.
        let inCapMonthsUsd: Double = 600.0 * 0.05 + 600.0 * 0.05
        let straddleMonthUsd: Double = 300.0 * 0.05 + 300.0 * 0.01
        let quarterlyUnitsUsd = inCapMonthsUsd + straddleMonthUsd
        let quarterlyFxUsd: Double = 600.0 * 0.025 * 3
        let expected = (quarterlyUnitsUsd * 4 - quarterlyFxUsd * 4) * ReportingCurrency.pinnedUsdToCad
        XCTAssertEqual(run.totalValueCad, expected, accuracy: 0.01)
    }

    /// A current-window checkout credit may choose a card for one real purchase, but it must not
    /// be replayed over every synthetic month in keep/cancel's forward year.
    func testPortfolioSimulationDoesNotReplayCheckoutCreditAcrossTheYear() {
        var dining = Predicate()
        dining.categories = ["dining"]
        let credit = CardCredit(
            creditId: "monthly-dining", label: "Monthly dining credit",
            value: Money(amount: 10, currency: .cad),
            schedule: CreditSchedule(basis: .calendar, unit: .month),
            redemptionMethod: .statementCredit, purchasePredicate: dining,
            allowsPartialUse: true, enrollment: CreditEnrollment(required: false),
            sourceType: .issuerConfirmed, lastVerifiedAt: "2026-08-31")

        func card(_ id: String, rate: Double, credits: [CardCredit]? = nil) -> CardProduct {
            CardProduct(
                cardId: id, officialName: id, issuer: "Test Bank", network: .visa, kind: .credit,
                fee: Fee(), program: Program(programId: "cashback", unit: "cashback"),
                fxRules: [FxRule(status: .current, effectiveFrom: nil, effectiveTo: nil, rate: 0,
                                 freeAllowanceCadPerCalendarMonth: nil, postAllowanceRate: nil)],
                earnRules: [EarnRule(ruleId: "base", status: .current,
                                     sourceType: .issuerConfirmed,
                                     earn: .cashback(rate: rate, rewardCurrency: nil),
                                     predicate: Predicate())],
                caps: [], perTransactionRewardVisibility: "issuerConfirmed",
                lastVerifiedAt: "2026-08-31", credits: credits)
        }

        let catalogue = Catalogue(cards: [card("credit-card", rate: 0, credits: [credit]),
                                          card("two-percent", rate: 0.02)])
        let owner = OwnerState(
            ownerStateVersion: "test", ownedCardIds: ["credit-card", "two-percent"],
            defaultCardId: "two-percent",
            switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0,
                                             minAdvantageCad: 0, semantics: "either"),
            carry: Carry(drawerCards: []), cardStates: ["credit-card": CardState()],
            valuationsCad: Valuations(programs: [
                "cashback": .cashback(CashBackValuation(cadPerDollar: 1))
            ]))
        let distribution = SpendDistribution(
            profileId: "credit-isolation", basis: "synthetic",
            buckets: [.init(label: "Dining", annualCad: 1_200, category: "dining")])

        let run = PortfolioAnalyzer(catalogue: catalogue, ownerState: owner)
            .run(distribution, excluding: [], asOf: "2026-08-01")
        XCTAssertEqual(run.totalValueCad, 24, accuracy: 0.001)
        XCTAssertEqual(run.valueByCard["two-percent"] ?? -1, 24, accuracy: 0.001)
        XCTAssertNil(run.valueByCard["credit-card"])
    }
}
