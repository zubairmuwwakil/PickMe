package com.cardcopilot.engine

import com.cardcopilot.engine.engine.AcquisitionAnalyzer
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.ApplicantIncomeProfile
import com.cardcopilot.engine.models.ApplicationRequirementEvaluator
import com.cardcopilot.engine.models.IncomeRequirementAssessmentStatus
import com.cardcopilot.engine.models.IncomeRequirementType
import com.cardcopilot.engine.models.Money
import com.cardcopilot.engine.models.Currency
import com.cardcopilot.engine.models.SpendDistribution
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private const val AS_OF = "2026-08-31"

@Serializable
private data class ApplicationRequirementFixtureFile(
    val cases: List<ApplicationRequirementFixtureCase>
)

@Serializable
private data class ApplicationRequirementFixtureCase(
    val caseId: String,
    val cardId: String,
    val profile: ApplicantIncomeProfile,
    val expectedStatus: IncomeRequirementAssessmentStatus,
    val expectedMatchedType: IncomeRequirementType? = null,
    val expectedClosestType: IncomeRequirementType? = null,
    val expectedShortfall: Double? = null,
    val expectedMissingTypes: List<IncomeRequirementType>? = null
)

class ApplicationRequirementTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `shared income requirement fixtures conform`() {
        val requirements = SeedLoader.loadApplicationRequirements()
        val stream = requireNotNull(javaClass.getResourceAsStream(
            "/com/cardcopilot/engine/application-requirements-fixtures.json"
        ))
        val fixtures = stream.bufferedReader().use { json.decodeFromString<ApplicationRequirementFixtureFile>(it.readText()) }

        for (fixture in fixtures.cases) {
            val assessment = ApplicationRequirementEvaluator.assess(
                requirements.requirement(fixture.cardId), fixture.profile
            )
            assertEquals(fixture.expectedStatus, assessment.status, fixture.caseId)
            assertEquals(fixture.expectedMatchedType, assessment.matchedType, fixture.caseId)
            assertEquals(fixture.expectedClosestType, assessment.closestType, fixture.caseId)
            assertEquals(fixture.expectedMissingTypes ?: emptyList<IncomeRequirementType>(), assessment.missingTypes, fixture.caseId)
            fixture.expectedShortfall?.let { expected ->
                assertEquals(expected, requireNotNull(assessment.closestPath?.shortfall?.amount), 0.001, fixture.caseId)
            }
        }
    }

    @Test
    fun `every candidate has one sourced application requirement`() {
        val candidates = SeedLoader.loadCandidateCatalogue().cardIds
        val requirements = SeedLoader.loadApplicationRequirements()

        assertEquals(candidates.toSet(), requirements.requirements.map { it.cardId }.toSet())
        assertEquals(candidates.size, requirements.requirements.size)
        assertTrue(requirements.requirements.all { it.sources.isNotEmpty() })
    }

    @Test
    fun `income screening groups candidates without changing acquisition economics`() {
        val catalogue = SeedLoader.loadCatalogue()
        val candidates = SeedLoader.loadCandidateCatalogue()
        val owner = SeedLoader.loadOwnerState()
        val requirements = SeedLoader.loadApplicationRequirements()
        val profile = ApplicantIncomeProfile(individualAnnualIncome = Money(10_000.0, Currency.CAD))
        val baseline = AcquisitionAnalyzer(catalogue, candidates, owner)
            .analyze(SpendDistribution.placeholderCanadianHousehold, AS_OF)
        val screened = AcquisitionAnalyzer(catalogue, candidates, owner, requirements, profile)
            .analyze(SpendDistribution.placeholderCanadianHousehold, AS_OF)

        assertEquals(baseline.candidates.map { it.netAnnualValueCad }, screened.candidates.map { it.netAnnualValueCad })
        assertNotNull(screened.incomeReadyCandidates.firstOrNull { it.cardId == "amex-simplycash-preferred" })
        assertNotNull(screened.incomeInformationNeeded.firstOrNull { it.cardId == "bmo-cashback-world-elite" })
        assertNotNull(screened.incomeCloseMatches.firstOrNull { it.cardId == "home-trust-preferred-visa" })
    }
}
