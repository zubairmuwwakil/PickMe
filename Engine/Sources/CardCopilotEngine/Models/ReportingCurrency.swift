import Foundation

/// Converts a `Money` value into the engine's fixed reporting currency.
///
/// This engine reports every cross-card number — `CandidateScore.netValueCad`,
/// `AcquisitionCandidate.annualFeeCad`, `PortfolioAnalyzer`'s totals — in CAD, regardless of any
/// individual card's `market` or `billingCurrency`. That choice is unchanged by the multi-market
/// catalogue: a USD annual fee or a USD-valued program still needs to become one CAD number before
/// it can be combined with a CAD one ("a price without a currency must not be summed" — the same
/// rule MoneyTalks' `Holding.priceCurrency` follows). This is where that conversion happens, and
/// ONLY where it happens — a catalogue `Money` value itself is never rewritten into CAD.
///
/// The rate is pinned, not live: this repo does not own market data (ECOSYSTEM.md), and a
/// portfolio-level "roughly how much is this US fee in CAD terms" figure does not need a fresh
/// quote to be useful, only an honest one. It reuses `Scorer.fallbackCadToUsd` exactly (inverted)
/// rather than inventing a second pinned constant that could drift from the first.
public enum ReportingCurrency {
    public static let reportingCurrency: Currency = .cad

    /// == 1 / Scorer.fallbackCadToUsd, kept as one pinned reference rather than two that could
    /// silently diverge. Refreshed by catalogue release, never at runtime.
    public static let pinnedUsdToCad = 1 / Scorer.fallbackCadToUsd

    /// `money`'s amount, converted to the reporting currency. `nil` reports as 0, matching the
    /// `?? 0` callers used before `Fee.annual`/`monthly` existed.
    public static func toReporting(_ money: Money?) -> Double {
        guard let money else { return 0 }
        switch money.currency {
        case reportingCurrency:
            return money.amount
        case .usd:
            return money.amount * pinnedUsdToCad
        }
    }
}
