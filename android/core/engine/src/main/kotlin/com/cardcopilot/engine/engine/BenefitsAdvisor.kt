package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.Benefit
import com.cardcopilot.engine.models.BenefitCoverage
import com.cardcopilot.engine.models.BenefitFamily
import com.cardcopilot.engine.models.BenefitKind
import com.cardcopilot.engine.models.BenefitVerification
import com.cardcopilot.engine.models.BenefitsCatalogue
import com.cardcopilot.engine.models.BenefitsTriggers
import com.cardcopilot.engine.models.PurchaseContext

data class BenefitDisclosure(
    val cardId: String,
    val kind: String,
    val coverage: BenefitCoverage,
    val conditions: List<String>,
    val exclusions: List<String>,
    val verification: BenefitVerification
) {
    val id: String get() = "$cardId/$kind"
}

data class CrossCardNudge(
    val cardId: String,
    val kind: String
)

data class DisclosureResult(
    val recommended: List<BenefitDisclosure>,
    val nudges: List<CrossCardNudge>
)

enum class BenefitContextKind(val rawValue: String) {
    FLIGHT("flight"),
    TRIP("trip"),
    CAR_RENTAL("carRental"),
    ELECTRONICS("electronics"),
    MOBILE_DEVICE("mobileDevice"),
    APPLIANCE_FURNITURE("applianceFurniture")
}

data class BenefitContext(
    val kind: BenefitContextKind,
    val abroad: Boolean = false
) {
    val relevantKinds: List<BenefitKind>
        get() {
            val base: List<BenefitKind> = when (kind) {
                BenefitContextKind.FLIGHT, BenefitContextKind.TRIP -> listOf(
                    BenefitKind.FLIGHT_DELAY,
                    BenefitKind.BAGGAGE_DELAY,
                    BenefitKind.BAGGAGE_LOSS,
                    BenefitKind.TRIP_CANCELLATION,
                    BenefitKind.TRIP_INTERRUPTION
                )
                BenefitContextKind.CAR_RENTAL -> listOf(BenefitKind.RENTAL_CDW)
                BenefitContextKind.ELECTRONICS, BenefitContextKind.APPLIANCE_FURNITURE -> listOf(
                    BenefitKind.PURCHASE_PROTECTION,
                    BenefitKind.EXTENDED_WARRANTY
                )
                BenefitContextKind.MOBILE_DEVICE -> listOf(
                    BenefitKind.PURCHASE_PROTECTION,
                    BenefitKind.EXTENDED_WARRANTY,
                    BenefitKind.MOBILE_DEVICE_INSURANCE
                )
            }
            return if (abroad) base + listOf(BenefitKind.TRAVEL_MEDICAL) else base
        }
}

data class ProtectionComparison(
    val relevantKinds: List<BenefitKind>,
    val columns: List<Column>,
    val absent: List<AbsentCard>,
    val dominantCardId: String?
) {
    data class Column(
        val cardId: String,
        val verification: BenefitVerification,
        val byKind: Map<String, BenefitDisclosure>
    )

    data class AbsentCard(
        val cardId: String,
        val verification: BenefitVerification
    )
}

object BenefitsAdvisor {
    fun disclosures(
        purchase: PurchaseContext,
        recommendedCardId: String,
        wallet: List<String>,
        catalogue: BenefitsCatalogue
    ): DisclosureResult {
        val families = triggeredFamilies(purchase, catalogue.triggers)
        if (families.isEmpty()) return DisclosureResult(emptyList(), emptyList())

        val recommended = relevantBenefits(recommendedCardId, families, catalogue)
        val recommendedKinds = recommended.map { it.kind }.toSet()

        val nudges = mutableListOf<CrossCardNudge>()
        val nudgedKinds = mutableSetOf<String>()

        for (cardId in wallet) {
            if (cardId == recommendedCardId) continue
            for (disclosure in relevantBenefits(cardId, families, catalogue)) {
                if (!recommendedKinds.contains(disclosure.kind) && !nudgedKinds.contains(disclosure.kind)) {
                    nudges.add(CrossCardNudge(cardId, disclosure.kind))
                    nudgedKinds.add(disclosure.kind)
                }
            }
        }

        return DisclosureResult(recommended, nudges)
    }

    fun triggeredFamilies(purchase: PurchaseContext, triggers: BenefitsTriggers): Set<BenefitFamily> {
        val families = mutableSetOf<BenefitFamily>()
        if (purchase.amountCad >= triggers.bigTicketThresholdCad && !triggers.consumableCategories.contains(purchase.category)) {
            families.add(BenefitFamily.SHOPPING)
        }
        if (purchase.category == "hotel" || purchase.country != "CA" || purchase.currency != "CAD") {
            families.add(BenefitFamily.TRAVEL_DISRUPTION)
            families.add(BenefitFamily.TRAVEL_MEDICAL)
        }
        return families
    }

    fun relevantBenefits(
        cardId: String,
        families: Set<BenefitFamily>,
        catalogue: BenefitsCatalogue
    ): List<BenefitDisclosure> {
        val card = catalogue.card(cardId) ?: return emptyList()
        return card.benefits.mapNotNull { benefit ->
            val fam = benefit.knownFamily ?: return@mapNotNull null
            if (benefit.knownKind == null || !families.contains(fam)) return@mapNotNull null
            disclosure(benefit, cardId, card.certificate.verificationStatus)
        }
    }

    fun disclosure(
        benefit: Benefit,
        cardId: String,
        verification: BenefitVerification
    ): BenefitDisclosure {
        return BenefitDisclosure(
            cardId = cardId,
            kind = benefit.kind,
            coverage = benefit.coverage,
            conditions = benefit.conditions,
            exclusions = benefit.exclusions ?: emptyList(),
            verification = verification
        )
    }

    fun comparison(
        context: BenefitContext,
        wallet: List<String>,
        catalogue: BenefitsCatalogue
    ): ProtectionComparison {
        val kinds = context.relevantKinds
        val kindKeys = kinds.map { it.rawValue }.toSet()

        val columns = mutableListOf<ProtectionComparison.Column>()
        val absent = mutableListOf<ProtectionComparison.AbsentCard>()

        for (cardId in wallet) {
            val card = catalogue.card(cardId) ?: continue
            val relevant = card.benefits.filter {
                it.knownKind != null && kindKeys.contains(it.kind)
            }
            if (relevant.isEmpty()) {
                absent.add(ProtectionComparison.AbsentCard(cardId, card.certificate.verificationStatus))
            } else {
                val byKind = mutableMapOf<String, BenefitDisclosure>()
                for (b in relevant) {
                    if (!byKind.containsKey(b.kind)) {
                        byKind[b.kind] = disclosure(b, cardId, card.certificate.verificationStatus)
                    }
                }
                columns.add(
                    ProtectionComparison.Column(
                        cardId = cardId,
                        verification = card.certificate.verificationStatus,
                        byKind = byKind
                    )
                )
            }
        }

        return ProtectionComparison(
            relevantKinds = kinds,
            columns = columns,
            absent = absent,
            dominantCardId = dominant(columns, kinds)
        )
    }

    private data class FieldSpec(
        val name: String,
        val lowerIsBetter: Boolean,
        val value: (BenefitCoverage) -> Double?
    )

    private val fieldSpecs: List<FieldSpec> = listOf(
        FieldSpec("windowDays", false) { it.windowDays?.toDouble() },
        FieldSpec("maxPerOccurrenceCad", false) { it.maxPerOccurrenceCad },
        FieldSpec("maxAnnualCad", false) { it.maxAnnualCad },
        FieldSpec("extraYears", false) { it.extraYears?.toDouble() },
        FieldSpec("maxCad", false) { it.maxCad },
        FieldSpec("deductibleCad", true) { it.deductibleCad },
        FieldSpec("delayHours", true) { it.delayHours?.toDouble() },
        FieldSpec("perDayCad", false) { it.perDayCad },
        FieldSpec("maxTripLengthDays", false) { it.maxTripLengthDays?.toDouble() },
        FieldSpec("maxRentalDays", false) { it.maxRentalDays?.toDouble() },
        FieldSpec("maxVehicleValueCad", false) { it.maxVehicleValueCad },
        FieldSpec("ageLimit", false) { it.ageLimit?.toDouble() }
    )

    private fun dominant(
        columns: List<ProtectionComparison.Column>,
        kinds: List<BenefitKind>
    ): String? {
        if (columns.isEmpty()) return null

        val rows = mutableListOf<List<Double>>()
        for (kind in kinds) {
            for (spec in fieldSpecs) {
                val raw: List<Double?> = columns.map { col ->
                    col.byKind[kind.rawValue]?.let { spec.value(it.coverage) }
                }
                if (raw.none { it != null }) continue
                rows.add(
                    raw.map { value ->
                        if (value == null) {
                            Double.NEGATIVE_INFINITY
                        } else {
                            if (spec.lowerIsBetter) -value else value
                        }
                    }
                )
            }
        }

        for (kind in kinds) {
            val presence = columns.map { if (it.byKind[kind.rawValue] != null) 1.0 else Double.NEGATIVE_INFINITY }
            if (presence.contains(1.0)) {
                rows.add(presence)
            }
        }

        if (rows.isEmpty()) return null

        fun dominates(a: Int, b: Int): Boolean {
            var strictlyBetterSomewhere = false
            for (row in rows) {
                if (row[a] < row[b]) return false
                if (row[a] > row[b]) strictlyBetterSomewhere = true
            }
            return strictlyBetterSomewhere
        }

        val maximal = columns.indices.filter { candidate ->
            !columns.indices.any { other ->
                other != candidate && dominates(other, candidate)
            }
        }

        if (maximal.size != 1) return null
        return columns[maximal[0]].cardId
    }
}
