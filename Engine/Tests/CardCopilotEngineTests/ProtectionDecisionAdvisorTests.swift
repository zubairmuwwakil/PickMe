import XCTest
@testable import CardCopilotEngine

final class ProtectionDecisionAdvisorTests: XCTestCase {
    private func catalogue(verification: BenefitVerification = .issuerPage) -> BenefitsCatalogue {
        let purchase = Benefit(
            benefitId: "test-purchase",
            family: BenefitFamily.shopping.rawValue,
            kind: BenefitKind.purchaseProtection.rawValue,
            coverage: BenefitCoverage(),
            conditions: ["Eligible purchase must be charged to the card."],
            exclusions: nil,
            certificateQuote: nil,
            notes: nil)
        let warranty = Benefit(
            benefitId: "test-warranty",
            family: BenefitFamily.shopping.rawValue,
            kind: BenefitKind.extendedWarranty.rawValue,
            coverage: BenefitCoverage(),
            conditions: ["Eligible purchase must be charged to the card."],
            exclusions: nil,
            certificateQuote: nil,
            notes: nil)
        let card = CardBenefits(
            cardId: "direct-card",
            certificate: CertificateProvenance(
                underwriter: "Test Underwriter",
                sourceUrl: "https://example.invalid/certificate",
                certificateDate: "2026-01",
                lastVerifiedAt: "2026-09-04",
                verificationStatus: verification),
            benefits: [purchase, warranty])
        return BenefitsCatalogue(
            benefitsCatalogueVersion: "test",
            triggers: BenefitsTriggers(
                bigTicketThresholdCad: 150,
                consumableCategories: ["drugStore", "grocery", "dining"]),
            cards: [card])
    }

    func testDurableBigTicketPurchaseCreatesProtectionTradeoff() {
        let assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId: "direct-card",
            purchase: PurchaseContext(amountCad: 500, category: "retailShopping"),
            benefits: catalogue())

        XCTAssertEqual(assessment.status, .potentialTradeoff)
        XCTAssertEqual(assessment.relevantKinds, [.purchaseProtection, .extendedWarranty])
        XCTAssertEqual(assessment.verification, .issuerPage)
    }

    func testConsumableMerchantCategoryRequestsPurchaseContextInsteadOfGuessing() {
        let assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId: "direct-card",
            purchase: PurchaseContext(amountCad: 500, category: "drugStore"),
            benefits: catalogue())

        XCTAssertEqual(assessment.status, .purchaseContextNeeded)
        XCTAssertEqual(assessment.relevantKinds, [.purchaseProtection, .extendedWarranty])
    }

    func testDeclaredElectronicsContextResolvesAmbiguityToTradeoff() {
        let assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId: "direct-card",
            purchase: PurchaseContext(amountCad: 500, category: "drugStore"),
            benefits: catalogue(),
            declaredContext: BenefitContext(kind: .electronics))

        XCTAssertEqual(assessment.status, .potentialTradeoff)
        XCTAssertEqual(assessment.relevantKinds, [.purchaseProtection, .extendedWarranty])
    }

    func testStubBenefitFactsNeverInfluenceDecision() {
        let assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId: "direct-card",
            purchase: PurchaseContext(amountCad: 500, category: "retailShopping"),
            benefits: catalogue(verification: .stub))

        XCTAssertEqual(assessment.status, .notRelevant)
        XCTAssertTrue(assessment.relevantKinds.isEmpty)
    }

    func testSmallPurchaseDoesNotCreateProtectionTradeoff() {
        let assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId: "direct-card",
            purchase: PurchaseContext(amountCad: 50, category: "retailShopping"),
            benefits: catalogue())

        XCTAssertEqual(assessment.status, .notRelevant)
    }
}
