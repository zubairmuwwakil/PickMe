import Foundation

/// A contextual insight Chip can voice at checkout or on the home screen. Each case carries
/// the exact numbers the App layer needs to format a personalised, Chip-voiced quip — the
/// Engine never emits display strings, only typed facts.
///
/// Design: follows the same advisor pattern as `BenefitsAdvisor` and `CategoryPickerAdvisor`.
/// Every insight is derived from data the engine already computes (`Recommendation`,
/// `PurchaseContext`, `CandidateScore`), so no separate content database or freshness
/// tracking is needed — insights inherit the catalogue's own `lastVerifiedAt` provenance.
public enum ChipInsight: Equatable, Sendable {

    // MARK: - Tier 1: Derived from Recommendation signals

    /// The winning card's FX cost is eating a significant fraction of the gross reward.
    /// Threshold: fxCostCad > 40% of grossRewardCad AND fxCostCad > $0.10.
    case fxCostErosion(
        winnerCardId: String,
        fxCostCad: Double,
        grossRewardCad: Double,
        fxRate: Double
    )

    /// Every scored card would lose money after fees. The owner is better off using debit.
    case allCardsNegative

    /// The recommendation depends on the owner's declared point valuation — a different
    /// valuation would change the winner. Carries the exact breakeven for Chip to voice.
    case valuationSensitive(
        winnerCardId: String,
        declaredCentsPerPoint: Double,
        breakevenCentsPerPoint: Double,
        alternateCardId: String,
        direction: ValuationDirection
    )

    /// The winning card's category cap is nearly exhausted. After the cap, the runner-up
    /// may take over.
    case capNearlyExhausted(
        winnerCardId: String,
        runnerUpCardId: String?
    )

    /// A better card exists but the advantage is too small to justify switching. The engine
    /// suppressed it — Chip can acknowledge the user's default is "close enough."
    case marginalWinnerSuppressed(
        suppressedCardId: String,
        advantageCad: Double
    )

    /// The winner switched away from the owner's default card, and the advantage is
    /// material. Chip should emphasise the switch.
    case switchFromDefault(
        fromDefaultId: String,
        toWinnerId: String,
        advantageCad: Double
    )

    /// The purchase is in a foreign currency. Chip reminds the owner to decline Dynamic
    /// Currency Conversion at the terminal.
    case declineDcc(localCurrency: String)

    /// One or more cards were excluded because the merchant's network acceptance is
    /// restricted (e.g., Costco → Mastercard only). Chip explains the restriction.
    case networkRestricted(
        merchant: String?,
        requiredNetworks: Set<Network>,
        excludedCardCount: Int
    )
}

/// Priority bucket for ordering insights. Lower raw value = shown first.
extension ChipInsight {
    var priority: Int {
        switch self {
        case .allCardsNegative:             return 0 // "Don't tap anything" is urgent
        case .networkRestricted:            return 1 // Must-know before tapping
        case .declineDcc:                   return 2 // Action required at terminal
        case .switchFromDefault:            return 3 // "Switch cards" is the core product moment
        case .fxCostErosion:                return 4 // Worth knowing but not blocking
        case .capNearlyExhausted:           return 5 // Informational
        case .valuationSensitive:           return 6 // Educational
        case .marginalWinnerSuppressed:     return 7 // Nice-to-know
        }
    }
}

/// Computes contextual insights from a recommendation and its purchase context.
///
/// Follows the existing advisor pattern: pure, deterministic, no side effects, no UI strings.
/// The App layer is responsible for formatting insights into Chip's 4th-wall voice.
public enum ChipInsightAdvisor {

    /// Evaluate a recommendation and purchase to produce zero or more insights, ordered by
    /// priority. Most purchases will produce zero insights — Chip stays quiet unless there
    /// is something genuinely worth saying.
    ///
    /// - Parameters:
    ///   - recommendation: The engine's scored recommendation for this purchase.
    ///   - purchase: The checkout context (merchant, category, currency, networks).
    ///   - catalogue: The card catalogue, used only to look up FX rules.
    ///   - defaultCardId: The owner's habitual card, from `OwnerState.defaultCardId`.
    public static func evaluate(
        recommendation: Recommendation,
        purchase: PurchaseContext,
        catalogue: Catalogue,
        defaultCardId: String
    ) -> [ChipInsight] {
        var insights: [ChipInsight] = []

        let winner = recommendation.winner

        // 1. All candidates negative — don't tap anything.
        if winner.netValueCad < -0.0001 {
            insights.append(.allCardsNegative)
        }

        // 2. Network restriction — the merchant accepts fewer networks than the standard set.
        let standardNetworks: Set<Network> = [.amex, .visa, .mastercard]
        let restricted = standardNetworks.subtracting(purchase.acceptedNetworks)
        if !restricted.isEmpty {
            // Count how many owned cards are on an excluded network. We check the catalogue
            // directly since allCandidates only carries non-excluded scores.
            let excludedCount = catalogue.cards.filter { card in
                restricted.contains(card.network) &&
                recommendation.allCandidates.allSatisfy { $0.cardId != card.cardId }
            }.count
            if excludedCount > 0 {
                insights.append(.networkRestricted(
                    merchant: purchase.merchantBrand,
                    requiredNetworks: purchase.acceptedNetworks,
                    excludedCardCount: excludedCount
                ))
            }
        }

        // 3. Foreign currency → DCC warning.
        if purchase.currency != "CAD" && purchase.country != "CA" {
            insights.append(.declineDcc(localCurrency: purchase.currency))
        }

        // 4. Switch from default — the core product moment.
        if recommendation.switchedFromDefault,
           !recommendation.defaultNotAccepted,
           let advantage = recommendation.advantageOverDefaultCad,
           advantage > 0.10 {
            insights.append(.switchFromDefault(
                fromDefaultId: defaultCardId,
                toWinnerId: winner.cardId,
                advantageCad: advantage
            ))
        }

        // 5. FX cost erosion — fees eating rewards.
        if winner.fxCostCad > 0.10,
           winner.grossRewardCad > 0,
           winner.fxCostCad > winner.grossRewardCad * 0.40 {
            let fxRate = fxRateForCard(winner.cardId, in: catalogue)
            insights.append(.fxCostErosion(
                winnerCardId: winner.cardId,
                fxCostCad: winner.fxCostCad,
                grossRewardCad: winner.grossRewardCad,
                fxRate: fxRate
            ))
        }

        // 6. Cap nearly exhausted.
        if winner.warnings.contains(.capNearlyExhausted) {
            insights.append(.capNearlyExhausted(
                winnerCardId: winner.cardId,
                runnerUpCardId: recommendation.runnerUp?.cardId
            ))
        }

        // 7. Valuation sensitive — point value matters.
        if recommendation.valuationSensitive,
           let declared = recommendation.declaredCentsPerPoint,
           let breakeven = recommendation.breakevenCentsPerPoint,
           let alternate = recommendation.alternateWinnerCardId,
           let direction = recommendation.valuationDirection {
            insights.append(.valuationSensitive(
                winnerCardId: winner.cardId,
                declaredCentsPerPoint: declared,
                breakevenCentsPerPoint: breakeven,
                alternateCardId: alternate,
                direction: direction
            ))
        }

        // 8. Marginal winner suppressed — "close enough."
        if let suppressed = recommendation.suppressedBetterCard {
            let delta = suppressed.netValueCad - winner.netValueCad
            insights.append(.marginalWinnerSuppressed(
                suppressedCardId: suppressed.cardId,
                advantageCad: delta
            ))
        }

        return insights.sorted { $0.priority < $1.priority }
    }

    // MARK: - Private helpers

    private static func fxRateForCard(_ cardId: String, in catalogue: Catalogue) -> Double {
        guard let card = catalogue.cards.first(where: { $0.cardId == cardId }),
              let fxRule = card.fxRules.first(where: { $0.status == .current }) else {
            return 0
        }
        return fxRule.rate
    }
}
