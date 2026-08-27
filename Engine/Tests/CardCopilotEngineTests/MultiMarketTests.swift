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

    func testEarnsOnTheUsdEquivalentAmountNotTheCadAmount() {
        let purchase = PurchaseContext(amountCad: 137, currency: "CAD", usdEquivalent: 100, category: "grocery")
        let score = Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: ownerState(), asOf: asOf)
        XCTAssertFalse(score.excluded)
        XCTAssertEqual(score.appliedRuleId, "grocery-5x-quarterly")
        XCTAssertEqual(score.rewardUnits, 5, accuracy: 0.000001)
        XCTAssertEqual(score.grossRewardCad, 5, accuracy: 0.000001)
    }

    func testFallsBackToThePinnedRateWhenNoUsdEquivalentSupplied() {
        let purchase = PurchaseContext(amountCad: 137, currency: "CAD", category: "grocery")
        let score = Scorer.score(card: usdCashbackCard(), purchase: purchase, ownerState: ownerState(), asOf: asOf)
        XCTAssertEqual(score.rewardUnits, 137 * Scorer.fallbackCadToUsd * 0.05, accuracy: 0.000001)
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
        XCTAssertEqual(score.rewardUnits, 100 * 0.05 + 100 * 0.01, accuracy: 0.000001)
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
