package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.Cadence
import com.cardcopilot.engine.models.CapMeasure
import com.cardcopilot.engine.models.CardProduct
import com.cardcopilot.engine.models.CardState
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.PurchaseContext
import com.cardcopilot.engine.models.RecurringCategoryDefaults
import com.cardcopilot.engine.models.RecurringFlagStatus
import com.cardcopilot.engine.models.RecurringPayment

data class PlacedPayment(
    val payment: RecurringPayment,
    val cardId: String,
    val assumeFlagged: Boolean
)

data class MonthlyBurn(
    val month: String,
    val burnCad: Double,
    val cumulativeCad: Double
)

enum class ProjectionBasis {
    DECLARED_RECURRING_ONLY
}

data class CapContention(
    val capId: String,
    val roomCad: Double,
    val declaredDemandCad: Double,
    val competingCategories: List<String>
)

sealed interface CapCoverage {
    data class Categories(val categories: List<String>) : CapCoverage
    data object AllSpendOnCard : CapCoverage
}

data class CapProjection(
    val cardId: String,
    val capId: String,
    val limitCad: Double,
    val window: CapWindow.Window,
    val startingUsageCad: Double,
    val startingUsageIsAnchored: Boolean,
    val monthlyBurn: List<MonthlyBurn>,
    val cumulativeAtWindowEndCad: Double,
    val crossingMonth: String?,
    val basis: ProjectionBasis,
    val coverage: CapCoverage,
    val undeclaredCategories: List<String>,
    val restsOnAssumedFlags: Boolean,
    val contention: CapContention?
)

sealed interface CapProjectionOutcome {
    data class Projected(val projection: CapProjection) : CapProjectionOutcome
    data class Refused(val cardId: String, val capId: String, val reason: String) : CapProjectionOutcome
}

class CapProjector(
    val catalogue: Catalogue,
    val ownerState: OwnerState
) {
    data class CapKey(
        val cardId: String,
        val capId: String
    ) : Comparable<CapKey> {
        override fun compareTo(other: CapKey): Int {
            val c = cardId.compareTo(other.cardId)
            return if (c != 0) c else capId.compareTo(other.capId)
        }
    }

    fun project(
        placements: List<PlacedPayment>,
        asOf: String,
        capProgressAsOf: String? = null
    ): List<CapProjectionOutcome> {
        val burnsByCap = mutableMapOf<CapKey, MutableList<PlacedPayment>>()
        for (placement in placements) {
            val key = capBurned(placement, asOf) ?: continue
            burnsByCap.getOrPut(key) { mutableListOf() }.add(placement)
        }

        return burnsByCap.keys.sorted().mapNotNull { key ->
            outcome(key, burnsByCap[key] ?: emptyList(), asOf, capProgressAsOf)
        }
    }

    private fun capBurned(placement: PlacedPayment, asOf: String): CapKey? {
        val capId = capId(placement, placement.assumeFlagged, asOf) ?: return null
        return CapKey(placement.cardId, capId)
    }

    private fun flagIsLoadBearing(placement: PlacedPayment, capId: String, asOf: String): Boolean {
        if (!placement.assumeFlagged) return false
        return this.capId(placement, false, asOf) != capId
    }

    private fun capId(placement: PlacedPayment, flagged: Boolean, asOf: String): String? {
        val card = catalogue.cards.firstOrNull { it.cardId == placement.cardId } ?: return null
        val purchase = context(placement).copy(recurringIndicator = flagged)
        val res = RuleMatcher.resolve(card, purchase, ownerState, asOf)
        return if (res is RuleResolution.Applied) res.rule.capId else null
    }

    private fun context(placement: PlacedPayment): PurchaseContext {
        val payment = placement.payment
        return PurchaseContext(
            amountCad = payment.amountCad,
            currency = payment.currency,
            category = payment.category,
            mcc = payment.mcc ?: RecurringCategoryDefaults.representativeMcc[payment.category],
            merchantBrand = payment.merchantBrand,
            channel = "online",
            recurringIndicator = placement.assumeFlagged,
            acceptedNetworks = payment.effectiveAcceptedNetworks
        )
    }

    private fun outcome(
        key: CapKey,
        placements: List<PlacedPayment>,
        asOf: String,
        capProgressAsOf: String?
    ): CapProjectionOutcome? {
        val card = catalogue.cards.firstOrNull { it.cardId == key.cardId } ?: return null
        val cap = card.caps.firstOrNull { it.capId == key.capId } ?: return null

        val window = CapWindow.resolve(cap, card.cardId, ownerState, asOf)
            ?: return CapProjectionOutcome.Refused(
                cardId = key.cardId,
                capId = key.capId,
                reason = "account-year anchor unresolved — set ${cap.anchor ?: "the cap's anchor"} in owner state"
            )

        val start = maxOf(CapWindow.monthIndex(asOf), CapWindow.monthIndex(window.startMonth))
        val end = CapWindow.monthIndex(window.endMonth)
        val monthCount = maxOf(0, end - start + 1)
        val burnByMonth = DoubleArray(monthCount)

        for (placement in placements) {
            for ((month, amount) in burnSchedule(placement.payment, start, end)) {
                if (month in start..end) {
                    burnByMonth[month - start] += amount
                }
            }
        }

        val startingUsage = ownerState.cardStates[key.cardId]?.capProgress?.get(key.capId) ?: 0.0
        var cumulative = startingUsage
        var crossingMonth: String? = null
        val monthly = mutableListOf<MonthlyBurn>()

        for (offset in 0 until monthCount) {
            val burn = burnByMonth[offset]
            cumulative += burn
            val month = CapWindow.month(start + offset)
            if (crossingMonth == null && cumulative > cap.limit) {
                crossingMonth = month
            }
            monthly.add(MonthlyBurn(month = month, burnCad = burn, cumulativeCad = cumulative))
        }

        val coverage = coverage(card, key.capId)
        val declared = placements.map { it.payment.category }.toSet()
        val undeclared = when (coverage) {
            is CapCoverage.Categories -> coverage.categories.filter { !declared.contains(it) }
            is CapCoverage.AllSpendOnCard -> emptyList()
        }
        val demand = burnByMonth.sum()
        val room = maxOf(0.0, cap.limit - startingUsage)

        return CapProjectionOutcome.Projected(
            CapProjection(
                cardId = key.cardId,
                capId = key.capId,
                limitCad = cap.limit,
                window = window,
                startingUsageCad = startingUsage,
                startingUsageIsAnchored = capProgressAsOf != null,
                monthlyBurn = monthly,
                cumulativeAtWindowEndCad = cumulative,
                crossingMonth = crossingMonth,
                basis = ProjectionBasis.DECLARED_RECURRING_ONLY,
                coverage = coverage,
                undeclaredCategories = undeclared,
                restsOnAssumedFlags = placements.any {
                    it.payment.flagStatus == RecurringFlagStatus.ASSUMED && flagIsLoadBearing(it, key.capId, asOf)
                },
                contention = if (demand > room) {
                    CapContention(
                        capId = key.capId,
                        roomCad = room,
                        declaredDemandCad = demand,
                        competingCategories = when (coverage) {
                            is CapCoverage.Categories -> coverage.categories
                            is CapCoverage.AllSpendOnCard -> emptyList()
                        }
                    )
                } else null
            )
        )
    }

    private fun coverage(card: CardProduct, capId: String): CapCoverage {
        val rules = card.earnRules.filter { it.capId == capId }
        if (!rules.all { it.predicate.categories != null }) return CapCoverage.AllSpendOnCard
        val categories = rules.flatMap { it.predicate.categories ?: emptyList() }.toSet().toList().sorted()
        return CapCoverage.Categories(categories)
    }

    private fun burnSchedule(
        payment: RecurringPayment,
        from: Int,
        to: Int
    ): List<Pair<Int, Double>> {
        if (to < from) return emptyList()
        val interval = monthsBetweenCharges(payment.cadence)
        if (interval == null) {
            val perMonth = payment.amountCad * payment.cadence.chargesPerYear / 12.0
            return (from..to).map { Pair(it, perMonth) }
        }

        val months = mutableListOf<Pair<Int, Double>>()
        if (payment.nextChargeMonth != null) {
            var month = CapWindow.monthIndex(payment.nextChargeMonth)
            while (month < from) month += interval
            while (month <= to) {
                months.add(Pair(month, payment.amountCad))
                month += interval
            }
        } else {
            var month = to
            while (month >= from) {
                months.add(Pair(month, payment.amountCad))
                month -= interval
            }
        }
        return months
    }

    private fun monthsBetweenCharges(cadence: Cadence): Int? {
        return when (cadence) {
            Cadence.WEEKLY, Cadence.BIWEEKLY, Cadence.MONTHLY -> null
            Cadence.QUARTERLY -> 3
            Cadence.SEMI_ANNUAL -> 6
            Cadence.ANNUAL -> 12
        }
    }
}
