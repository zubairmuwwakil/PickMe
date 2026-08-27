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
    @SerialName("mastercard") MASTERCARD,
    @SerialName("discover") DISCOVER;

    val rawValue: String get() = name.lowercase()
}

/**
 * The country a card product is sold in. NOT, by itself, an eligibility claim beyond "this is the
 * market the card is sold in" — see [Eligibility.residency] for the rare card sold in more than
 * one. Mirrors Swift's `Market` — a cross-language contract, same reasoning as [EngineCapability].
 */
@Serializable
enum class Market(val rawValue: String) {
    @SerialName("CA") CA("CA"),
    @SerialName("US") US("US")
}

/**
 * The two currencies this catalogue represents. Used for [CardProduct.billingCurrency] and
 * [Money]. Adding a third market's currency is a schema + engine change — see
 * `ReportingCurrency.toReporting` (Engine/Sources/CardCopilotEngine/Models/ReportingCurrency.swift)
 * for the pinned-rate mechanism this would need to gain a case in too.
 */
@Serializable
enum class Currency(val rawValue: String) {
    @SerialName("CAD") CAD("CAD"),
    @SerialName("USD") USD("USD")
}

/**
 * A currency-tagged monetary figure. Replaces the old bare CAD-assuming numbers
 * (`Fee.annualCad`/`monthlyCad`) — a price without a currency must never be summed with one that
 * has it (see `ReportingCurrency` in the Swift twin for the conversion-at-point-of-use rule this
 * type exists to support).
 */
@Serializable
data class Money(val amount: Double, val currency: Currency)

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
    /**
     * Points per unit of the card's OWN [CardProduct.billingCurrency] — 1 point per USD billed
     * for a USD-billing card, not per CAD unconditionally. Renamed from `pointsPerCad` in
     * catalogue 2.0.
     */
    data class Points(val pointsPerUnit: Double) : Earn
    data class Cashback(val rate: Double, val rewardCurrency: String? = null) : Earn
    data object CentsPerLitre : Earn
}

object EarnSerializer : KSerializer<Earn> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Earn") {
        element<String>("type")
        element<Double>("pointsPerUnit", isOptional = true)
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
                val pointsPerUnit = root["pointsPerUnit"]?.jsonPrimitive?.double
                    ?: throw SerializationException("Missing pointsPerUnit for points Earn")
                Earn.Points(pointsPerUnit)
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
                    encodeDoubleElement(descriptor, 1, value.pointsPerUnit)
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

/**
 * `SPEND_CAD`/`"spendCad"` renamed to `SPEND_NATIVE`/`"spendNative"` in catalogue 2.0: the amount
 * is measured in the CARD's own [CardProduct.billingCurrency], not CAD unconditionally.
 * `SPEND_USD_EQUIVALENT` is unchanged.
 */
@Serializable
enum class CapMeasure {
    @SerialName("spendNative") SPEND_NATIVE,
    @SerialName("spendUsdEquivalent") SPEND_USD_EQUIVALENT
}

/**
 * `CALENDAR_QUARTER` added for US rotating-category cards (e.g. 5x groceries up to $1,500/
 * quarter) — a shape this catalogue could not previously express at all. Gated the same way as
 * the other periods: [EngineCapability.CAP_CALENDAR_QUARTER].
 */
@Serializable
enum class CapPeriod {
    @SerialName("calendarMonth") CALENDAR_MONTH,
    @SerialName("calendarQuarter") CALENDAR_QUARTER,
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

/**
 * `annualCad`/`monthlyCad: Double?` renamed to `annual`/`monthly: Money?` in catalogue 2.0 — a US
 * card's fee is stated in USD, never converted to CAD at authoring time. Not read by [Scorer] at
 * all (fee has no bearing on a single checkout pick); `PortfolioAnalyzer`/`AcquisitionAnalyzer`
 * convert it to the engine's CAD reporting currency via `ReportingCurrency.toReporting`.
 */
@Serializable
data class Fee(
    val annual: Money? = null,
    val monthly: Money? = null,
    val billing: String? = null,
    val waiver: String? = null
)

@Serializable
data class Program(
    val programId: String,
    val unit: String
)

/**
 * Which market(s) a resident must be in to hold a card. Absent means "assume `[market]`" —
 * `AcquisitionAnalyzer` falls back to the card's own `market` when this is nil.
 */
@Serializable
data class Eligibility(val residency: List<Market>? = null)

/**
 * `PUBLISHED` (absent decodes as this — backward compatible with every pre-2.0 card) is a
 * checkout-eligible product that has cleared this catalogue's issuer-confirmed sourcing bar (D3).
 * `DRAFT` is a research-grade record that has NOT: `RecommendationEngine`/`PortfolioAnalyzer`
 * refuse to consider a draft card even if it somehow ended up in `ownedCardIds`. Mirrors Swift's
 * `CardStatus` — see that type's doc comment for the full reasoning.
 */
@Serializable
enum class CardStatus {
    @SerialName("published") PUBLISHED,
    @SerialName("draft") DRAFT
}

/** Availability is independent of publication quality: a published card may later be withdrawn. */
@Serializable
enum class ProductLifecycleStatus {
    @SerialName("active") ACTIVE,
    @SerialName("withdrawn") WITHDRAWN
}

@Serializable
data class CardProduct(
    val cardId: String,
    val officialName: String,
    val issuer: String,
    /** The country this product is sold in. Defaults to CA — every pre-2.0 card is Canadian. */
    val market: Market = Market.CA,
    /**
     * The currency a purchase is measured in for THIS card's own earn rules and caps. Independent
     * of [market] — see the Swift twin's doc comment on `CardProduct.billingCurrency`.
     */
    val billingCurrency: Currency = Currency.CAD,
    val network: Network,
    val kind: CardKind,
    /** Absent decodes as [CardStatus.PUBLISHED]. */
    val status: CardStatus? = null,
    val eligibility: Eligibility? = null,
    val fee: Fee,
    val program: Program,
    val fxRules: List<FxRule> = emptyList(),
    val earnRules: List<EarnRule> = emptyList(),
    val caps: List<Cap> = emptyList(),
    val perTransactionRewardVisibility: String,
    val lastVerifiedAt: String,
    /** Absent means active for catalogues written before tombstoning existed. */
    val lifecycleStatus: ProductLifecycleStatus? = null,
    /** Last date on which a withdrawn product remains scoreable. */
    val effectiveTo: String? = null
) {
    /** Scorable right now (D3's sourcing bar cleared) — see [CardStatus]. */
    val isPublished: Boolean get() = (status ?: CardStatus.PUBLISHED) == CardStatus.PUBLISHED

    fun isScoreable(asOf: String): Boolean =
        lifecycleStatus != ProductLifecycleStatus.WITHDRAWN ||
            (effectiveTo?.let { asOf <= it } ?: false)
}

@Serializable
data class Catalogue(
    val catalogueVersion: String,
    val currency: String,
    val cards: List<CardProduct>
)

/**
 * The researched acquisition candidates, as references into [Catalogue] — never as card
 * definitions. Mirrors Swift's `CandidateSet` (see `SeedLoader.loadCandidateCatalogue`'s doc
 * comment there for why: a card defined in two places always drifts, one referenced by id
 * cannot). `candidate-catalogue.json` carried full duplicate card definitions before 2026-08-24;
 * this type is the post-refactor shape.
 */
@Serializable
data class CandidateSet(
    val candidateCatalogueVersion: String = "2.0",
    val cardIds: List<String> = emptyList()
)
