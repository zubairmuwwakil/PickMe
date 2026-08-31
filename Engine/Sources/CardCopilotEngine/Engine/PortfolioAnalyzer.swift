import Foundation

/// What to do with a card, given only what the engine can honestly measure: earn value.
///
/// Every verdict below is about *rewards on spend*. Non-earn benefits — lounge access, annual
/// free-night awards, elite nights, insurance, statement credits — are deliberately not valued
/// (decision #14). Where they matter, `requiredBenefitValueCad` states the threshold the owner
/// has to clear from their own judgement, exactly as `breakevenCentsPerPoint` does for points.
public enum PortfolioVerdict: String, Codable, Equatable, Sendable {
    /// No annual fee. Holding it costs nothing, so there is nothing to decide.
    case freeToKeep
    /// Marginal earn value alone covers the annual fee.
    case keep
    /// The fee is not earned, but this card is the wallet's only access to its rewards program —
    /// so the move is a cheaper product in the same family, not walking away from the currency.
    case downgrade
    /// The fee is not earned and the wallet loses no program access: another card already earns
    /// in the same currency, or the card earns nothing this wallet can't get elsewhere.
    case cancel
}

/// Where a card's spend goes when that card is removed — the reason its marginal value is what
/// it is. A card can look worthless purely because a duplicate sits beside it.
public struct BackfillShare: Equatable, Sendable {
    public let cardId: String
    public let bucketLabels: [String]
    public let valueRetainedCad: Double
}

public struct CardContribution: Equatable, Sendable {
    public let cardId: String
    /// What the wallet loses if this card goes: total value with it, minus total value with every
    /// purchase re-optimised over the remaining cards. The only honest measure of worth.
    public let marginalValueCad: Double
    /// What this card earns on the buckets it wins. Shown *only* for contrast — subtracting the
    /// fee from this number is the classic wrong answer.
    public let grossRewardValueCad: Double
    public let annualFeeCad: Double
    /// Issuer credits the owner confirmed actually posted. Unspent credits never enter this value.
    public let realizedCreditValueCad: Double
    /// Current unused amount, disclosed as recoverable upside but excluded from the verdict.
    public let unspentCreditPotentialCad: Double
    /// `marginalValueCad + realizedCreditValueCad − annualFeeCad`. The ranking key.
    public let netContributionCad: Double
    public let verdict: PortfolioVerdict
    /// Annual value the owner must get from benefits this engine does not price, for the fee to
    /// be worth paying. Zero when earn value already covers the fee.
    public let requiredBenefitValueCad: Double
    /// The stated fee is conditional and the owner has not told us whether the condition holds —
    /// so the verdict is computed at the stated fee and flagged rather than guessed.
    public let feeWaiverUnresolved: Bool
    /// Owner state gates this card out of every purchase, so it can contribute nothing at all.
    public let neverScorable: Bool
    public let winningBuckets: [String]
    public let backfilledBy: [BackfillShare]
}

/// Two cards that each look disposable only because the other one covers for them. Cancelling
/// either is cheap; cancelling both is not.
public struct RedundantPair: Equatable, Sendable {
    public let cardIds: [String]
    public let jointMarginalCad: Double
    public let sumOfIndividualMarginalsCad: Double
    public let combinedAnnualFeeCad: Double
}

public struct PortfolioAnalysis: Equatable, Sendable {
    public let profileId: String
    public let asOf: String
    public let totalAnnualSpendCad: Double
    /// Annual reward value of the whole wallet, every purchase optimally placed.
    public let portfolioValueCad: Double
    public let totalAnnualFeesCad: Double
    /// Ranked by net contribution, best first.
    public let contributions: [CardContribution]
    public let redundantPairs: [RedundantPair]

    public func contribution(_ cardId: String) -> CardContribution? {
        contributions.first { $0.cardId == cardId }
    }
}

/// One counterfactual wallet's year.
public struct PortfolioRun: Equatable, Sendable {
    public let totalValueCad: Double
    public let valueByCard: [String: Double]
    public let valueByBucket: [String: Double]
    /// Cards that produced a score on at least one purchase. A card missing here is gated out by
    /// owner state or acceptance everywhere — a different fact from earning less than its rivals.
    public let scorableCards: Set<String>
    /// A bucket can have more than one winner across the year — that is a cap flipping mid-year.
    public let winnersByBucket: [String: Set<String>]
}

/// Answers "which of these cards is worth keeping?" for a given annual spend distribution.
///
/// **Modelling assumptions, all deliberate:**
/// - Value is measured at the wallet's optimum (`allCandidates.first`), not at the threshold-gated
///   recommendation. The switch threshold models the friction of digging out a second card at one
///   checkout; applied here it would make removing the *default* card raise the wallet's total,
///   producing negative marginal values that are an artefact of the gate rather than a fact about
///   the card.
/// - The year is simulated as twelve equal months from `asOf`, with cap progress carried forward.
///   Monthly caps reset each month, quarterly caps every third simulated month (loop-relative, not
///   pinned to real Jan/Apr/Jul/Oct boundaries); annual and account-year caps are treated as one
///   full year of room across the window, which is exact for account-year caps and never
///   double-counts a reset.
/// - Cap progress starts at zero: this is a forward-looking year, not the remainder of the current
///   one. (The seeded Scotia progress is flagged suspect in owner-state.json regardless.)
public struct PortfolioAnalyzer {
    /// How much of the pair's combined annual fee the overlap must be worth before the pair is
    /// reported. A display threshold, not a fact about the cards — stated so it isn't invisible.
    static let redundancyMaterialityFraction = 0.1

    let catalogue: Catalogue
    let ownerState: OwnerState

    public init(catalogue: Catalogue, ownerState: OwnerState,
                cardIds: Set<String>? = nil) {
        var scopedCatalogue = catalogue
        if let cardIds {
            scopedCatalogue.cards = catalogue.cards.filter { cardIds.contains($0.cardId) }
        } else if !ownerState.ownedCardIds.isEmpty {
            let owned = Set(ownerState.ownedCardIds)
            scopedCatalogue.cards = catalogue.cards.filter { owned.contains($0.cardId) }
        }
        self.catalogue = scopedCatalogue
        self.ownerState = ownerState
    }

    public func analyze(_ distribution: SpendDistribution, asOf: String) -> PortfolioAnalysis {
        let full = run(distribution, excluding: [], asOf: asOf)

        var contributions: [CardContribution] = []
        for card in catalogue.cards {
            let without = run(distribution, excluding: [card.cardId], asOf: asOf)
            let marginal = full.totalValueCad - without.totalValueCad
            let fee = ReportingCurrency.toReporting(card.fee.annual)
            let creditRecovery = CreditPortfolioRecoveryCalculator.recovery(
                card: card, cardState: ownerState.cardStates[card.cardId] ?? CardState(), asOf: asOf
            )
            let wins = full.winnersByBucket
                .filter { $0.value.contains(card.cardId) }
                .keys.sorted()

            contributions.append(CardContribution(
                cardId: card.cardId,
                marginalValueCad: marginal,
                grossRewardValueCad: full.valueByCard[card.cardId] ?? 0,
                annualFeeCad: fee,
                realizedCreditValueCad: creditRecovery.realizedCad,
                unspentCreditPotentialCad: creditRecovery.unspentPotentialCad,
                netContributionCad: marginal + creditRecovery.realizedCad - fee,
                verdict: verdict(for: card, marginal: marginal + creditRecovery.realizedCad,
                                 fee: fee),
                requiredBenefitValueCad: max(0, fee - marginal - creditRecovery.realizedCad),
                feeWaiverUnresolved: feeWaiverUnresolved(card),
                neverScorable: !full.scorableCards.contains(card.cardId),
                winningBuckets: wins,
                backfilledBy: backfill(for: card.cardId, wins: wins, without: without)))
        }
        contributions.sort {
            $0.netContributionCad != $1.netContributionCad
                ? $0.netContributionCad > $1.netContributionCad
                : $0.cardId < $1.cardId
        }

        return PortfolioAnalysis(
            profileId: distribution.profileId,
            asOf: asOf,
            totalAnnualSpendCad: distribution.totalAnnualCad,
            portfolioValueCad: full.totalValueCad,
            totalAnnualFeesCad: catalogue.cards.reduce(0) { $0 + ReportingCurrency.toReporting($1.fee.annual) },
            contributions: contributions,
            redundantPairs: redundantPairs(distribution, asOf: asOf,
                                           full: full, contributions: contributions))
    }

    /// Annual reward value of the wallet with `excluding` removed and every purchase re-optimised
    /// over what is left. `marginalValue` is the difference between two of these.
    public func marginalValue(ofRemoving cardIds: Set<String>,
                              from distribution: SpendDistribution, asOf: String) -> Double {
        run(distribution, excluding: [], asOf: asOf).totalValueCad
            - run(distribution, excluding: cardIds, asOf: asOf).totalValueCad
    }

    // MARK: - The simulated year

    public func run(_ distribution: SpendDistribution, excluding: Set<String>,
                    asOf: String) -> PortfolioRun {
        var subCatalogue = catalogue
        subCatalogue.cards = catalogue.cards.filter { !excluding.contains($0.cardId) }

        var state = forwardYearState()

        var total = 0.0
        var byCard: [String: Double] = [:]
        var byBucket: [String: Double] = [:]
        var winners: [String: Set<String>] = [:]
        var scorable: Set<String> = []

        for month in 0..<12 {
            resetPeriodicCaps(in: &state, catalogue: subCatalogue, month: month)
            let monthAsOf = Self.advance(asOf, byMonths: month)

            for bucket in distribution.buckets where bucket.annualCad > 0 {
                var purchase = bucket.context
                purchase.amountCad = bucket.annualCad / 12
                purchase.usdEquivalent = bucket.context.usdEquivalent.map { $0 / 12 }
                guard subCatalogue.cards.contains(where: {
                    purchase.acceptedNetworks.contains($0.network)
                }) else { continue }

                let engine = RecommendationEngine(catalogue: subCatalogue, ownerState: state)
                let candidates = engine.recommendOrNil(purchase, asOf: monthAsOf)?.allCandidates ?? []
                scorable.formUnion(candidates.map(\.cardId))
                guard let best = candidates.first else { continue }

                total += best.netValueCad
                byCard[best.cardId, default: 0] += best.netValueCad
                byBucket[bucket.label, default: 0] += best.netValueCad
                winners[bucket.label, default: []].insert(best.cardId)
                accrueCapProgress(for: best, purchase: purchase,
                                  catalogue: subCatalogue, into: &state)
            }
        }

        return PortfolioRun(totalValueCad: total, valueByCard: byCard, valueByBucket: byBucket,
                            scorableCards: scorable, winnersByBucket: winners)
    }

    /// Caps start empty: the question is what a card is worth over the *next* year, not what is
    /// left of the current one. (The seeded Scotia progress is flagged suspect regardless.)
    ///
    /// The simulated owner also owns exactly the cards in this counterfactual's catalogue.
    /// `RecommendationEngine` re-filters its catalogue by `ownedCardIds` — a checkout-path guard
    /// against advising a card the owner doesn't hold — and without this the two filters intersect,
    /// silently deleting any scoped-in card that isn't already owned. For keep/cancel the scoped set
    /// is a subset of the owned set, so this is a no-op; for the *acquisition* counterfactual the
    /// candidate is unowned by definition, so it would score on nothing at all.
    private func forwardYearState() -> OwnerState {
        var state = ownerState
        state.ownedCardIds = catalogue.cards.map(\.cardId)
        state.cardStates = state.cardStates.mapValues { cardState in
            var reset = cardState
            reset.capProgress = cardState.capProgress?.mapValues { _ in 0 }
            return reset
        }
        return state
    }

    /// Resets caps whose period completes on this simulated month. `month` is the loop-relative
    /// index from `run(_:excluding:asOf:)` (0...11 from `asOf`, not a real calendar month), so a
    /// `.calendarQuarter` cap resets every third simulated month — "one quarter of room" per the
    /// same non-calendar-pinned simplification `.calendarYear`/`.accountYear` already get treated
    /// with as "one full year of room" across the window.
    private func resetPeriodicCaps(in state: inout OwnerState, catalogue: Catalogue, month: Int) {
        for card in catalogue.cards {
            for cap in card.caps {
                let dueForReset = cap.period == .calendarMonth
                    || (cap.period == .calendarQuarter && month % 3 == 0)
                guard dueForReset else { continue }
                state.cardStates[card.cardId, default: CardState()]
                    .capProgress?[cap.capId] = 0
            }
        }
    }

    /// Spend counts against a cap only on the card it was actually put on.
    private func accrueCapProgress(for score: CandidateScore, purchase: PurchaseContext,
                                   catalogue: Catalogue, into state: inout OwnerState) {
        guard let card = catalogue.cards.first(where: { $0.cardId == score.cardId }),
              let ruleId = score.appliedRuleId,
              let rule = card.earnRules.first(where: { $0.ruleId == ruleId })
        else { return }

        let effectiveCaps = rule.effectiveCapIds.compactMap { id in card.caps.first { $0.capId == id } }
        guard !effectiveCaps.isEmpty else { return }

        for cap in effectiveCaps {
            // `.spendNative` must accrue in the same currency `Scorer.score` compares it against —
            // the card's own billingCurrency, not unconditionally CAD.
            let amount = cap.measure == .spendUsdEquivalent
                ? (purchase.usdEquivalent ?? purchase.amountCad * Scorer.fallbackCadToUsd)
                : Scorer.nativeAmount(for: purchase, billingCurrency: card.billingCurrency)
            var cardState = state.cardStates[card.cardId] ?? CardState()
            cardState.capProgress = (cardState.capProgress ?? [:])
                .merging([cap.capId: amount], uniquingKeysWith: +)
            state.cardStates[card.cardId] = cardState
        }
    }

    /// `asOf` advanced whole months, so effective-dated rules land in the right month.
    static func advance(_ isoDate: String, byMonths months: Int) -> String {
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return isoDate }
        let zeroBased = (parts[0] * 12 + parts[1] - 1) + months
        return String(format: "%04d-%02d-%02d", zeroBased / 12, zeroBased % 12 + 1,
                      min(parts[2], 28))
    }

    // MARK: - Verdicts

    private func verdict(for card: CardProduct, marginal: Double, fee: Double) -> PortfolioVerdict {
        if fee <= 0 { return .freeToKeep }
        if marginal >= fee { return .keep }
        // Cancelling the only card that earns a currency forfeits the currency; cancelling one of
        // two does not. That difference is the whole distinction between downgrade and cancel.
        let soleHolderOfProgram = !catalogue.cards.contains {
            $0.cardId != card.cardId && $0.program.programId == card.program.programId
        }
        return (marginal > 0 && soleHolderOfProgram) ? .downgrade : .cancel
    }

    /// A conditional fee whose condition the owner hasn't answered. The engine never guesses
    /// owner state, so the verdict is computed at the stated fee and the uncertainty is surfaced.
    private func feeWaiverUnresolved(_ card: CardProduct) -> Bool {
        card.fee.waiver != nil && ownerState.cardStates[card.cardId]?.feeWaiverActive == nil
    }

    private func backfill(for cardId: String, wins: [String],
                          without: PortfolioRun) -> [BackfillShare] {
        var buckets: [String: [String]] = [:]
        var retained: [String: Double] = [:]
        for label in wins {
            for successor in (without.winnersByBucket[label] ?? []).sorted() {
                buckets[successor, default: []].append(label)
                retained[successor, default: 0] += without.valueByBucket[label] ?? 0
            }
        }
        return buckets.keys
            .sorted { (retained[$0] ?? 0, $1) > (retained[$1] ?? 0, $0) }
            .map { BackfillShare(cardId: $0, bucketLabels: buckets[$0] ?? [],
                                 valueRetainedCad: retained[$0] ?? 0) }
    }

    /// A pair is redundant when removing both costs materially more than removing each alone —
    /// the signature of two cards covering the same categories at the same rate. Almost any two
    /// cards overlap by a few dollars, so the overlap has to be worth at least
    /// `redundancyMaterialityFraction` of the fees at stake before it is worth the owner's
    /// attention; below that it buries the pairs that actually change a decision.
    private func redundantPairs(_ distribution: SpendDistribution, asOf: String,
                                full: PortfolioRun,
                                contributions: [CardContribution]) -> [RedundantPair] {
        let unearned = contributions.filter { $0.marginalValueCad < $0.annualFeeCad }
        var pairs: [RedundantPair] = []
        for (index, a) in unearned.enumerated() {
            for b in unearned[(index + 1)...] {
                guard a.backfilledBy.contains(where: { $0.cardId == b.cardId })
                        || b.backfilledBy.contains(where: { $0.cardId == a.cardId }) else { continue }
                let joint = full.totalValueCad
                    - run(distribution, excluding: [a.cardId, b.cardId], asOf: asOf).totalValueCad
                let individually = a.marginalValueCad + b.marginalValueCad
                let combinedFee = a.annualFeeCad + b.annualFeeCad
                guard joint - individually >= Self.redundancyMaterialityFraction * combinedFee,
                      joint > individually + 0.01 else { continue }
                pairs.append(RedundantPair(cardIds: [a.cardId, b.cardId].sorted(),
                                           jointMarginalCad: joint,
                                           sumOfIndividualMarginalsCad: individually,
                                           combinedAnnualFeeCad: combinedFee))
            }
        }
        return pairs.sorted { $0.jointMarginalCad > $1.jointMarginalCad }
    }
}
