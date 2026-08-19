package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.SwitchThreshold

enum class AmbientMerchantConfidence {
    VERIFIED,
    BRAND_MATCHED,
    UNKNOWN
}

data class AmbientAdvantage(
    val percentagePoints: Double,
    val cad: Double
)

data class AmbientGateInput(
    val merchantConfidence: AmbientMerchantConfidence,
    val recommendedCardId: String,
    val defaultCardId: String,
    val advantage: AmbientAdvantage,
    val switchThreshold: SwitchThreshold,
    val isMuted: Boolean
)

enum class AmbientSuppressionReason {
    MERCHANT_CONFIDENCE_LOW,
    RECOMMENDED_DEFAULT_CARD,
    ADVANTAGE_BELOW_SWITCH_THRESHOLD,
    ADVANTAGE_BELOW_UNVERIFIED_THRESHOLD,
    MERCHANT_MUTED
}

data class AmbientGateDecision(
    val suppressionReasons: Set<AmbientSuppressionReason>
) {
    val fires: Boolean get() = suppressionReasons.isEmpty()
}

object AmbientGate {
    const val UNVERIFIED_ADVANTAGE_MULTIPLIER = 2.0

    fun evaluate(input: AmbientGateInput): AmbientGateDecision {
        val reasons = mutableSetOf<AmbientSuppressionReason>()
        if (input.recommendedCardId == input.defaultCardId) {
            reasons.add(AmbientSuppressionReason.RECOMMENDED_DEFAULT_CARD)
        }
        if (input.isMuted) {
            reasons.add(AmbientSuppressionReason.MERCHANT_MUTED)
        }

        when (input.merchantConfidence) {
            AmbientMerchantConfidence.UNKNOWN -> {
                reasons.add(AmbientSuppressionReason.MERCHANT_CONFIDENCE_LOW)
            }
            AmbientMerchantConfidence.VERIFIED -> {
                if (!clearsSwitchThreshold(input.advantage, input.switchThreshold)) {
                    reasons.add(AmbientSuppressionReason.ADVANTAGE_BELOW_SWITCH_THRESHOLD)
                }
            }
            AmbientMerchantConfidence.BRAND_MATCHED -> {
                if (!clearsSwitchThreshold(input.advantage, scaled(input.switchThreshold))) {
                    reasons.add(AmbientSuppressionReason.ADVANTAGE_BELOW_UNVERIFIED_THRESHOLD)
                }
            }
        }

        return AmbientGateDecision(suppressionReasons = reasons)
    }

    fun scaled(threshold: SwitchThreshold): SwitchThreshold {
        return SwitchThreshold(
            minAdvantagePercentagePoints = threshold.minAdvantagePercentagePoints * UNVERIFIED_ADVANTAGE_MULTIPLIER,
            minAdvantageCad = threshold.minAdvantageCad * UNVERIFIED_ADVANTAGE_MULTIPLIER,
            semantics = threshold.semantics
        )
    }

    fun clearsSwitchThreshold(advantage: AmbientAdvantage, threshold: SwitchThreshold): Boolean {
        val cadOK = advantage.cad >= threshold.minAdvantageCad
        val ppOK = advantage.percentagePoints >= threshold.minAdvantagePercentagePoints
        return if (threshold.semantics == "either") (cadOK || ppOK) else (cadOK && ppOK)
    }
}

data class SuppressionLog(
    var fired: Int = 0,
    var suppressed: Int = 0,
    val suppressedByReason: MutableMap<AmbientSuppressionReason, Int> = mutableMapOf()
) {
    fun record(decision: AmbientGateDecision) {
        if (decision.fires) {
            fired += 1
        } else {
            suppressed += 1
            for (reason in decision.suppressionReasons) {
                suppressedByReason[reason] = (suppressedByReason[reason] ?: 0) + 1
            }
        }
    }

    fun merge(other: SuppressionLog) {
        fired += other.fired
        suppressed += other.suppressed
        for ((reason, count) in other.suppressedByReason) {
            suppressedByReason[reason] = (suppressedByReason[reason] ?: 0) + count
        }
    }
}
