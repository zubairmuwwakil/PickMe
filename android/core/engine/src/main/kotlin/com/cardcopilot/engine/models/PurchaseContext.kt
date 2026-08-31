package com.cardcopilot.engine.models

import kotlinx.serialization.Serializable

@Serializable
data class PurchaseContext(
    var amountCad: Double,
    val currency: String = "CAD",
    val usdEquivalent: Double? = null,
    val category: String,
    val mcc: Int? = null,
    val merchantBrand: String? = null,
    val country: String = "CA",
    val channel: String = "cardPresent",
    val recurringIndicator: Boolean = false,
    val acceptedNetworks: Set<Network> = setOf(Network.AMEX, Network.VISA, Network.MASTERCARD, Network.DISCOVER)
) {
    fun canonicalized(): PurchaseContext = copy(category = CategoryTaxonomy.canonicalId(category))
}
