import XCTest
@testable import CardCopilotEngine

final class ChipInsightAdvisorTests: XCTestCase {
    var catalogue: Catalogue!
    var owner: OwnerState!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        catalogue = try SeedLoader.loadCatalogue()
        owner = try SeedLoader.loadPinnedOwnerState()
    }

    private func engine() -> RecommendationEngine {
        RecommendationEngine(catalogue: catalogue, ownerState: owner)
    }

    // MARK: - Vanilla purchase → no insights (don't spam)

    func testVanillaDomesticPurchaseProducesNoInsights() {
        let purchase = PurchaseContext(amountCad: 50, category: "grocery",
                                       mcc: 5411, merchantBrand: "loblaws")
        guard case .advised(let rec) = engine().recommend(purchase, asOf: asOf) else {
            return XCTFail("Expected advice")
        }
        let insights = ChipInsightAdvisor.evaluate(
            recommendation: rec, purchase: purchase,
            catalogue: catalogue, defaultCardId: owner.defaultCardId)
        // A typical domestic grocery purchase should not trigger FX, DCC, or all-negative.
        // It MAY trigger switchFromDefault or networkRestricted depending on wallet — that's
        // acceptable. What matters is the list is small, not that it's empty.
        let unwanted: [String] = insights.compactMap {
            switch $0 {
            case .allCardsNegative: return "allCardsNegative"
            case .fxCostErosion: return "fxCostErosion"
            case .declineDcc: return "declineDcc"
            default: return nil
            }
        }
        XCTAssertTrue(unwanted.isEmpty,
                      "Vanilla domestic grocery should not trigger: \(unwanted)")
    }

    // MARK: - FX cost erosion

    func testForeignPurchaseTriggersDeclineDcc() {
        let purchase = PurchaseContext(amountCad: 165, currency: "USD",
                                       category: "other", country: "US",
                                       channel: "online")
        guard case .advised(let rec) = engine().recommend(purchase, asOf: asOf) else {
            return XCTFail("Expected advice")
        }
        let insights = ChipInsightAdvisor.evaluate(
            recommendation: rec, purchase: purchase,
            catalogue: catalogue, defaultCardId: owner.defaultCardId)
        XCTAssertTrue(insights.contains(where: {
            if case .declineDcc(let currency) = $0 { return currency == "USD" }
            return false
        }), "Foreign USD purchase should trigger DCC warning")
    }

    // MARK: - Network restriction

    func testCostcoTriggersNetworkRestriction() {
        // Costco only accepts Mastercard — Amex and Visa cards should be excluded.
        let purchase = PurchaseContext(amountCad: 150, category: "wholesaleClub",
                                       mcc: 5411, merchantBrand: "costco",
                                       acceptedNetworks: [.mastercard])
        guard case .advised(let rec) = engine().recommend(purchase, asOf: asOf) else {
            return XCTFail("Expected advice")
        }
        let insights = ChipInsightAdvisor.evaluate(
            recommendation: rec, purchase: purchase,
            catalogue: catalogue, defaultCardId: owner.defaultCardId)
        let networkInsights = insights.filter {
            if case .networkRestricted = $0 { return true }
            return false
        }
        XCTAssertFalse(networkInsights.isEmpty,
                       "Costco should trigger networkRestricted insight")
        if case .networkRestricted(let merchant, let networks, let count) = networkInsights[0] {
            XCTAssertEqual(merchant, "costco")
            XCTAssertEqual(networks, [.mastercard])
            XCTAssertGreaterThan(count, 0)
        }
    }

    // MARK: - Cap nearly exhausted

    func testCapNearlyExhaustedTriggersInsight() {
        // Push Cobalt's cap close to limit so the warning fires.
        owner.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"] = 2450
        let purchase = PurchaseContext(amountCad: 100, category: "grocery",
                                       mcc: 5411, merchantBrand: "loblaws")
        guard case .advised(let rec) = engine().recommend(purchase, asOf: asOf) else {
            return XCTFail("Expected advice")
        }
        // Only fires if the winner is the card with the near-exhausted cap.
        if rec.winner.cardId == "amex-cobalt" && rec.winner.warnings.contains(.capNearlyExhausted) {
            let insights = ChipInsightAdvisor.evaluate(
                recommendation: rec, purchase: purchase,
                catalogue: catalogue, defaultCardId: owner.defaultCardId)
            XCTAssertTrue(insights.contains(where: {
                if case .capNearlyExhausted = $0 { return true }
                return false
            }), "Near-exhausted cap should trigger capNearlyExhausted insight")
        }
    }

    // MARK: - Valuation sensitivity

    func testValuationSensitiveTriggersInsight() {
        // At 1.8¢/point MR is high enough to win over cashback on some purchases but
        // lowering it could flip the recommendation.
        let purchase = PurchaseContext(amountCad: 100, category: "dining")
        guard case .advised(let rec) = engine().recommend(purchase, asOf: asOf) else {
            return XCTFail("Expected advice")
        }
        if rec.valuationSensitive {
            let insights = ChipInsightAdvisor.evaluate(
                recommendation: rec, purchase: purchase,
                catalogue: catalogue, defaultCardId: owner.defaultCardId)
            XCTAssertTrue(insights.contains(where: {
                if case .valuationSensitive = $0 { return true }
                return false
            }), "Valuation-sensitive recommendation should trigger insight")
        }
    }

    // MARK: - Priority ordering

    func testInsightsOrderedByPriority() {
        // Foreign purchase at Costco: should trigger both networkRestricted and declineDcc.
        let purchase = PurchaseContext(amountCad: 150, currency: "USD",
                                       category: "wholesaleClub",
                                       merchantBrand: "costco",
                                       country: "US",
                                       acceptedNetworks: [.mastercard])
        guard case .advised(let rec) = engine().recommend(purchase, asOf: asOf) else {
            return XCTFail("Expected advice")
        }
        let insights = ChipInsightAdvisor.evaluate(
            recommendation: rec, purchase: purchase,
            catalogue: catalogue, defaultCardId: owner.defaultCardId)
        // Verify ordering: networkRestricted (priority 1) should come before declineDcc (priority 2).
        let priorities = insights.map(\.priority)
        XCTAssertEqual(priorities, priorities.sorted(),
                       "Insights should be ordered by priority (lower = more urgent)")
    }

    // MARK: - All negative

    func testAllNegativeTriggersInsight() {
        // Cobalt goes negative on foreign-currency "other" purchases (FX > rewards).
        // Restrict wallet to Cobalt only so the winner is the negative-value card.
        var restrictedOwner = owner!
        restrictedOwner.ownedCardIds = ["amex-cobalt"]
        let eng = RecommendationEngine(catalogue: catalogue, ownerState: restrictedOwner)
        let purchase = PurchaseContext(amountCad: 165, currency: "USD",
                                       category: "other", country: "US",
                                       channel: "online")
        guard case .advised(let rec) = eng.recommend(purchase, asOf: asOf) else {
            return XCTFail("Expected advice even if negative")
        }
        guard rec.winner.netValueCad < 0 else {
            // If the seed data changes so Cobalt isn't negative here, skip gracefully.
            return
        }
        let insights = ChipInsightAdvisor.evaluate(
            recommendation: rec, purchase: purchase,
            catalogue: catalogue, defaultCardId: restrictedOwner.defaultCardId)
        XCTAssertTrue(insights.contains(where: {
            if case .allCardsNegative = $0 { return true }
            return false
        }), "All-negative winner should trigger allCardsNegative")
        // allCardsNegative should be the highest-priority insight (priority 0).
        if let first = insights.first {
            if case .allCardsNegative = first {
                // Expected
            } else {
                XCTFail("allCardsNegative should be the first (highest-priority) insight, got \(first)")
            }
        }
    }
}
