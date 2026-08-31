package com.cardcopilot.engine.engine

data class CapSplit(val inCap: Double, val overCap: Double)
data class CapInput(val limit: Double, val usage: Double)

object CapMath {
    fun split(amount: Double, capLimit: Double, usage: Double): CapSplit {
        val room = maxOf(0.0, capLimit - usage)
        val inCap = minOf(amount, room)
        return CapSplit(inCap, amount - inCap)
    }

    /** The cap with the least remaining room constrains the accelerated portion. */
    fun splitMulti(amount: Double, caps: List<CapInput>): CapSplit {
        val minRoom = caps.minOfOrNull { maxOf(0.0, it.limit - it.usage) }
            ?: Double.POSITIVE_INFINITY
        val inCap = minOf(amount, minRoom)
        return CapSplit(inCap, amount - inCap)
    }
}
