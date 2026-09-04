package com.cardcopilot.store

import com.cardcopilot.store.models.NearbyPlace
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin
import kotlin.math.sqrt

data class DiscoveryCacheEntry(
    val cellKey: String,
    val exploredAtTimestamp: Long,
    val areaCount: Int
)

sealed interface DiscoveryDecision {
    data object Query : DiscoveryDecision
    data object SkipMoving : DiscoveryDecision
    data class SkipCached(val areaCount: Int) : DiscoveryDecision
    data object SkipRateLimited : DiscoveryDecision
}

enum class DwellOutcome {
    WALK_BY,
    SILENT_VISIT,
    PROMPT_FOR_AMOUNT,
    STRANDED
}

data class ShoppingAreaCandidate(
    val centroidLatitude: Double,
    val centroidLongitude: Double,
    val radiusMeters: Double,
    val members: List<NearbyPlace>
)

object DiscoveryPolicy {
    const val DISCOVERY_CELL_DEGREES: Double = 0.01
    const val DISCOVERY_SPEED_CEILING_METERS_PER_SECOND: Double = 8.0 // ~29 km/h
    const val DISCOVERY_CACHE_TTL_MS: Long = 30L * 24 * 60 * 60 * 1000 // 30 days
    const val DISCOVERY_HOURLY_QUERY_CEILING: Int = 6

    const val MINIMUM_SHOPPING_DWELL_MS: Long = 4 * 60 * 1000 // 4 mins
    const val MAXIMUM_PLAUSIBLE_DWELL_MS: Long = 6 * 60 * 60 * 1000 // 6 hours

    const val AREA_CLUSTER_RADIUS_METERS: Double = 200.0
    const val MINIMUM_AREA_RADIUS_METERS: Double = 100.0
    const val MAXIMUM_AREA_RADIUS_METERS: Double = 400.0

    fun cellKey(latitude: Double, longitude: Double): String {
        val latIndex = floor(latitude / DISCOVERY_CELL_DEGREES).toInt()
        val lonIndex = floor(longitude / DISCOVERY_CELL_DEGREES).toInt()
        return "${latIndex}_${lonIndex}"
    }

    fun shouldQueryDiscovery(
        cellKey: String,
        cachedEntry: DiscoveryCacheEntry?,
        speedMetersPerSecond: Double,
        recentQueryTimestamps: List<Long>,
        nowTimestamp: Long
    ): DiscoveryDecision {
        if (speedMetersPerSecond >= 0 && speedMetersPerSecond > DISCOVERY_SPEED_CEILING_METERS_PER_SECOND) {
            return DiscoveryDecision.SkipMoving
        }

        if (cachedEntry != null && cachedEntry.cellKey == cellKey &&
            (nowTimestamp - cachedEntry.exploredAtTimestamp) <= DISCOVERY_CACHE_TTL_MS
        ) {
            return DiscoveryDecision.SkipCached(cachedEntry.areaCount)
        }

        val windowStart = nowTimestamp - 3600 * 1000
        val recentCount = recentQueryTimestamps.count { it > windowStart }
        if (recentCount >= DISCOVERY_HOURLY_QUERY_CEILING) {
            return DiscoveryDecision.SkipRateLimited
        }

        return DiscoveryDecision.Query
    }

    fun dwellDecision(
        enteredAtTimestamp: Long,
        exitedAtTimestamp: Long,
        didEngage: Boolean
    ): DwellOutcome {
        val dwell = exitedAtTimestamp - enteredAtTimestamp
        if (dwell < 0 || dwell > MAXIMUM_PLAUSIBLE_DWELL_MS) return DwellOutcome.STRANDED
        if (dwell < MINIMUM_SHOPPING_DWELL_MS) return DwellOutcome.WALK_BY
        return if (didEngage) DwellOutcome.PROMPT_FOR_AMOUNT else DwellOutcome.SILENT_VISIT
    }

    fun greatCircleDistanceMeters(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ): Double {
        val earthRadius = 6371000.0
        val toRad = Math.PI / 180.0
        val dLat = (lat2 - lat1) * toRad
        val dLon = (lon2 - lon1) * toRad
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * toRad) * cos(lat2 * toRad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    fun clusterIntoAreas(merchants: List<NearbyPlace>): List<ShoppingAreaCandidate> {
        val ordered = merchants.sortedWith { a, b ->
            val latC = a.latitude.compareTo(b.latitude)
            if (latC != 0) return@sortedWith latC
            val lonC = a.longitude.compareTo(b.longitude)
            if (lonC != 0) return@sortedWith lonC
            a.id.compareTo(b.id)
        }

        var unassigned = ordered
        val areas = mutableListOf<ShoppingAreaCandidate>()

        while (unassigned.isNotEmpty()) {
            val seed = unassigned.first()
            val members = mutableListOf<NearbyPlace>()
            val remaining = mutableListOf<NearbyPlace>()

            for (candidate in unassigned) {
                val distance = greatCircleDistanceMeters(
                    seed.latitude, seed.longitude,
                    candidate.latitude, candidate.longitude
                )
                if (distance <= AREA_CLUSTER_RADIUS_METERS) {
                    members.add(candidate)
                } else {
                    remaining.add(candidate)
                }
            }
            unassigned = remaining

            val centroidLat = members.sumOf { it.latitude } / members.size
            val centroidLon = members.sumOf { it.longitude } / members.size
            val spread = members.maxOfOrNull {
                greatCircleDistanceMeters(centroidLat, centroidLon, it.latitude, it.longitude)
            } ?: 0.0

            val radius = minOf(
                maxOf(spread + MINIMUM_AREA_RADIUS_METERS / 2.0, MINIMUM_AREA_RADIUS_METERS),
                MAXIMUM_AREA_RADIUS_METERS
            )

            areas.add(
                ShoppingAreaCandidate(
                    centroidLatitude = centroidLat,
                    centroidLongitude = centroidLon,
                    radiusMeters = radius,
                    members = members
                )
            )
        }

        return areas
    }
}
