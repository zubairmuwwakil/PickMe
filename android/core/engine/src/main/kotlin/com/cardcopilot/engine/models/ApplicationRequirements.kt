package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class ApplicationRequirementCoverage {
    @SerialName("completePublishedSet") COMPLETE_PUBLISHED_SET,
    @SerialName("partialPublishedSet") PARTIAL_PUBLISHED_SET
}

@Serializable
enum class FinancialRequirementPublicationStatus {
    @SerialName("published") PUBLISHED,
    @SerialName("noIssuerPublishedMinimumFound") NO_ISSUER_PUBLISHED_MINIMUM_FOUND
}

@Serializable
enum class RequirementSemantics {
    @SerialName("any") ANY,
    @SerialName("unknown") UNKNOWN
}

@Serializable
enum class IncomeRequirementType(val rawValue: String) {
    @SerialName("individualAnnualIncome") INDIVIDUAL_ANNUAL_INCOME("individualAnnualIncome"),
    @SerialName("householdAnnualIncome") HOUSEHOLD_ANNUAL_INCOME("householdAnnualIncome")
}

@Serializable
enum class IncomeRequirementOperator {
    @SerialName("atLeast") AT_LEAST,
    @SerialName("greaterThan") GREATER_THAN
}

@Serializable
data class IncomeRequirementOption(
    val type: IncomeRequirementType,
    val operator: IncomeRequirementOperator,
    val amount: Money
)

@Serializable
data class FinancialApplicationRequirements(
    val publicationStatus: FinancialRequirementPublicationStatus,
    val semantics: RequirementSemantics,
    val options: List<IncomeRequirementOption>
)

@Serializable
enum class ApplicationRequirementSourceScope {
    @SerialName("cardSpecific") CARD_SPECIFIC,
    @SerialName("cardSpecificApplication") CARD_SPECIFIC_APPLICATION
}

@Serializable
data class ApplicationRequirementSource(
    val url: String,
    val scope: ApplicationRequirementSourceScope,
    val verifiedAt: String
)

@Serializable
data class CardApplicationRequirements(
    val cardId: String,
    val coverage: ApplicationRequirementCoverage,
    val financialRequirements: FinancialApplicationRequirements,
    val sources: List<ApplicationRequirementSource>
)

@Serializable
data class ApplicationRequirementCatalogue(
    val applicationRequirementsVersion: String,
    val verifiedAt: String,
    val requirements: List<CardApplicationRequirements>
) {
    fun requirement(cardId: String): CardApplicationRequirements? =
        requirements.firstOrNull { it.cardId == cardId }
}

/** Owner-entered income facts stay separate from synced wallet state. */
@Serializable
data class ApplicantIncomeProfile(
    val individualAnnualIncome: Money? = null,
    val householdAnnualIncome: Money? = null
) {
    fun value(type: IncomeRequirementType): Money? = when (type) {
        IncomeRequirementType.INDIVIDUAL_ANNUAL_INCOME -> individualAnnualIncome
        IncomeRequirementType.HOUSEHOLD_ANNUAL_INCOME -> householdAnnualIncome
    }
}

@Serializable
enum class IncomeRequirementAssessmentStatus {
    @SerialName("meetsPublishedMinimum") MEETS_PUBLISHED_MINIMUM,
    @SerialName("belowPublishedMinimum") BELOW_PUBLISHED_MINIMUM,
    @SerialName("needsMoreInformation") NEEDS_MORE_INFORMATION,
    @SerialName("noIssuerPublishedMinimumFound") NO_ISSUER_PUBLISHED_MINIMUM_FOUND,
    @SerialName("requirementsUnavailable") REQUIREMENTS_UNAVAILABLE
}

@Serializable
enum class IncomePathAssessmentStatus {
    @SerialName("met") MET,
    @SerialName("belowMinimum") BELOW_MINIMUM,
    @SerialName("missingOwnerInput") MISSING_OWNER_INPUT,
    @SerialName("currencyMismatch") CURRENCY_MISMATCH
}

@Serializable
data class IncomePathAssessment(
    val requirement: IncomeRequirementOption,
    val reportedAmount: Money?,
    val status: IncomePathAssessmentStatus,
    val shortfall: Money?,
    val shortfallPercentage: Double?
)

@Serializable
data class IncomeRequirementAssessment(
    val status: IncomeRequirementAssessmentStatus,
    val coverage: ApplicationRequirementCoverage?,
    val paths: List<IncomePathAssessment>,
    val matchedType: IncomeRequirementType?,
    val closestType: IncomeRequirementType?,
    val missingTypes: List<IncomeRequirementType>
) {
    val closestPath: IncomePathAssessment?
        get() = closestType?.let { type -> paths.firstOrNull { it.requirement.type == type } }

    /** This only reports whether a published minimum was met; it never predicts approval. */
    val isIncomeReady: Boolean
        get() = status == IncomeRequirementAssessmentStatus.MEETS_PUBLISHED_MINIMUM ||
            status == IncomeRequirementAssessmentStatus.NO_ISSUER_PUBLISHED_MINIMUM_FOUND

    companion object {
        val unavailable = IncomeRequirementAssessment(
            status = IncomeRequirementAssessmentStatus.REQUIREMENTS_UNAVAILABLE,
            coverage = null,
            paths = emptyList(),
            matchedType = null,
            closestType = null,
            missingTypes = emptyList()
        )
    }
}

object ApplicationRequirementEvaluator {
    fun assess(
        requirements: CardApplicationRequirements?,
        profile: ApplicantIncomeProfile
    ): IncomeRequirementAssessment {
        requirements ?: return IncomeRequirementAssessment.unavailable
        val financial = requirements.financialRequirements
        if (financial.publicationStatus != FinancialRequirementPublicationStatus.PUBLISHED) {
            return IncomeRequirementAssessment(
                status = IncomeRequirementAssessmentStatus.NO_ISSUER_PUBLISHED_MINIMUM_FOUND,
                coverage = requirements.coverage,
                paths = emptyList(),
                matchedType = null,
                closestType = null,
                missingTypes = emptyList()
            )
        }

        val paths = financial.options.map { option ->
            val reported = profile.value(option.type)
                ?: return@map IncomePathAssessment(
                    requirement = option,
                    reportedAmount = null,
                    status = IncomePathAssessmentStatus.MISSING_OWNER_INPUT,
                    shortfall = null,
                    shortfallPercentage = null
                )
            if (reported.currency != option.amount.currency) {
                return@map IncomePathAssessment(
                    requirement = option,
                    reportedAmount = reported,
                    status = IncomePathAssessmentStatus.CURRENCY_MISMATCH,
                    shortfall = null,
                    shortfallPercentage = null
                )
            }

            val met = when (option.operator) {
                IncomeRequirementOperator.AT_LEAST -> reported.amount >= option.amount.amount
                IncomeRequirementOperator.GREATER_THAN -> reported.amount > option.amount.amount
            }
            if (met) {
                IncomePathAssessment(option, reported, IncomePathAssessmentStatus.MET, null, null)
            } else {
                // Income is entered in whole currency units, so a strict boundary needs one more.
                val increment = if (option.operator == IncomeRequirementOperator.GREATER_THAN) 1.0 else 0.0
                val gap = maxOf(0.0, option.amount.amount - reported.amount + increment)
                IncomePathAssessment(
                    requirement = option,
                    reportedAmount = reported,
                    status = IncomePathAssessmentStatus.BELOW_MINIMUM,
                    shortfall = Money(gap, option.amount.currency),
                    shortfallPercentage = if (option.amount.amount > 0) gap / option.amount.amount else null
                )
            }
        }

        val matched = paths.firstOrNull { it.status == IncomePathAssessmentStatus.MET }
        if (matched != null) {
            return IncomeRequirementAssessment(
                status = IncomeRequirementAssessmentStatus.MEETS_PUBLISHED_MINIMUM,
                coverage = requirements.coverage,
                paths = paths,
                matchedType = matched.requirement.type,
                closestType = null,
                missingTypes = emptyList()
            )
        }

        val missing = paths.filter {
            it.status == IncomePathAssessmentStatus.MISSING_OWNER_INPUT ||
                it.status == IncomePathAssessmentStatus.CURRENCY_MISMATCH
        }.map { it.requirement.type }
        val closest = paths.filter { it.status == IncomePathAssessmentStatus.BELOW_MINIMUM }
            .minWithOrNull(compareBy<IncomePathAssessment> { it.shortfallPercentage ?: Double.POSITIVE_INFINITY }
                .thenBy { it.requirement.type.rawValue })

        return IncomeRequirementAssessment(
            status = if (missing.isEmpty()) IncomeRequirementAssessmentStatus.BELOW_PUBLISHED_MINIMUM
            else IncomeRequirementAssessmentStatus.NEEDS_MORE_INFORMATION,
            coverage = requirements.coverage,
            paths = paths,
            matchedType = null,
            closestType = closest?.requirement?.type,
            missingTypes = missing
        )
    }
}
