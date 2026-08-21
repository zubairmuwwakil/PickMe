package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * What this engine build can actually do. Earn rules declare what they need; a rule needing
 * something absent here is skipped with a warning rather than scored wrongly.
 *
 * Replaces the hand-set `scoredInV1` boolean, which had no machine meaning: nothing checked that
 * a rule marked true was supported, and enabling a capability meant hunting the catalogue for
 * every flag to flip. Adding a case here turns on every rule that declared it, with no catalogue
 * edit — the maintenance burden inverts from O(rules) to O(capabilities).
 *
 * The raw values and the [supported] set are a cross-language contract with the Swift twin
 * (`Engine/Sources/CardCopilotEngine/Models/EngineCapability.swift`). The two engines reading
 * the same catalogue must gate the same rules, or a card scores on Android and vanishes on iOS.
 */
@Serializable
enum class EngineCapability(val rawValue: String) {
    @SerialName("cap.calendarMonth") CAP_CALENDAR_MONTH("cap.calendarMonth"),
    @SerialName("cap.calendarYear") CAP_CALENDAR_YEAR("cap.calendarYear"),
    @SerialName("cap.accountYear") CAP_ACCOUNT_YEAR("cap.accountYear"),
    @SerialName("cap.statementYear") CAP_STATEMENT_YEAR("cap.statementYear"),
    @SerialName("cap.globalGroup") CAP_GLOBAL_GROUP("cap.globalGroup"),
    @SerialName("predicate.merchantPartnerList") MERCHANT_PARTNER_LIST("predicate.merchantPartnerList"),
    @SerialName("predicate.mccStrict") MCC_STRICT("predicate.mccStrict"),
    @SerialName("earn.perLitre") UNIT_PER_LITRE("earn.perLitre"),
    @SerialName("earn.marginal") MARGINAL_EARN("earn.marginal");

    companion object {
        /**
         * Capabilities this build implements. The rest are declared so rules can name them and
         * turn on automatically when they ship. `predicate.channelIdentity` is deliberately
         * absent from this enum entirely — online booking channels are permanently out of scope
         * for an at-the-register copilot, so rules needing them use `outOfScope`, not `requires`.
         */
        val supported: Set<EngineCapability> = setOf(
            CAP_CALENDAR_MONTH, CAP_CALENDAR_YEAR, CAP_ACCOUNT_YEAR
        )

        fun fromRaw(raw: String): EngineCapability? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * A rule that will never be scored, with the reason. Distinct from `requires`, which means
 * "not yet". Collapsing the two is how someone later builds a capability that was ruled out.
 */
@Serializable
data class OutOfScope(val reason: String)
