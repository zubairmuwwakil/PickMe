package com.cardcopilot.engine.engine

import com.cardcopilot.engine.models.Cap
import com.cardcopilot.engine.models.CapPeriod
import com.cardcopilot.engine.models.OwnerState
import java.util.Locale

object CapWindow {
    data class Window(
        val startMonth: String,
        val endMonth: String
    )

    fun resolve(
        cap: Cap,
        cardId: String,
        ownerState: OwnerState,
        asOf: String
    ): Window? {
        val asOfIndex = monthIndex(asOf)
        return when (cap.period) {
            CapPeriod.CALENDAR_MONTH -> {
                Window(startMonth = month(asOfIndex), endMonth = month(asOfIndex))
            }
            CapPeriod.CALENDAR_QUARTER -> {
                val quarterStart = (asOfIndex / 3) * 3
                Window(startMonth = month(quarterStart), endMonth = month(quarterStart + 2))
            }
            CapPeriod.CALENDAR_YEAR -> {
                val january = (asOfIndex / 12) * 12
                Window(startMonth = month(january), endMonth = month(january + 11))
            }
            CapPeriod.ACCOUNT_YEAR -> {
                val anchor = anchorMonth(cap, cardId, ownerState) ?: return null
                val asOfMonth = asOfIndex % 12 + 1
                val startYear = if (asOfMonth >= anchor) asOfIndex / 12 else asOfIndex / 12 - 1
                val start = startYear * 12 + anchor - 1
                Window(startMonth = month(start), endMonth = month(start + 11))
            }
        }
    }

    private fun anchorMonth(cap: Cap, cardId: String, ownerState: OwnerState): Int? {
        val state = ownerState.cardStates[cardId]
        return when (cap.anchor) {
            "ownerState.scotiaAccountYearAnchorMonth" -> state?.scotiaAccountYearAnchorMonth
            "ownerState.rogersAccountAnniversaryMonth" -> state?.rogersAccountAnniversaryMonth
            else -> null
        }
    }

    fun monthIndex(isoDate: String): Int {
        val parts = isoDate.split("-").mapNotNull { it.toIntOrNull() }
        if (parts.size < 2) return 0
        return parts[0] * 12 + parts[1] - 1
    }

    fun month(index: Int): String {
        return String.format(Locale.US, "%04d-%02d", index / 12, index % 12 + 1)
    }
}
