package com.cardcopilot.store

import com.cardcopilot.store.models.NearbyPlace

interface MerchantProvider {
    suspend fun nearby(latitude: Double, longitude: Double): List<NearbyPlace>
    suspend fun search(text: String): List<NearbyPlace>
}

object MerchantRanking {
    fun rankNearbyPlaces(merchants: List<NearbyPlace>): List<NearbyPlace> {
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
        val deduped = mutableListOf<NearbyPlace>()
        for (m in sorted) {
            if (seenIds.add(m.id)) {
                deduped.add(m)
            }
        }
        return deduped
    }
}
