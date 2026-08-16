import XCTest
@testable import CardCopilotEngine

final class BenefitsAdvisorDisclosureTests: XCTestCase {

    // MARK: - Fixture builders (in-code, no JSON)

    private func benefit(_ id: String, family: String, kind: String,
                         configure: (inout BenefitCoverage) -> Void = { _ in }) -> Benefit {
        var coverage = BenefitCoverage()
        configure(&coverage)
        return Benefit(benefitId: id, family: family, kind: kind, coverage: coverage,
                       conditions: ["Full purchase charged to the card"],
                       exclusions: nil, certificateQuote: nil, notes: nil)
    }

    private func card(_ cardId: String, status: BenefitVerification = .stub,
                      benefits: [Benefit]) -> CardBenefits {
        CardBenefits(cardId: cardId,
                     certificate: CertificateProvenance(underwriter: nil, sourceUrl: nil,
                                                        certificateDate: nil, lastVerifiedAt: nil,
                                                        verificationStatus: status),
                     benefits: benefits)
    }

    private func catalogue(_ cards: [CardBenefits],
                           threshold: Double = 150,
                           consumables: [String] = ["dining", "grocery", "gasStation"]) -> BenefitsCatalogue {
        BenefitsCatalogue(benefitsCatalogueVersion: "test",
                          triggers: BenefitsTriggers(bigTicketThresholdCad: threshold,
                                                     consumableCategories: consumables),
                          cards: cards)
    }

    private var shoppingPair: [Benefit] {
        [benefit("a-pp", family: "shopping", kind: "purchaseProtection") { $0.windowDays = 90 },
         benefit("a-ew", family: "shopping", kind: "extendedWarranty") { $0.extraYears = 1 }]
    }

    private func purchase(amount: Double, category: String,
                          country: String = "CA", currency: String = "CAD") -> PurchaseContext {
        PurchaseContext(amountCad: amount, currency: currency, category: category, country: country)
    }

    // MARK: - Big-ticket shopping trigger

    func testBigTicketTriggersShoppingDisclosuresForRecommendedCard() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertEqual(result.recommended.map(\.kind).sorted(),
                       ["extendedWarranty", "purchaseProtection"])
        XCTAssertEqual(result.recommended.first?.verification, .stub)
    }

    func testExactlyAtThresholdTriggers() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 150, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertFalse(result.recommended.isEmpty)
    }

    func testBelowThresholdStaysQuiet() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 149.99, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
        XCTAssertTrue(result.nudges.isEmpty)
    }

    func testConsumableCategoryNeverTriggersShopping() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "grocery"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
    }

    // MARK: - Travel triggers

    func testHotelCategoryTriggersTravelKinds() {
        let travel = [benefit("a-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 },
                      benefit("a-tm", family: "travelMedical", kind: "travelMedical") { $0.maxCad = 1_000_000 }]
        let cat = catalogue([card("winner", benefits: travel + shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 80, category: "hotel"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        // Amount is under the big-ticket threshold: travel families only, no shopping kinds.
        XCTAssertEqual(result.recommended.map(\.kind).sorted(), ["flightDelay", "travelMedical"])
    }

    func testForeignCountryTriggersTravelKinds() {
        let travel = [benefit("a-tm", family: "travelMedical", kind: "travelMedical") { $0.maxCad = 1_000_000 }]
        let cat = catalogue([card("winner", benefits: travel)])
        let result = BenefitsAdvisor.disclosures(
            purchase: purchase(amount: 40, category: "dining", country: "US"),
            recommendedCardId: "winner", wallet: ["winner"], catalogue: cat)
        XCTAssertEqual(result.recommended.map(\.kind), ["travelMedical"])
    }

    func testForeignCurrencyTriggersTravelKinds() {
        let travel = [benefit("a-tm", family: "travelMedical", kind: "travelMedical") { $0.maxCad = 1_000_000 }]
        let cat = catalogue([card("winner", benefits: travel)])
        let result = BenefitsAdvisor.disclosures(
            purchase: purchase(amount: 40, category: "dining", currency: "USD"),
            recommendedCardId: "winner", wallet: ["winner"], catalogue: cat)
        XCTAssertEqual(result.recommended.map(\.kind), ["travelMedical"])
    }

    // MARK: - Cross-card nudges

    func testNudgeWhenAnotherCardHasAKindTheWinnerLacks() {
        let other = card("other", benefits: [
            benefit("o-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 1000 }])
        let cat = catalogue([card("winner", benefits: shoppingPair), other])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "other"], catalogue: cat)
        XCTAssertEqual(result.nudges, [CrossCardNudge(cardId: "other", kind: "mobileDeviceInsurance")])
    }

    func testNoNudgeForKindsTheWinnerAlreadyHas() {
        let other = card("other", benefits: shoppingPair.map {
            var b = $0; b.benefitId = "other-" + b.benefitId; return b
        })
        let cat = catalogue([card("winner", benefits: shoppingPair), other])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "other"], catalogue: cat)
        XCTAssertTrue(result.nudges.isEmpty)
    }

    func testNudgesDedupeByKindInWalletOrder() {
        let second = card("second", benefits: [
            benefit("s-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 800 }])
        let third = card("third", benefits: [
            benefit("t-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 1000 }])
        let cat = catalogue([card("winner", benefits: shoppingPair), second, third])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "second", "third"], catalogue: cat)
        XCTAssertEqual(result.nudges, [CrossCardNudge(cardId: "second", kind: "mobileDeviceInsurance")])
    }

    func testNoTriggerMeansNoNudges() {
        let other = card("other", benefits: [
            benefit("o-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 1000 }])
        let cat = catalogue([card("winner", benefits: []), other])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 20, category: "dining"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "other"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
        XCTAssertTrue(result.nudges.isEmpty)
    }

    func testUnknownKindsAreIgnored() {
        let weird = [benefit("w-x", family: "shopping", kind: "cellPlanInsurance")]
        let cat = catalogue([card("winner", benefits: weird)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
    }
}
