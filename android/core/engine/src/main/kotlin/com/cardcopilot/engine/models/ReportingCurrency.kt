package com.cardcopilot.engine.models

import com.cardcopilot.engine.engine.Scorer

/**
 * Converts a [Money] value into the engine's fixed reporting currency.
 *
 * Mirrors the Swift twin (`Engine/Sources/CardCopilotEngine/Models/ReportingCurrency.swift`) —
 * see its doc comment for the full reasoning. In short: this engine reports every cross-card
 * number in CAD regardless of a card's own `market`/`billingCurrency`, so a USD fee (or a
 * USD-valued program, later) needs to become one CAD number before it can be combined with a CAD
 * one. The rate is pinned, not live — this repo does not own market data.
 */
object ReportingCurrency {
    val reportingCurrency: Currency = Currency.CAD

    /** == 1 / Scorer.FALLBACK_CAD_TO_USD, kept as one pinned reference rather than two. */
    val pinnedUsdToCad: Double = 1.0 / Scorer.FALLBACK_CAD_TO_USD

    /** [money]'s amount, converted to the reporting currency. `null` reports as 0.0. */
    fun toReporting(money: Money?): Double {
        if (money == null) return 0.0
        return when (money.currency) {
            Currency.CAD -> money.amount
            Currency.USD -> money.amount * pinnedUsdToCad
        }
    }
}
