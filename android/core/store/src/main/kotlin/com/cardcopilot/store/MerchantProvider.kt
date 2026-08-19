package com.cardcopilot.store

import com.cardcopilot.store.models.NearbyMerchant

interface MerchantProvider {
    suspend fun nearby(latitude: Double, longitude: Double): List<NearbyMerchant>
    suspend fun search(text: String): List<NearbyMerchant>
}

object MerchantRanking {
    fun rankNearbyMerchants(merchants: List<NearbyMerchant>): List<NearbyMerchant> {
        val sorted = merchants.sortedWith { a, b ->
            val distA = a.distanceMeters
            val distB = b.distanceMeters
            when {
                distA != null && distB != null && distA != distB -> distA.compareTo(distB)
                distA == null && distB != null -> 1
                distA != null && distB == null -> -1
                else -> a.name.compareTo(b.name, ignoreCase = true)
            }
        }

        val seenIds = mutableSetOf<String>()
        val deduped = mutableListOf<NearbyMerchant>()
        for (m in sorted) {
            if (seenIds.add(m.id)) {
                deduped.add(m)
            }
        }
        return deduped
    }
}
