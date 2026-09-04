import XCTest
@testable import CardCopilotEngine

final class PurchaseRouteAdvisorTests: XCTestCase {
    private func fixture() throws -> (Catalogue, OwnerState, RecommendationEngine) {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        // Route acquisition should not accidentally inherit merchant-specific checkout credits
        // from a generic grocery-store template.
        let engine = RecommendationEngine(catalogue: catalogue,
                                          ownerState: owner,
                                          includeCheckoutCredits: false)
        return (catalogue, owner, engine)
    }

    func testShoppersRouteCanBeatDirectPayment() throws {
        let (_, _, engine) = try fixture()
        let directContext = PurchaseContext(amountCad: 100,
                                            category: "drugStore",
                                            mcc: 5912,
                                            merchantBrand: "shoppers-drug-mart")
        guard case .advised(let direct) = engine.recommend(directContext, asOf: "2026-09-04") else {
            return XCTFail("fixture wallet should produce direct advice")
        }

        let result = PurchaseRouteAdvisor.bestAlternative(
            directRecommendation: direct,
            destination: directContext,
            destinationMerchantName: "Shoppers Drug Mart",
            engine: engine,
            asOf: "2026-09-04"
        )

        let route = try XCTUnwrap(result)
        XCTAssertEqual(route.route.routeId, "shoppers-gift-card-via-grocery-5411")
        XCTAssertGreaterThanOrEqual(route.advantageCad, 1)
        XCTAssertGreaterThanOrEqual(route.advantagePercentagePoints, 1)
        XCTAssertEqual(route.route.evidenceLevel, .communityObserved)
    }

    func testMaterialGiftCardRouteKeepsRewardGainSeparateFromProtectionTradeoff() throws {
        let (_, _, engine) = try fixture()
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        let directContext = PurchaseContext(amountCad: 500,
                                            category: "drugStore",
                                            mcc: 5912,
                                            merchantBrand: "shoppers-drug-mart")
        guard case .advised(let direct) = engine.recommend(directContext, asOf: "2026-09-04") else {
            return XCTFail("fixture wallet should produce direct advice")
        }

        let result = try XCTUnwrap(PurchaseRouteAdvisor.bestAlternative(
            directRecommendation: direct,
            destination: directContext,
            destinationMerchantName: "Shoppers Drug Mart",
            engine: engine,
            asOf: "2026-09-04",
            benefits: benefits
        ))

        XCTAssertGreaterThan(result.advantageCad, 0)
        XCTAssertEqual(result.verdict, .rewardProtectionTradeoff)
        XCTAssertNotEqual(result.protectionAssessment.status, .notRelevant)
        // Protection changes the verdict, not the measured reward advantage.
        XCTAssertEqual(result.routeValueCad - result.directValueCad,
                       result.advantageCad,
                       accuracy: 0.000_001)
    }

    func testSmallPurchaseIsSuppressedByFrictionThreshold() throws {
        let (_, _, engine) = try fixture()
        let directContext = PurchaseContext(amountCad: 5,
                                            category: "drugStore",
                                            mcc: 5912,
                                            merchantBrand: "shoppers-drug-mart")
        guard case .advised(let direct) = engine.recommend(directContext, asOf: "2026-09-04") else {
            return XCTFail("fixture wallet should produce direct advice")
        }

        XCTAssertNil(PurchaseRouteAdvisor.bestAlternative(
            directRecommendation: direct,
            destination: directContext,
            destinationMerchantName: "Shoppers Drug Mart",
            engine: engine,
            asOf: "2026-09-04"
        ))
    }

    func testRouteDoesNotLeakToOtherDrugstores() throws {
        let (_, _, engine) = try fixture()
        let directContext = PurchaseContext(amountCad: 100,
                                            category: "drugStore",
                                            mcc: 5912,
                                            merchantBrand: "rexall")
        guard case .advised(let direct) = engine.recommend(directContext, asOf: "2026-09-04") else {
            return XCTFail("fixture wallet should produce direct advice")
        }

        XCTAssertNil(PurchaseRouteAdvisor.bestAlternative(
            directRecommendation: direct,
            destination: directContext,
            destinationMerchantName: "Rexall",
            engine: engine,
            asOf: "2026-09-04"
        ))
    }

    func testMerchantMatchingIsCaseAndPunctuationInsensitive() {
        let route = PurchaseRouteCatalogue.canadaV1[0]
        XCTAssertTrue(route.matches(destinationMerchantName: "SHOPPERS DRUG MART #1234"))
        XCTAssertTrue(route.matches(destinationMerchantName: "Pharmaprix - Montréal"))
        XCTAssertFalse(route.matches(destinationMerchantName: "Rexall Pharmacy"))
    }
}
