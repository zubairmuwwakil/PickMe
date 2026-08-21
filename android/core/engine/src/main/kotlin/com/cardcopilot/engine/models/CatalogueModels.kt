package com.cardcopilot.engine.models

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encoding.decodeStructure
import kotlinx.serialization.encoding.encodeStructure
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

@Serializable
enum class Network {
    @SerialName("amex") AMEX,
    @SerialName("visa") VISA,
    @SerialName("mastercard") MASTERCARD;

    val rawValue: String get() = name.lowercase()
}

@Serializable
enum class CardKind {
    @SerialName("credit") CREDIT,
    @SerialName("charge") CHARGE,
    @SerialName("prepaid") PREPAID
}

@Serializable
enum class RuleStatus {
    @SerialName("current") CURRENT,
    @SerialName("announced") ANNOUNCED
}

@Serializable
enum class SourceType {
    @SerialName("issuerConfirmed") ISSUER_CONFIRMED,
    @SerialName("ownerObserved") OWNER_OBSERVED,
    @SerialName("inferred") INFERRED
}

@Serializable(with = EarnSerializer::class)
sealed interface Earn {
    data class Points(val pointsPerCad: Double) : Earn
    data class Cashback(val rate: Double, val rewardCurrency: String? = null) : Earn
    data object CentsPerLitre : Earn
}

object EarnSerializer : KSerializer<Earn> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Earn") {
        element<String>("type")
        element<Double>("pointsPerCad", isOptional = true)
        element<Double>("rate", isOptional = true)
        element<String>("rewardCurrency", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): Earn {
        val jsonDecoder = decoder as? JsonDecoder
            ?: throw SerializationException("EarnSerializer only supports JSON decoding")
        val root = jsonDecoder.decodeJsonElement() as? JsonObject
            ?: throw SerializationException("Expected JsonObject for Earn")
        val type = root["type"]?.jsonPrimitive?.content
            ?: throw SerializationException("Missing 'type' field in Earn")

        return when (type) {
            "points" -> {
                val pointsPerCad = root["pointsPerCad"]?.jsonPrimitive?.double
                    ?: throw SerializationException("Missing pointsPerCad for points Earn")
                Earn.Points(pointsPerCad)
            }
            "cashback" -> {
                val rate = root["rate"]?.jsonPrimitive?.double
                    ?: throw SerializationException("Missing rate for cashback Earn")
                val currency = root["rewardCurrency"]?.jsonPrimitive?.contentOrNull
                Earn.Cashback(rate, currency)
            }
            "centsPerLitre" -> Earn.CentsPerLitre
            else -> throw SerializationException("Unknown Earn type: $type")
        }
    }

    override fun serialize(encoder: Encoder, value: Earn) {
        encoder.encodeStructure(descriptor) {
            when (value) {
                is Earn.Points -> {
                    encodeStringElement(descriptor, 0, "points")
                    encodeDoubleElement(descriptor, 1, value.pointsPerCad)
                }
                is Earn.Cashback -> {
                    encodeStringElement(descriptor, 0, "cashback")
                    encodeDoubleElement(descriptor, 2, value.rate)
                    value.rewardCurrency?.let { encodeStringElement(descriptor, 3, it) }
                }
                is Earn.CentsPerLitre -> {
                    encodeStringElement(descriptor, 0, "centsPerLitre")
                }
            }
        }
    }
}

@Serializable
data class Predicate(
    val categories: List<String>? = null,
    val mccInclude: List<Int>? = null,
    val mccExclude: List<Int>? = null,
    val merchantInclude: List<String>? = null,
    val merchantExclude: List<String>? = null,
    val country: String? = null,
    val currency: String? = null,
    val channels: List<String>? = null,
    val recurringViaNetworkIndicator: Boolean? = null
)

@Serializable
data class EarnRule(
    val ruleId: String,
    val status: RuleStatus,
    val effectiveFrom: String? = null,
    val effectiveTo: String? = null,
    val sourceType: SourceType,
    val earn: Earn,
    val predicate: Predicate = Predicate(),
    val capId: String? = null,
    val ownerConditions: List<String>? = null,
    val scoredInV1: Boolean? = null,
    /**
     * Engine capabilities this rule needs, as [EngineCapability] raw values. Absent means none.
     * A rule naming a capability this build lacks is skipped; it turns on by itself when that
     * capability ships. Typed as `List<String>` rather than `List<EngineCapability>` so an
     * unrecognised name is a gating decision made in code, not a decode failure that loses the
     * whole catalogue — a card the engine cannot fully score is still a card it can partly score.
     */
    val requires: List<String>? = null,
    /** Set when the rule will never be scored. Mutually exclusive with [requires]. */
    val outOfScope: OutOfScope? = null
)

@Serializable
enum class CapMeasure {
    @SerialName("spendCad") SPEND_CAD,
    @SerialName("spendUsdEquivalent") SPEND_USD_EQUIVALENT
}

@Serializable
enum class CapPeriod {
    @SerialName("calendarMonth") CALENDAR_MONTH,
    @SerialName("calendarYear") CALENDAR_YEAR,
    @SerialName("accountYear") ACCOUNT_YEAR
}

@Serializable
data class Cap(
    val capId: String,
    val measure: CapMeasure,
    val limit: Double,
    val period: CapPeriod,
    val anchor: String? = null,
    val resetTimeZone: String,
    val postCapEarn: Earn? = null,
    val proration: Boolean
)

@Serializable
data class FxRule(
    val status: RuleStatus,
    val effectiveFrom: String? = null,
    val effectiveTo: String? = null,
    val rate: Double,
    val freeAllowanceCadPerCalendarMonth: Double? = null,
    val postAllowanceRate: Double? = null
)

@Serializable
data class Fee(
    val annualCad: Double? = null,
    val monthlyCad: Double? = null,
    val billing: String? = null,
    val waiver: String? = null
)

@Serializable
data class Program(
    val programId: String,
    val unit: String
)

@Serializable
data class CardProduct(
    val cardId: String,
    val officialName: String,
    val issuer: String,
    val network: Network,
    val kind: CardKind,
    val fee: Fee,
    val program: Program,
    val fxRules: List<FxRule> = emptyList(),
    val earnRules: List<EarnRule> = emptyList(),
    val caps: List<Cap> = emptyList(),
    val perTransactionRewardVisibility: String,
    val lastVerifiedAt: String
)

@Serializable
data class Catalogue(
    val catalogueVersion: String,
    val currency: String,
    val cards: List<CardProduct>
)
