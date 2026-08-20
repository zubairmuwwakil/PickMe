package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

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

@Serializable
data class PointValuation(
    val centsPerPoint: Double,
    val floorCentsPerPoint: Double? = null,
    val aspirationalCentsPerPoint: Double? = null,
    val low: Double? = null,
    val high: Double? = null,
    val basis: String? = null
)

@Serializable
data class CtMoneyValuation(
    val cadPerUnit: Double,
    val optionalUsabilityFactor: Double,
    val usabilityFactorApplied: Boolean
)

@Serializable
data class CroValuation(
    /** How CRO converts to CAD. Renamed from `model` 2026-08-20 so the Swift twin's
     *  ProgramValuation discriminator can own that key at the same JSON level. */
    val redemptionModel: String,
    val faceValueFactorIfAutoSold: Double,
    val defaultHeldRiskFactor: Double
)

@Serializable
data class CashBackValuation(
    val cadPerDollar: Double
)

@Serializable
data class Valuations(
    val amexMembershipRewards: PointValuation,
    val marriottBonvoy: PointValuation,
    val mbnaRewards: PointValuation,
    val ctMoney: CtMoneyValuation,
    val cro: CroValuation,
    val cashBack: CashBackValuation
)

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
