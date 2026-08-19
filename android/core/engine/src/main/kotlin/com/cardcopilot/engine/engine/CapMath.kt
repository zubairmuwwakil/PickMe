package com.cardcopilot.engine.engine

data class CapSplit(val inCap: Double, val overCap: Double)

object CapMath {
    fun split(amount: Double, capLimit: Double, usage: Double): CapSplit {
        val room = maxOf(0.0, capLimit - usage)
        val inCap = minOf(amount, room)
        return CapSplit(inCap, amount - inCap)
    }
}
