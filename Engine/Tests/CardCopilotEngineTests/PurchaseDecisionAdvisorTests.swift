import XCTest
@testable import CardCopilotEngine

final class PurchaseDecisionAdvisorTests: XCTestCase {
    private func fixture(amountCad: Double) throws -> (Recommendation, PurchaseContext, OwnerState, BenefitsCatalogue) {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: owner)
        let purchase = PurchaseContext(amountCad: amountCad, category: "retailShopping")
        guard case .advised(let recommendation) = engine.recommend(purchase, asOf: "2026-09-04") else {
            throw NSError(domain: "PurchaseDecisionAdvisorTests", code: 1)
        }
        return (recommendation, purchase, owner, benefits)
    }

    func testSmallPurchaseStaysRewardOnly() throws {
        let (recommendation, purchase, owner, benefits) = try fixture(amountCad: 50)
        let result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation: recommendation,
            purchase: purchase,
            wallet: owner.ownedCardIds,
            benefits: benefits)

        XCTAssertEqual(result.verdict, .rewardLeader)
        XCTAssertEqual(result.policyVersion, "conservative-multi-attribute-v1")
    }

    func testMaterialPurchaseRequestsItemContextInsteadOfInferringFromMerchant() throws {
        let (recommendation, purchase, owner, benefits) = try fixture(amountCad: 500)
        let result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation: recommendation,
            purchase: purchase,
            wallet: owner.ownedCardIds,
            benefits: benefits)

        XCTAssertEqual(result.verdict, .purchaseContextNeeded)
        XCTAssertFalse(result.relevantKinds.isEmpty)
    }

    func testDeclaredElectronicsContextProducesProtectionDecision() throws {
        let (recommendation, purchase, owner, benefits) = try fixture(amountCad: 500)
        let result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation: recommendation,
            purchase: purchase,
            wallet: owner.ownedCardIds,
            benefits: benefits,
            declaredContext: BenefitContext(kind: .electronics))

        XCTAssertNotEqual(result.verdict, .purchaseContextNeeded)
        XCTAssertTrue(result.relevantKinds.contains(.purchaseProtection))
        XCTAssertTrue(result.relevantKinds.contains(.extendedWarranty))
    }

    func testDeclaredOtherContextMeansKnownNoModelledProtectionContext() throws {
        let (recommendation, purchase, owner, benefits) = try fixture(amountCad: 500)
        let context = BenefitContext(kind: .other)

        XCTAssertTrue(context.relevantKinds.isEmpty)

        let result = PurchaseDecisionAdvisor.assess(
            rewardRecommendation: recommendation,
            purchase: purchase,
            wallet: owner.ownedCardIds,
            benefits: benefits,
            declaredContext: context)

        XCTAssertEqual(result.verdict, .rewardLeader)
        XCTAssertTrue(result.relevantKinds.isEmpty)
    }
}
