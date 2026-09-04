package com.cardcopilot.store.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class ConfidenceSource(val rawValue: String) {
    @SerialName("ownerConfirmedTerminal") OWNER_CONFIRMED_TERMINAL("ownerConfirmedTerminal"),
    @SerialName("repeatedTerminal") REPEATED_TERMINAL("repeatedTerminal"),
    @SerialName("issuerOverride") ISSUER_OVERRIDE("issuerOverride"),
    @SerialName("observedMcc") OBSERVED_MCC("observedMcc"),
    @SerialName("brandPrior") BRAND_PRIOR("brandPrior"),
    @SerialName("mapKitCategory") MAP_KIT_CATEGORY("mapKitCategory"),
    @SerialName("fallback") FALLBACK("fallback");

    val isVerified: Boolean
        get() = this == OWNER_CONFIRMED_TERMINAL || this == REPEATED_TERMINAL

    val defaultScore: Double
        get() = when (this) {
            REPEATED_TERMINAL -> 0.99
            OWNER_CONFIRMED_TERMINAL -> 0.95
            ISSUER_OVERRIDE -> 0.90
            OBSERVED_MCC -> 0.85
            BRAND_PRIOR -> 0.70
            MAP_KIT_CATEGORY -> 0.55
            FALLBACK -> 0.10
        }

    companion object {
        fun fromRaw(raw: String): ConfidenceSource {
            return entries.firstOrNull { it.rawValue == raw } ?: FALLBACK
        }
    }
}

@Serializable
enum class MissClass(val rawValue: String) {
    @SerialName("wrongCategory") WRONG_CATEGORY("wrongCategory"),
    @SerialName("capExceeded") CAP_EXCEEDED("capExceeded"),
    @SerialName("staleRule") STALE_RULE("staleRule"),
    @SerialName("processorWeirdness") PROCESSOR_WEIRDNESS("processorWeirdness"),
    @SerialName("networkNotAccepted") NETWORK_NOT_ACCEPTED("networkNotAccepted");

    companion object {
        fun fromRaw(raw: String?): MissClass? {
            if (raw == null) return null
            return entries.firstOrNull { it.rawValue == raw }
        }
    }
}

@Serializable
enum class CaptureSource(val rawValue: String) {
    @SerialName("atTill") AT_TILL("atTill"),
    @SerialName("recalledLater") RECALLED_LATER("recalledLater"),
    @SerialName("walletCapture") WALLET_CAPTURE("walletCapture");

    companion object {
        fun fromRaw(raw: String?): CaptureSource? {
            if (raw == null) return null
            return entries.firstOrNull { it.rawValue == raw }
        }
    }
}

enum class MissingPurchaseFact {
    CARD,
    AMOUNT
}

data class NearbyPlace(
    val id: String,
    val name: String,
    val poiCategoryRaw: String? = null,
    val latitude: Double,
    val longitude: Double,
    val distanceMeters: Double? = null,
    val merchantCategoryCode: Int? = null
)

data class CategoryPrediction(
    val category: String,
    val confidenceSource: ConfidenceSource,
    val candidates: List<String>,
    val confidenceScore: Double = confidenceSource.defaultScore,
    val rawCategory: String? = null,
    val merchantCategoryCode: Int? = null,
    val merchantGroupID: String? = null,
    val taxonomyVersion: String = com.cardcopilot.engine.models.CategoryTaxonomy.taxonomyVersion
)
