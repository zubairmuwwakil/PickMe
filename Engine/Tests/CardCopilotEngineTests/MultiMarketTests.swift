import XCTest
@testable import CardCopilotEngine

/// Targeted coverage for the 2026-08-26 multi-market capabilities (Money-shaped fee/credit
/// values, market/billingCurrency, spendNative replacing spendCad, calendarQuarter, draft
/// status) — deliberately NOT added to engine-fixtures.json, the cross-language contract keyed
/// to the real 41-card catalogue, every one of which is CAD-billing today. A synthetic card
/// belongs here, constructed directly, never in the shared production catalogue (D3's sourcing
/// bar).
///
/// Mirrors `MultiMarketTest.kt` (Android) and `multiMarket.test.ts` (MoneyTalks) — the three
/// should stay in lockstep, since that's the whole point of the shared-semantics contract.
final class MultiMarketTests: XCTestCase {

    private let asOf = "2026-08-26"

    private func usdCashbackCard(status: CardStatus? = nil) -> CardProduct {
        CardProduct(
            cardId: "usd-cashback-test",
            officialName: "Test USD Cashback Card",
            issuer: "Test Bank",
            market: .us,
            billingCurrency: .usd,
            network: .visa,
            kind: .credit,
            status: status,
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
                EarnRule(ruleId: "base", status: .current,
                         sourceType: .issuerConfirmed,
                         earn: .cashback(rate: 0.01, rewardCurrency: nil),
                         predicate: Predicate(),
                         capId: nil),
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

    private func ownerState(ownedCardIds: [String] = [], cardStates: [String: CardState] = [:]) -> OwnerState {
        OwnerState(ownerStateVersion: "test", ownedCardIds: ownedCardIds, defaultCardId: "usd-cashback-test",
                   switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0, minAdvantageCad: 0, semantics: "either"),
                   carry: Carry(drawerCards: []), cardStates: cardStates,
                   valuationsCad: Valuations(programs: ["cashback": .cashback(CashBackValuation(cadPerDollar: 1))]))
    }

    /// A synthetic two-meter rule. The first cap's post-cap rate is intentionally different
    /// from the second's so the test also pins which fallback earn binds.
    private func multiCapUsdCashbackCard() -> CardProduct {
        var card = usdCashbackCard()
        card.earnRules[0] = EarnRule(
            ruleId: "grocery-5x-multi-cap", status: .current,
            sourceType: .issuerConfirmed,
            earn: .cashback(rate: 0.05, rewardCurrency: nil),
            predicate: {
                var p = Predicate()
                p.categories = ["grocery"]
                return p
            }(),
            capIds: ["grocery-cap", "global-cap"])
        card.caps.append(
            Cap(capId: "global-cap", measure: .spendNative, limit: 1500,
                period: .calendarQuarter, anchor: nil, resetTimeZone: "UTC",
                postCapEarn: .cashback(rate: 0.005, rewardCurrency: nil), proration: true)
        )
        return card
    }

    func testEarnsOnTheUsdEquivalentAmountNotTheCadAmount() {
        let purchase = PurchaseContext(amountCad: 137, currency: "CAD", usdEquivalent: 100, category: "grocery")
        let score = Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: ownerState(), asOf: asOf)
        XCTAssertFalse(score.excluded)
        XCTAssertEqual(score.appliedRuleId, "grocery-5x-quarterly")
        // 5% of the $100 USD equivalent (= US$5 cashback), converted to the CAD reporting figure
        // — NOT left as if US$5 were C$5. Cashback is real money in the card's billing currency,
        // unlike points (a currency-agnostic token), so this conversion is load-bearing.
        let expectedCad = 100 * 0.05 * ReportingCurrency.pinnedUsdToCad
        XCTAssertEqual(score.rewardUnits, expectedCad, accuracy: 0.000001)
        XCTAssertEqual(score.grossRewardCad, expectedCad, accuracy: 0.000001)
    }

    func testFallsBackToThePinnedRateWhenNoUsdEquivalentSupplied() {
        let purchase = PurchaseContext(amountCad: 137, currency: "CAD", category: "grocery")
        let score = Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: ownerState(), asOf: asOf)
        // CAD -> USD (fallbackCadToUsd) to compute native earn, then USD -> CAD (its exact
        // inverse) to report it — the two conversions cancel, leaving 137 * 0.05.
        let expected = 137 * Scorer.fallbackCadToUsd * 0.05 * ReportingCurrency.pinnedUsdToCad
        XCTAssertEqual(score.rewardUnits, expected, accuracy: 0.000001)
    }

    func testChargesFxWhenPurchaseCurrencyDiffersFromTheCardsBillingCurrency() {
        let purchase = PurchaseContext(amountCad: 137, currency: "CAD", usdEquivalent: 100, category: "other")
        let score = Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: ownerState(), asOf: asOf)
        let expectedFxCad = (100 * 0.025) * ReportingCurrency.pinnedUsdToCad
        XCTAssertEqual(score.fxCostCad, expectedFxCad, accuracy: 0.000001)
    }

    func testChargesNoFxWhenPurchaseCurrencyMatchesTheCardsUsdBillingCurrency() {
        let purchase = PurchaseContext(amountCad: 137, currency: "USD", usdEquivalent: 100, category: "other")
        let score = Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: ownerState(), asOf: asOf)
        XCTAssertEqual(score.fxCostCad, 0)
    }

    func testSplitsAQuarterlyCapStraddleUsingTheNativeUsdAmount() {
        let purchase = PurchaseContext(amountCad: 274, currency: "CAD", usdEquivalent: 200, category: "grocery")
        var state = CardState()
        state.capProgress = ["grocery-cap": 1400]
        let owner = ownerState(cardStates: ["usd-cashback-test": state])
        let score = Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: owner, asOf: asOf)
        let expected = (100 * 0.05 + 100 * 0.01) * ReportingCurrency.pinnedUsdToCad
        XCTAssertEqual(score.rewardUnits, expected, accuracy: 0.000001)
    }

    func testMultipleCapsUseTheTightestRoomAndFirstCapsPostCapEarn() {
        let purchase = PurchaseContext(amountCad: 274, currency: "CAD",
                                       usdEquivalent: 200, category: "grocery")
        var state = CardState()
        // Both meters are nearly exhausted; grocery has $100 room, global only $10. The global
        // meter therefore constrains the accelerated portion, while the FIRST cap supplies the
        // post-cap 1% fallback (the second deliberately says 0.5%).
        state.capProgress = ["grocery-cap": 1400, "global-cap": 1490]
        let owner = ownerState(cardStates: ["usd-cashback-test": state])
        let score = Scorer.score(card: multiCapUsdCashbackCard(), purchase: purchase,
                                 ownerState: owner, asOf: asOf)
        let expected = (10 * 0.05 + 190 * 0.01) * ReportingCurrency.pinnedUsdToCad
        XCTAssertEqual(score.rewardUnits, expected, accuracy: 0.000001)
        XCTAssertEqual(score.warnings.filter { $0 == .capNearlyExhausted }.count, 1)
    }

    func testExcludesADraftCardEvenWhenOwned() {
        let purchase = PurchaseContext(amountCad: 100, currency: "CAD", category: "grocery")
        let owner = ownerState(ownedCardIds: ["usd-cashback-test"])
        let score = Scorer.score(card: usdCashbackCard(status: .draft), purchase: purchase, ownerState: owner, asOf: asOf)
        XCTAssertTrue(score.excluded)
    }

    func testScoresNormallyWhenStatusIsPublishedOrAbsent() {
        let purchase = PurchaseContext(amountCad: 100, currency: "CAD", usdEquivalent: 73, category: "grocery")
        XCTAssertFalse(Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: ownerState(), asOf: asOf).excluded)
        XCTAssertFalse(Scorer.score(card: usdCashbackCard(status: .published), purchase: purchase, ownerState: ownerState(), asOf: asOf).excluded)
    }
}
