package com.cardcopilot.engine.models

data class SpendDistribution(
    val profileId: String,
    val basis: String,
    val buckets: List<Bucket>
) {
    data class Bucket(
        val label: String,
        val annualCad: Double,
        val context: PurchaseContext
    ) {
        constructor(
            label: String,
            annualCad: Double,
            category: String,
            mcc: Int? = null,
            merchantBrand: String? = null,
            currency: String = "CAD",
            usdEquivalent: Double? = null,
            country: String = "CA",
            channel: String = "cardPresent",
            recurring: Boolean = false,
            acceptedNetworks: Set<Network> = setOf(Network.AMEX, Network.VISA, Network.MASTERCARD, Network.DISCOVER)
        ) : this(
            label = label,
            annualCad = annualCad,
            context = PurchaseContext(
                amountCad = annualCad,
                currency = currency,
                usdEquivalent = usdEquivalent,
                category = category,
                mcc = mcc,
                merchantBrand = merchantBrand,
                country = country,
                channel = channel,
                recurringIndicator = recurring,
                acceptedNetworks = acceptedNetworks
            )
        )
    }

    val totalAnnualCad: Double get() = buckets.sumOf { it.annualCad }

    fun scaled(factor: Double, profileId: String): SpendDistribution {
        return SpendDistribution(
            profileId = profileId,
            basis = "$basis × $factor",
            buckets = buckets.map {
                Bucket(label = it.label, annualCad = it.annualCad * factor, context = it.context)
            }
        )
    }

    companion object {
        val placeholderCanadianHousehold = SpendDistribution(
            profileId = "placeholder-canadian-household-2026",
            basis = "ASSUMPTION (2026-08-15): no spend history exists yet. Category totals are a " +
                "documented guess at a ~$40,200 single-household year, not measured data.",
            buckets = listOf(
                Bucket(label = "Groceries", annualCad = 9000.0, category = "grocery", mcc = 5411, merchantBrand = "loblaws"),
                Bucket(label = "Restaurants & coffee", annualCad = 4200.0, category = "dining", mcc = 5812),
                Bucket(label = "Food delivery", annualCad = 900.0, category = "foodDelivery", mcc = 5814, channel = "online"),
                Bucket(label = "Streaming", annualCad = 600.0, category = "streaming", mcc = 5968, channel = "online", recurring = true),
                Bucket(label = "Digital media & apps", annualCad = 300.0, category = "digitalMedia", mcc = 5815, channel = "online"),
                Bucket(label = "Memberships & dues", annualCad = 600.0, category = "memberships", mcc = 7997, recurring = true),
                Bucket(label = "Phone & internet", annualCad = 1800.0, category = "householdUtilities", mcc = 4814, recurring = true),
                Bucket(label = "Insurance premiums", annualCad = 2400.0, category = "recurring", mcc = 6300, recurring = true),
                Bucket(label = "Gas", annualCad = 2400.0, category = "gasStation", mcc = 5541),
                Bucket(label = "Transit & rideshare", annualCad = 1200.0, category = "transit", mcc = 4121),
                Bucket(label = "Flights", annualCad = 1800.0, category = "travel", mcc = 3000, channel = "online"),
                Bucket(label = "Hotels (non-Marriott)", annualCad = 1200.0, category = "lodging", mcc = 3501, channel = "online"),
                Bucket(label = "Marriott stays", annualCad = 1200.0, category = "marriottDirect", mcc = 3509, merchantBrand = "marriott"),
                Bucket(label = "Costco", annualCad = 2600.0, category = "wholesaleClub", mcc = 5300, merchantBrand = "costco", acceptedNetworks = setOf(Network.MASTERCARD)),
                Bucket(label = "Canadian Tire family", annualCad = 1200.0, category = "ctFamily", mcc = 5200, merchantBrand = "canadian-tire"),
                Bucket(label = "Foreign currency (USD online)", annualCad = 2000.0, category = "other", currency = "USD", channel = "online"),
                Bucket(label = "Everything else", annualCad = 6800.0, category = "other")
            )
        )
    }
}
