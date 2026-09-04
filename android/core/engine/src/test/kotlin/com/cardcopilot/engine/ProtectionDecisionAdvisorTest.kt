package com.cardcopilot.engine

import com.cardcopilot.engine.engine.BenefitContext
import com.cardcopilot.engine.engine.BenefitContextKind
import com.cardcopilot.engine.engine.ProtectionDecisionAdvisor
import com.cardcopilot.engine.engine.ProtectionDecisionStatus
import com.cardcopilot.engine.models.Benefit
import com.cardcopilot.engine.models.BenefitCoverage
import com.cardcopilot.engine.models.BenefitFamily
import com.cardcopilot.engine.models.BenefitKind
import com.cardcopilot.engine.models.BenefitVerification
import com.cardcopilot.engine.models.BenefitsCatalogue
import com.cardcopilot.engine.models.BenefitsTriggers
import com.cardcopilot.engine.models.CardBenefits
import com.cardcopilot.engine.models.CertificateProvenance
import com.cardcopilot.engine.models.PurchaseContext
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ProtectionDecisionAdvisorTest {
    private fun catalogue(verification: BenefitVerification = BenefitVerification.ISSUER_PAGE): BenefitsCatalogue {
        val purchase = Benefit(
            benefitId = "test-purchase",
            family = BenefitFamily.SHOPPING.rawValue,
            kind = BenefitKind.PURCHASE_PROTECTION.rawValue,
            coverage = BenefitCoverage(),
            conditions = listOf("Eligible purchase must be charged to the card.")
        )
        val warranty = Benefit(
            benefitId = "test-warranty",
            family = BenefitFamily.SHOPPING.rawValue,
            kind = BenefitKind.EXTENDED_WARRANTY.rawValue,
            coverage = BenefitCoverage(),
            conditions = listOf("Eligible purchase must be charged to the card.")
        )
        return BenefitsCatalogue(
            benefitsCatalogueVersion = "test",
            triggers = BenefitsTriggers(
                bigTicketThresholdCad = 150.0,
                consumableCategories = listOf("drugStore", "grocery", "dining")
            ),
            cards = listOf(
                CardBenefits(
                    cardId = "direct-card",
                    certificate = CertificateProvenance(
                        underwriter = "Test Underwriter",
                        sourceUrl = "https://example.invalid/certificate",
                        certificateDate = "2026-01",
                        lastVerifiedAt = "2026-09-04",
                        verificationStatus = verification
                    ),
                    benefits = listOf(purchase, warranty)
                )
            )
        )
    }

    @Test
    fun `durable big ticket purchase creates protection tradeoff`() {
        val assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId = "direct-card",
            purchase = PurchaseContext(amountCad = 500.0, category = "retailShopping"),
            benefits = catalogue()
        )

        assertEquals(ProtectionDecisionStatus.POTENTIAL_TRADEOFF, assessment.status)
        assertEquals(
            listOf(BenefitKind.PURCHASE_PROTECTION, BenefitKind.EXTENDED_WARRANTY),
            assessment.relevantKinds
        )
        assertEquals(BenefitVerification.ISSUER_PAGE, assessment.verification)
    }

    @Test
    fun `consumable merchant category requests purchase context instead of guessing`() {
        val assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId = "direct-card",
            purchase = PurchaseContext(amountCad = 500.0, category = "drugStore"),
            benefits = catalogue()
        )

        assertEquals(ProtectionDecisionStatus.PURCHASE_CONTEXT_NEEDED, assessment.status)
        assertEquals(
            listOf(BenefitKind.PURCHASE_PROTECTION, BenefitKind.EXTENDED_WARRANTY),
            assessment.relevantKinds
        )
    }

    @Test
    fun `declared electronics context resolves ambiguity to tradeoff`() {
        val assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId = "direct-card",
            purchase = PurchaseContext(amountCad = 500.0, category = "drugStore"),
            benefits = catalogue(),
            declaredContext = BenefitContext(BenefitContextKind.ELECTRONICS)
        )

        assertEquals(ProtectionDecisionStatus.POTENTIAL_TRADEOFF, assessment.status)
        assertEquals(
            listOf(BenefitKind.PURCHASE_PROTECTION, BenefitKind.EXTENDED_WARRANTY),
            assessment.relevantKinds
        )
    }

    @Test
    fun `stub benefit facts never influence decision`() {
        val assessment = ProtectionDecisionAdvisor.alternateFundingAssessment(
            directCardId = "direct-card",
            purchase = PurchaseContext(amountCad = 500.0, category = "retailShopping"),
            benefits = catalogue(BenefitVerification.STUB)
        )

        assertEquals(ProtectionDecisionStatus.NOT_RELEVANT, assessment.status)
        assertTrue(assessment.relevantKinds.isEmpty())
    }
}
