package com.cardcopilot.engine.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class BenefitVerification {
    @SerialName("stub") STUB,
    @SerialName("issuerPage") ISSUER_PAGE,
    @SerialName("certificateVerified") CERTIFICATE_VERIFIED
}

enum class BenefitFamily(val rawValue: String) {
    SHOPPING("shopping"),
    TRAVEL_DISRUPTION("travelDisruption"),
    RENTAL_CDW("rentalCdw"),
    TRAVEL_MEDICAL("travelMedical");

    companion object {
        fun fromRaw(raw: String): BenefitFamily? = entries.firstOrNull { it.rawValue == raw }
    }
}

enum class BenefitKind(val rawValue: String) {
    PURCHASE_PROTECTION("purchaseProtection"),
    EXTENDED_WARRANTY("extendedWarranty"),
    MOBILE_DEVICE_INSURANCE("mobileDeviceInsurance"),
    FLIGHT_DELAY("flightDelay"),
    BAGGAGE_DELAY("baggageDelay"),
    BAGGAGE_LOSS("baggageLoss"),
    TRIP_CANCELLATION("tripCancellation"),
    TRIP_INTERRUPTION("tripInterruption"),
    RENTAL_CDW("rentalCdw"),
    TRAVEL_MEDICAL("travelMedical");

    companion object {
        fun fromRaw(raw: String): BenefitKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

@Serializable
data class BenefitCoverage(
    val windowDays: Int? = null,
    val maxPerOccurrenceCad: Double? = null,
    val maxAnnualCad: Double? = null,
    val extraYears: Int? = null,
    val maxOriginalWarrantyYears: Int? = null,
    val maxCad: Double? = null,
    val deductibleCad: Double? = null,
    val delayHours: Int? = null,
    val perDayCad: Double? = null,
    val maxTripLengthDays: Int? = null,
    val maxRentalDays: Int? = null,
    val maxVehicleValueCad: Double? = null,
    val ageLimit: Int? = null
)

@Serializable
data class Benefit(
    val benefitId: String,
    val family: String,
    val kind: String,
    val coverage: BenefitCoverage = BenefitCoverage(),
    val conditions: List<String> = emptyList(),
    val exclusions: List<String>? = null,
    val certificateQuote: String? = null,
    val notes: String? = null
) {
    val knownKind: BenefitKind? get() = BenefitKind.fromRaw(kind)
    val knownFamily: BenefitFamily? get() = BenefitFamily.fromRaw(family)
}

@Serializable
data class CertificateProvenance(
    val underwriter: String? = null,
    val sourceUrl: String? = null,
    val certificateDate: String? = null,
    val lastVerifiedAt: String? = null,
    val verificationStatus: BenefitVerification
)

@Serializable
data class CardBenefits(
    val cardId: String,
    val certificate: CertificateProvenance,
    val benefits: List<Benefit> = emptyList()
)

@Serializable
data class BenefitsTriggers(
    val bigTicketThresholdCad: Double,
    val consumableCategories: List<String>
)

@Serializable
data class BenefitsCatalogue(
    val benefitsCatalogueVersion: String,
    val triggers: BenefitsTriggers,
    val cards: List<CardBenefits>
) {
    fun card(cardId: String): CardBenefits? = cards.firstOrNull { it.cardId == cardId }
}
