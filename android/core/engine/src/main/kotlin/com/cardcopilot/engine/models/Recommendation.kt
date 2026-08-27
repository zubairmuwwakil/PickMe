package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class Warning(val rawValue: String) {
    @SerialName("drawerCard") DRAWER_CARD("drawerCard"),
    @SerialName("unresolvedOwnerState") UNRESOLVED_OWNER_STATE("unresolvedOwnerState"),
    @SerialName("networkNotAccepted") NETWORK_NOT_ACCEPTED("networkNotAccepted"),
    @SerialName("capNearlyExhausted") CAP_NEARLY_EXHAUSTED("capNearlyExhausted"),
    @SerialName("negativeNetValue") NEGATIVE_NET_VALUE("negativeNetValue"),
    @SerialName("fxAllowanceAssumed") FX_ALLOWANCE_ASSUMED("fxAllowanceAssumed"),
    @SerialName("hypotheticalSelection") HYPOTHETICAL_SELECTION("hypotheticalSelection"),

    /**
     * This card's rewards program has no valuation. The card cannot be scored at all —
     * distinct from being scored and losing.
     */
    @SerialName("unsupportedProgram") UNSUPPORTED_PROGRAM("unsupportedProgram"),

    /**
     * An earn rule requires an engine capability this build does not have. The rule is
     * skipped; the card is still scored on its remaining rules.
     */
    @SerialName("unsupportedCapability") UNSUPPORTED_CAPABILITY("unsupportedCapability"),

    /**
     * The issuer has discontinued this product as of the scored date. Mirrors Swift's
     * `Warning.productWithdrawn`, which PickMe's engine owns.
     */
    @SerialName("productWithdrawn") PRODUCT_WITHDRAWN("productWithdrawn"),

    /**
     * `card.status == DRAFT` — a research-grade catalogue record that has not cleared D3's
     * issuer-confirmed sourcing bar. Excluded outright, never merely scored with a caveat.
     */
    @SerialName("draftProduct") DRAFT_PRODUCT("draftProduct");

    companion object {
        fun fromRaw(raw: String): Warning? = entries.firstOrNull { it.rawValue == raw }
    }
}

@Serializable
data class CandidateScore(
    val cardId: String,
    val appliedRuleId: String? = null,
    val rewardUnits: Double,
    val grossRewardCad: Double,
    val fxCostCad: Double,
    val netValueCad: Double,
    val floorNetValueCad: Double,
    val aspirationalNetValueCad: Double,
    val warnings: List<Warning> = emptyList(),
    val excluded: Boolean = false,
    val exclusionReason: String? = null
)

@Serializable
enum class ValuationDirection {
    @SerialName("below") BELOW,
    @SerialName("above") ABOVE
}

@Serializable
data class Recommendation(
    val winner: CandidateScore,
    val runnerUp: CandidateScore? = null,
    val switchedFromDefault: Boolean,
    val advantageOverDefaultCad: Double? = null,
    val defaultNotAccepted: Boolean,
    val suppressedBetterCard: CandidateScore? = null,
    val valuationSensitive: Boolean,
    val valuationDirection: ValuationDirection? = null,
    val alternateWinnerCardId: String? = null,
    val breakevenCentsPerPoint: Double? = null,
    val declaredCentsPerPoint: Double? = null,
    val allCandidates: List<CandidateScore>
)

/**
 * Either advice, or an explicit refusal. The engine can now be genuinely unable to advise —
 * a wallet whose every card is on an unvalued program — and inventing a $0.00 winner would
 * present a refusal as advice.
 */
sealed interface RecommendationOutcome {
    data class Advised(val recommendation: Recommendation) : RecommendationOutcome
    data class CannotAdvise(val reasons: List<String>) : RecommendationOutcome
}
