package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.SwitchThreshold

enum class AmbientMerchantConfidence {
    VERIFIED,
    BRAND_MATCHED,

    /**
     * A recognised merchant the owner has paid at on several separate days.
     *
     * Evidence of a different kind from VERIFIED, not a weaker grade of it: a reconciled terminal
     * proves how a charge codes, while repeated payment proves the owner shops here and that this
     * is the merchant we think it is. The category question stays exactly where BRAND_MATCHED
     * leaves it — on a brand prior.
     */
    FREQUENTED,
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

    /**
     * Kept apart from ADVANTAGE_BELOW_SWITCH_THRESHOLD for the reason the unverified counter is:
     * it is the only evidence that can say whether FREQUENTED_ADVANTAGE_MULTIPLIER is set right.
     */
    ADVANTAGE_BELOW_FREQUENTED_THRESHOLD,
    MERCHANT_MUTED
}

/**
 * How an arrival should reach the owner.
 *
 * Derived from the suppression reasons rather than added alongside them: two of the reasons are
 * volume judgements ("the answer is: keep going"), one is a correctness stop ("we do not know
 * this merchant"), and one is consent ("you told us to stop"). One boolean cannot express that.
 *
 * Mirrors `AmbientDeliveryTier` in the Swift engine. The two must agree exactly.
 */
enum class AmbientDeliveryTier {
    /** Nothing at all. The owner's explicit instruction, not a volume dial. */
    SILENT,

    /** Visible, carrying no card advice: naming a card at an unidentifiable merchant is a
     * confident wrong answer, which costs trust faster than silence does. */
    PRESENCE,

    /** Visible and advisory, never audible. */
    CONFIRM,

    /** Sound, time-sensitive banner, Live Activity. Switching cards earns money here. */
    INTERRUPT
}

data class AmbientGateDecision(
    val suppressionReasons: Set<AmbientSuppressionReason>
) {
    /**
     * Precedence: consent, then correctness, then volume. Ordered checks rather than a ranking,
     * so that adding a reason forces a decision about where it sits instead of defaulting into
     * the quietest tier by accident.
     */
    val tier: AmbientDeliveryTier
        get() = when {
            AmbientSuppressionReason.MERCHANT_MUTED in suppressionReasons ->
                AmbientDeliveryTier.SILENT
            AmbientSuppressionReason.MERCHANT_CONFIDENCE_LOW in suppressionReasons ->
                AmbientDeliveryTier.PRESENCE
            suppressionReasons.isEmpty() -> AmbientDeliveryTier.INTERRUPT
            else -> AmbientDeliveryTier.CONFIRM
        }

    /** Unchanged in meaning: PickMe interrupted. Not a statement about visibility. */
    val fires: Boolean get() = tier == AmbientDeliveryTier.INTERRUPT
}

object AmbientGate {
    const val UNVERIFIED_ADVANTAGE_MULTIPLIER = 2.0

    /**
     * 1.0 — the owner's own floor, unscaled. The 2.0 above covers three doubts at once (identity,
     * presence, coding) and patronage retires the first two. It does not retire the third, which
     * is why this is a separate, tunable constant rather than a fold into VERIFIED.
     */
    const val FREQUENTED_ADVANTAGE_MULTIPLIER = 1.0

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
                if (!clearsSwitchThreshold(
                        input.advantage,
                        scaled(input.switchThreshold, UNVERIFIED_ADVANTAGE_MULTIPLIER)
                    )
                ) {
                    reasons.add(AmbientSuppressionReason.ADVANTAGE_BELOW_UNVERIFIED_THRESHOLD)
                }
            }
            AmbientMerchantConfidence.FREQUENTED -> {
                if (!clearsSwitchThreshold(
                        input.advantage,
                        scaled(input.switchThreshold, FREQUENTED_ADVANTAGE_MULTIPLIER)
                    )
                ) {
                    reasons.add(AmbientSuppressionReason.ADVANTAGE_BELOW_FREQUENTED_THRESHOLD)
                }
            }
        }

        return AmbientGateDecision(suppressionReasons = reasons)
    }

    fun scaled(threshold: SwitchThreshold, multiplier: Double): SwitchThreshold {
        return SwitchThreshold(
            minAdvantagePercentagePoints = threshold.minAdvantagePercentagePoints * multiplier,
            minAdvantageCad = threshold.minAdvantageCad * multiplier,
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
