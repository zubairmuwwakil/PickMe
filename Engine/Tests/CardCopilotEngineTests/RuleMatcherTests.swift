import XCTest
@testable import CardCopilotEngine

final class RuleMatcherTests: XCTestCase {
    var catalogue: Catalogue!
    var owner: OwnerState!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        catalogue = try SeedLoader.loadCatalogue()
        owner = try SeedLoader.loadPinnedOwnerState()
    }

    private func card(_ id: String) -> CardProduct { catalogue.cards.first { $0.cardId == id }! }

    private func appliedRuleId(_ cardId: String, _ p: PurchaseContext) -> String? {
        if case .applied(let rule, _) = RuleMatcher.resolve(card: card(cardId), purchase: p,
                                                        ownerState: owner, asOf: asOf) {
            return rule.ruleId
        }
        return nil
    }

    func testGroceryMatchesCobalt5x() {
        let p = PurchaseContext(amountCad: 100, category: "grocery", mcc: 5411, merchantBrand: "loblaws")
        XCTAssertEqual(appliedRuleId("amex-cobalt", p), "cobalt-eats-5x")
    }

    func testCostcoMccBlocksMbnaGrocery() {
        let p = PurchaseContext(amountCad: 200, category: "wholesaleClub", mcc: 5300,
                                merchantBrand: "costco", acceptedNetworks: [.mastercard])
        XCTAssertEqual(appliedRuleId("mbna-rewards-we", p), "mbna-base",
                       "5300 is not a grocery MCC and category is wholesaleClub, so base rule applies")
    }

    func testCostcoBrandBlocksTriangleGroceryEvenAsMcc5411() {
        let p = PurchaseContext(amountCad: 200, category: "grocery", mcc: 5411, merchantBrand: "costco")
        XCTAssertEqual(appliedRuleId("triangle-we", p), "triangle-base",
                       "merchantExclude beats an otherwise-matching MCC")
    }

    func testRecurringIndicatorFiresMomentum4pct() {
        let p = PurchaseContext(amountCad: 15.49, category: "streaming", mcc: 5968,
                                merchantBrand: "netflix", channel: "online", recurringIndicator: true)
        XCTAssertEqual(appliedRuleId("scotia-momentum-vi-plus", p), "momentum-grocery-recurring-4pct")
    }

    func testUsdRuleFiresOnCurrency() {
        let p = PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")
        XCTAssertEqual(appliedRuleId("rogers-red-we", p), "rogers-usd-3pct")
    }

    func testRogersServiceRuleSkippedWhenUnresolved() {
        let p = PurchaseContext(amountCad: 100, category: "other")
        var o = owner!
        var s = o.cardStates["rogers-red-we"] ?? CardState()
        s.rogersEligibleServiceLinked = nil
        o.cardStates["rogers-red-we"] = s
        guard case .applied(let rule, _) = RuleMatcher.resolve(card: card("rogers-red-we"), purchase: p,
                                                            ownerState: o, asOf: asOf)
        else { return XCTFail("expected a rule to apply") }
        XCTAssertEqual(rule.ruleId, "rogers-base-1_5", "unresolved condition must not enable the 2% rule")
    }

    func testAmazonPrimeUnansweredFallsToNonPrimeRule() {
        let p = PurchaseContext(amountCad: 100, category: "other",
                                merchantBrand: "amazon-ca", channel: "online")
        XCTAssertEqual(appliedRuleId("amazon-ca-rewards-mastercard", p),
                       "amazon-ca-nonprime-1_5x",
                       "unanswered Prime must fail closed without suppressing the 1.5x fallback")
    }

    func testCryptoExcludedWhenPlanInactive() {
        let p = PurchaseContext(amountCad: 100, category: "other")
        guard case .cardExcluded = RuleMatcher.resolve(card: card("cryptocom-royal-indigo"),
                                                       purchase: p, ownerState: owner, asOf: asOf)
        else { return XCTFail("Level Up Pro inactive means the card is excluded, never guessed") }
    }

    func testTangerineTreatAsAllSelectedMatchesSentinel() {
        let p = PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912)
        XCTAssertEqual(appliedRuleId("tangerine-moneyback-world", p), "tangerine-selected-2pct")
    }

    func testTangerineUnresolvedSelectionsFallToBase() {
        let p = PurchaseContext(amountCad: 30, category: "drugStore", mcc: 5912)
        var o = owner!
        var s = o.cardStates["tangerine-moneyback-world"] ?? CardState()
        s.selectedCategories = nil
        o.cardStates["tangerine-moneyback-world"] = s
        guard case .applied(let rule, _) = RuleMatcher.resolve(card: card("tangerine-moneyback-world"),
                                                            purchase: p, ownerState: o, asOf: asOf)
        else { return XCTFail("expected a rule to apply") }
        XCTAssertEqual(rule.ruleId, "tangerine-base")
    }

    func testEveryTangerineSelectionMatchesItsPurchaseFacts() {
        let cases: [(TangerineMoneyBackCategory, PurchaseContext)] = [
            (.grocery, .init(amountCad: 30, category: "grocery", mcc: 5411)),
            (.dining, .init(amountCad: 30, category: "dining", mcc: 5812)),
            (.gasStation, .init(amountCad: 30, category: "gasStation", mcc: 5541)),
            (.entertainment, .init(amountCad: 30, category: "entertainment")),
            (.furniture, .init(amountCad: 30, category: "furniture")),
            (.lodging, .init(amountCad: 30, category: "lodging", mcc: 3501)),
            (.drugStore, .init(amountCad: 30, category: "drugStore", mcc: 5912)),
            (.recurring, .init(amountCad: 30, category: "insurance", recurringIndicator: true)),
            (.homeImprovement, .init(amountCad: 30, category: "homeImprovement")),
            (.transit, .init(amountCad: 30, category: "transit", mcc: 4121)),
            (.eGames, .init(amountCad: 30, category: "eGames")),
            (.fitness, .init(amountCad: 30, category: "fitness")),
            (.foreignCurrency, .init(amountCad: 30, currency: "USD", category: "other")),
        ]

        XCTAssertEqual(TangerineMoneyBackCategory.allCases.count, 13)
        for (selection, purchase) in cases {
            var state = owner.cardStates["tangerine-moneyback-world"] ?? CardState()
            state.selectedCategories = [selection.rawValue]
            state.treatAsAllSelected = false
            owner.cardStates["tangerine-moneyback-world"] = state

            XCTAssertEqual(appliedRuleId("tangerine-moneyback-world", purchase),
                           "tangerine-selected-2pct", selection.rawValue)
        }
    }

    func testTangerineSpecialSelectionsDoNotMatchUnrelatedPurchases() {
        var state = owner.cardStates["tangerine-moneyback-world"] ?? CardState()
        state.selectedCategories = [
            TangerineMoneyBackCategory.recurring.rawValue,
            TangerineMoneyBackCategory.foreignCurrency.rawValue,
        ]
        state.treatAsAllSelected = false
        owner.cardStates["tangerine-moneyback-world"] = state

        let ordinaryCadPurchase = PurchaseContext(amountCad: 30, category: "other")
        XCTAssertEqual(appliedRuleId("tangerine-moneyback-world", ordinaryCadPurchase),
                       "tangerine-base")
    }

    func testMarriottDirectInheritsLodging() {
        let p = PurchaseContext(amountCad: 300, category: "marriottDirect", mcc: 3509,
                                merchantBrand: "marriott")
        XCTAssertEqual(appliedRuleId("amex-platinum", p), "platinum-travel-2x",
                       "marriottDirect inherits lodging/travel via the category hierarchy")
        XCTAssertEqual(appliedRuleId("amex-bonvoy", p), "bonvoy-marriott-5x")
    }

    /// merchantInclude had zero coverage before this — the display-cased catalogue tokens that
    /// could never match (see CatalogueIntegrityTests.testMerchantBrandTokensAreLowercaseKebabCase)
    /// went unnoticed for exactly that reason. Exercises RuleMatcher.matches directly, since every
    /// merchantInclude rules were gated off live scoring when this regression was added; keeping
    /// the predicate-level pin makes token matching failures local instead of looking like an
    /// Amazon owner-condition regression.
    func testMerchantIncludeMatchesListedBrand() {
        var predicate = Predicate()
        predicate.merchantInclude = ["sobeys", "safeway"]
        let purchase = PurchaseContext(amountCad: 30, category: "grocery", merchantBrand: "sobeys")
        XCTAssertTrue(RuleMatcher.matches(predicate, purchase: purchase, state: CardState()))
    }

    func testMerchantIncludeRejectsBrandNotOnTheList() {
        var predicate = Predicate()
        predicate.merchantInclude = ["sobeys", "safeway"]
        let purchase = PurchaseContext(amountCad: 30, category: "grocery", merchantBrand: "costco")
        XCTAssertFalse(RuleMatcher.matches(predicate, purchase: purchase, state: CardState()))
    }

    /// The match is exact and case-sensitive (`include.contains(brand)`), so a catalogue token
    /// that disagrees in case with every brand producer can never fire. This is the behavior the
    /// display-cased tokens silently violated.
    func testMerchantIncludeIsCaseSensitive() {
        var predicate = Predicate()
        predicate.merchantInclude = ["sobeys"]
        let purchase = PurchaseContext(amountCad: 30, category: "grocery", merchantBrand: "Sobeys")
        XCTAssertFalse(RuleMatcher.matches(predicate, purchase: purchase, state: CardState()))
    }

    func testMerchantIncludeRejectsMissingMerchantBrand() {
        var predicate = Predicate()
        predicate.merchantInclude = ["sobeys"]
        let purchase = PurchaseContext(amountCad: 30, category: "grocery")
        XCTAssertFalse(RuleMatcher.matches(predicate, purchase: purchase, state: CardState()))
    }

    func testAnnouncedFutureFxRecordIgnoredBeforeEffectiveFrom() {
        let crypto = card("cryptocom-royal-indigo")
        let active = RuleMatcher.activeFxRule(for: crypto, asOf: "2026-08-20")
        XCTAssertNil(active?.freeAllowanceCadPerCalendarMonth, "pre-September record has no allowance")
        let september = RuleMatcher.activeFxRule(for: crypto, asOf: "2026-09-02")
        XCTAssertEqual(september?.freeAllowanceCadPerCalendarMonth, 1400)
    }
}
