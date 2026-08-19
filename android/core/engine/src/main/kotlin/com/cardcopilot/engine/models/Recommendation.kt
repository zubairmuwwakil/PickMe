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
    @SerialName("hypotheticalSelection") HYPOTHETICAL_SELECTION("hypotheticalSelection");

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
