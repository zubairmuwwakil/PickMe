package com.cardcopilot.engine.models

import com.cardcopilot.engine.loading.SeedLoader
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject

@Serializable
data class SwitchThreshold(
    val minAdvantagePercentagePoints: Double,
    val minAdvantageCad: Double,
    val semantics: String // "both" | "either"
)

@Serializable
data class Carry(
    val drawerCards: List<String> = emptyList()
)

@Serializable
enum class TangerineMoneyBackCategory {
    @SerialName("grocery") GROCERY,
    @SerialName("dining") DINING,
    @SerialName("gasStation") GAS_STATION,
    @SerialName("entertainment") ENTERTAINMENT,
    @SerialName("furniture") FURNITURE,
    @SerialName("lodging") LODGING,
    @SerialName("drugStore") DRUG_STORE,
    @SerialName("recurring") RECURRING,
    @SerialName("homeImprovement") HOME_IMPROVEMENT,
    @SerialName("transit") TRANSIT,
    @SerialName("eGames") E_GAMES,
    @SerialName("fitness") FITNESS,
    @SerialName("foreignCurrency") FOREIGN_CURRENCY;

    val rawValue: String get() = when (this) {
        GROCERY -> "grocery"
        DINING -> "dining"
        GAS_STATION -> "gasStation"
        ENTERTAINMENT -> "entertainment"
        FURNITURE -> "furniture"
        LODGING -> "lodging"
        DRUG_STORE -> "drugStore"
        RECURRING -> "recurring"
        HOME_IMPROVEMENT -> "homeImprovement"
        TRANSIT -> "transit"
        E_GAMES -> "eGames"
        FITNESS -> "fitness"
        FOREIGN_CURRENCY -> "foreignCurrency"
    }
}

@Serializable
data class CardState(
    val capProgress: Map<String, Double>? = null,
    val scotiaAccountYearAnchorMonth: Int? = null,
    val selectedCategories: List<String>? = null,
    val treatAsAllSelected: Boolean? = null,
    val thirdCategoryUnlocked: Boolean? = null,
    val nextChangeEffectiveDate: String? = null,
    val rogersEligibleServiceLinked: Boolean? = null,
    val rogersAccountAnniversaryMonth: Int? = null,
    val feeWaiverActive: Boolean? = null,
    val cryptoLevelUpProActive: Boolean? = null,
    val croHandling: String? = null // "autoSell" | "hold" | null
)

/**
 * Reward-currency valuations, keyed by the catalogue's `programId`.
 *
 * Was six hardcoded properties, which made every new rewards program a Swift change, a Kotlin
 * change, a schema-enum change and an owner-state migration. Sixteen programIds shipped in the
 * catalogue against those six properties before this was fixed, and every card on the other ten
 * scored $0.00 on every purchase while staying selectable in wallet setup.
 *
 * The payload types ([PointValuation] and friends) live in ProgramValuation.kt, where they are
 * the sealed subclasses of [ProgramValuation].
 */
@Serializable(with = ValuationsSerializer::class)
data class Valuations(val programs: Map<String, ProgramValuation> = emptyMap()) {

    operator fun get(programId: String): ProgramValuation? = programs[programId]

    /**
     * A points program's valuation, or null when the program is absent or valued under a
     * different model. The Kotlin twin of Swift's `subscript(points:)`.
     *
     * Exists because cents-per-point is the one field callers routinely read and write — the
     * valuation sandbox, wallet setup, and every sensitivity test. Without it each call site
     * would repeat an `as?` dance, and the sites that got it wrong would fail silently.
     */
    fun points(programId: String): PointValuation? = programs[programId] as? PointValuation

    /** [programs] with one entry replaced. Null removes the entry, mirroring the Swift setter. */
    fun setting(programId: String, valuation: ProgramValuation?): Valuations =
        copy(programs = if (valuation == null) programs - programId else programs + (programId to valuation))
}

/**
 * Legacy owner states name each program as its own top-level key and carry no `model`
 * discriminator — the model was implied by the key. New ones nest a `programs` dictionary.
 * Both decode; only the latter is ever written back, so a wallet upgrades itself the first
 * time it is saved. Delete the legacy branch one full release cycle after ship, with a dated
 * entry in contracts/CHANGELOG.md.
 *
 * The legacy branch decodes key-by-key into the concrete payload type rather than going through
 * the polymorphic serializer: the legacy key set is closed, so the model each key implies is
 * known statically, and unlisted keys are skipped by construction. Decoding a sealed subclass by
 * its own serializer does not consult the class discriminator, which is exactly what a legacy
 * block — having no `model` key — needs.
 *
 * The modern branch is gated on key *presence* and then decodes without swallowing failures, so
 * a malformed `programs` block throws instead of falling through to the legacy branch and
 * quietly producing an empty wallet. Mirrors the Swift twin's `Valuations.init(from:)`.
 */
object ValuationsSerializer : KSerializer<Valuations> {
    private val programsSerializer = MapSerializer(String.serializer(), ProgramValuation.serializer())

    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Valuations") {
        element("programs", programsSerializer.descriptor)
    }

    /**
     * Legacy top-level key to (payload serializer, catalogue programId). The catalogue spells
     * cash back's programId lowercase while the legacy key is camelCase; getting that one
     * mapping wrong silently unvalues every cash-back card.
     */
    private val legacyKeys: List<Triple<String, KSerializer<out ProgramValuation>, String>> = listOf(
        Triple("amexMembershipRewards", PointValuation.serializer(), "amexMembershipRewards"),
        Triple("marriottBonvoy", PointValuation.serializer(), "marriottBonvoy"),
        Triple("mbnaRewards", PointValuation.serializer(), "mbnaRewards"),
        Triple("ctMoney", CtMoneyValuation.serializer(), "ctMoney"),
        Triple("cro", CroValuation.serializer(), "cro"),
        Triple("cashBack", CashBackValuation.serializer(), "cashback")
    )

    override fun deserialize(decoder: Decoder): Valuations {
        val jsonDecoder = decoder as? JsonDecoder
            ?: throw SerializationException("ValuationsSerializer only supports JSON decoding")
        val root = jsonDecoder.decodeJsonElement() as? JsonObject
            ?: throw SerializationException("Expected JsonObject for Valuations")

        root["programs"]?.let { programs ->
            return Valuations(jsonDecoder.json.decodeFromJsonElement(programsSerializer, programs))
        }

        val programs = mutableMapOf<String, ProgramValuation>()
        for ((legacyKey, serializer, programId) in legacyKeys) {
            val element = root[legacyKey] ?: continue
            programs[programId] = jsonDecoder.json.decodeFromJsonElement(serializer, element)
        }
        // Anything else in a legacy block — `rogersEligibleServiceRedemption`, say — is not a
        // catalogue programId and has no ProgramValuation model. Ignored, never fatal.
        return Valuations(programs)
    }

    override fun serialize(encoder: Encoder, value: Valuations) {
        val jsonEncoder = encoder as? JsonEncoder
            ?: throw SerializationException("ValuationsSerializer only supports JSON encoding")
        jsonEncoder.encodeJsonElement(
            buildJsonObject {
                put("programs", jsonEncoder.json.encodeToJsonElement(programsSerializer, value.programs))
            }
        )
    }
}

@Serializable
data class OwnerState(
    val ownerStateVersion: String,
    val ownedCardIds: List<String>,
    val defaultCardId: String,
    val switchThreshold: SwitchThreshold,
    val carry: Carry = Carry(),
    val cardStates: Map<String, CardState> = emptyMap(),
    val valuationsCad: Valuations
)

/**
 * This state with catalogue defaults filled in beneath anything the owner has declared.
 *
 * A valuation is a personal forecast of redemption behaviour, so the catalogue may supply a
 * number where the owner has none but must never overrule one they have declared. That
 * direction is the whole contract.
 *
 * Applied at `RecommendationEngine`'s constructor, which every scoring path funnels through —
 * PortfolioAnalyzer, RecurringAuditor, CategoryPickerAdvisor and store's CheckoutService all
 * construct one. Merging in `SeedLoader.loadOwnerState()` instead would reach the shipped seed
 * and nothing else: owner states restored from a device never pass through SeedLoader, and
 * those are the real wallets.
 *
 * Idempotent, so re-merging an already-merged state (PortfolioAnalyzer builds sub-engines from
 * a state it already holds) costs a map merge and changes nothing.
 */
fun OwnerState.applyingCatalogueValuationDefaults(
    defaults: Map<String, ProgramValuation> = SeedLoader.programValuationDefaults
): OwnerState = copy(
    valuationsCad = Valuations(defaults + valuationsCad.programs)
)
