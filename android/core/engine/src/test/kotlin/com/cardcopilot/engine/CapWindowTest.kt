package com.cardcopilot.engine

import com.cardcopilot.engine.engine.CapWindow
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.Cap
import com.cardcopilot.engine.models.CapMeasure
import com.cardcopilot.engine.models.CapPeriod
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class CapWindowTest {
    @Test
    fun `statement year uses calendar-year bounds at monthly projection granularity`() {
        val cap = Cap(
            capId = "statement-year",
            measure = CapMeasure.SPEND_NATIVE,
            limit = 50_000.0,
            period = CapPeriod.STATEMENT_YEAR,
            resetTimeZone = "America/Toronto",
            proration = false,
        )

        assertEquals(
            CapWindow.Window(startMonth = "2026-01", endMonth = "2026-12"),
            CapWindow.resolve(
                cap = cap,
                cardId = "cibc-dividend-vi",
                ownerState = SeedLoader.loadOwnerState(),
                asOf = "2026-08-30",
            ),
        )
    }
}
