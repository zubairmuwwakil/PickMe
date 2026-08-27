package com.cardcopilot.engine.models

enum class Cadence(val chargesPerYear: Double) {
    WEEKLY(52.0),
    BIWEEKLY(26.0),
    MONTHLY(12.0),
    QUARTERLY(4.0),
    SEMI_ANNUAL(2.0),
    ANNUAL(1.0)
}

sealed interface Placement {
    data class Card(val cardId: String) : Placement
    data object OffWallet : Placement
    data object Unknown : Placement
}

enum class RecurringFlagStatus {
    ASSUMED,
    CONFIRMED,
    REFUTED
}

data class RecurringPayment(
    val id: String,
    val label: String,
    val amountCad: Double,
    val cadence: Cadence,
    val category: String,
    val mcc: Int? = null,
    val merchantBrand: String? = null,
    val currency: String = "CAD",
    val placement: Placement,
    val declaredAcceptedNetworks: Set<Network>? = null,
    val flagStatus: RecurringFlagStatus = RecurringFlagStatus.ASSUMED,
    val nextChargeMonth: String? = null
) {
    val annualCad: Double get() = amountCad * cadence.chargesPerYear

    val effectiveAcceptedNetworks: Set<Network>
        get() = declaredAcceptedNetworks ?: setOf(Network.AMEX, Network.VISA, Network.MASTERCARD, Network.DISCOVER)
}

data class RecurringPlan(
    val planId: String,
    val basis: String,
    val payments: List<RecurringPayment>
) {
    val totalAnnualCad: Double get() = payments.sumOf { it.annualCad }

    fun asSpendDistribution(profileId: String? = null): SpendDistribution {
        return SpendDistribution(
            profileId = profileId ?: planId,
            basis = "DECLARED recurring bills (the owner's own figures, not a spend estimate): $basis",
            buckets = payments.map { payment ->
                SpendDistribution.Bucket(
                    label = payment.label,
                    annualCad = payment.annualCad,
                    category = payment.category,
                    mcc = payment.mcc ?: RecurringCategoryDefaults.representativeMcc[payment.category],
                    merchantBrand = payment.merchantBrand,
                    currency = payment.currency,
                    channel = "online",
                    recurring = payment.flagStatus != RecurringFlagStatus.REFUTED,
                    acceptedNetworks = payment.effectiveAcceptedNetworks
                )
            }
        )
    }

    companion object {
        val placeholderSubscriptions = RecurringPlan(
            planId = "placeholder-subscriptions-2026",
            basis = "ASSUMPTION (2026-08-16): no subscription list has been captured yet. Amounts are " +
                "a plausible Canadian household's recurring bills, not declared data.",
            payments = listOf(
                RecurringPayment(id = "netflix", label = "Netflix", amountCad = 16.99, cadence = Cadence.MONTHLY, category = "streaming", placement = Placement.Card("wealthsimple-vip")),
                RecurringPayment(id = "icloud", label = "iCloud storage", amountCad = 12.99, cadence = Cadence.MONTHLY, category = "digitalMedia", placement = Placement.Card("wealthsimple-vip")),
                RecurringPayment(id = "phone", label = "Phone", amountCad = 85.0, cadence = Cadence.MONTHLY, category = "householdUtilities", mcc = 4814, placement = Placement.Card("wealthsimple-vip")),
                RecurringPayment(id = "internet", label = "Internet", amountCad = 95.0, cadence = Cadence.MONTHLY, category = "householdUtilities", mcc = 4814, placement = Placement.Card("scotia-momentum-vi-plus")),
                RecurringPayment(id = "gym", label = "Gym membership", amountCad = 59.0, cadence = Cadence.MONTHLY, category = "memberships", mcc = 7997, placement = Placement.Card("wealthsimple-vip")),
                RecurringPayment(id = "home-auto-insurance", label = "Home & auto insurance", amountCad = 210.0, cadence = Cadence.MONTHLY, category = "recurring", mcc = 6300, placement = Placement.OffWallet),
                RecurringPayment(id = "life-insurance", label = "Term life insurance", amountCad = 45.0, cadence = Cadence.MONTHLY, category = "recurring", mcc = 6300, placement = Placement.OffWallet),
                RecurringPayment(id = "costco-membership", label = "Costco membership", amountCad = 65.0, cadence = Cadence.ANNUAL, category = "wholesaleClub", merchantBrand = "costco", placement = Placement.Card("rogers-red-we"), declaredAcceptedNetworks = setOf(Network.MASTERCARD), nextChargeMonth = "2026-11")
            )
        )
    }
}

object RecurringCategoryDefaults {
    val representativeMcc: Map<String, Int> = mapOf(
        "streaming" to 5968,
        "digitalMedia" to 5815,
        "memberships" to 7997,
        "householdUtilities" to 4814,
        "recurring" to 6300,
        "transit" to 4121,
        "foodDelivery" to 5814,
        "grocery" to 5411
    )
}
