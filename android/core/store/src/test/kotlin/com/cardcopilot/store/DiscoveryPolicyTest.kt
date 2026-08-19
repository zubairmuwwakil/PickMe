package com.cardcopilot.store

import com.cardcopilot.store.models.NearbyMerchant
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class DiscoveryPolicyTest {

    @Test
    fun testCellKeyCalculation() {
        val key1 = DiscoveryPolicy.cellKey(43.6532, -79.3832)
        assertEquals("4365_-7939", key1)

        val key2 = DiscoveryPolicy.cellKey(43.6599, -79.3801)
        assertEquals("4365_-7939", key2)
    }

    @Test
    fun testSpeedCeilingSkipsWhenMovingFast() {
        val now = 1000000L
        val decision = DiscoveryPolicy.shouldQueryDiscovery(
            cellKey = "4365_-7939",
            cachedEntry = null,
            speedMetersPerSecond = 15.0, // fast driving
            recentQueryTimestamps = emptyList(),
            nowTimestamp = now
        )
        assertEquals(DiscoveryDecision.SkipMoving, decision)
    }

    @Test
    fun testDwellDecisions() {
        val enter = 1000000L
        val quickPass = enter + 60 * 1000 // 1 min -> walk by
        assertEquals(DwellOutcome.WALK_BY, DiscoveryPolicy.dwellDecision(enter, quickPass, didEngage = true))

        val realDwell = enter + 10 * 60 * 1000 // 10 min
        assertEquals(DwellOutcome.PROMPT_FOR_AMOUNT, DiscoveryPolicy.dwellDecision(enter, realDwell, didEngage = true))
        assertEquals(DwellOutcome.SILENT_VISIT, DiscoveryPolicy.dwellDecision(enter, realDwell, didEngage = false))
    }

    @Test
    fun testClusteringPOIs() {
        val m1 = NearbyMerchant("1", "Store A", null, 43.6532, -79.3832)
        val m2 = NearbyMerchant("2", "Store B", null, 43.6533, -79.3833) // ~15m away
        val m3 = NearbyMerchant("3", "Far Store", null, 43.6700, -79.4000) // ~2km away

        val areas = DiscoveryPolicy.clusterIntoAreas(listOf(m1, m2, m3))
        assertEquals(2, areas.size)
        assertTrue(areas.any { it.members.size == 2 })
        assertTrue(areas.any { it.members.size == 1 })
    }
}
