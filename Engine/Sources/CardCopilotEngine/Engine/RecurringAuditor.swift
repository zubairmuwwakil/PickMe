import Foundation

/// What the checklist says to do with one declared bill.
public enum RecurringAction: String, Equatable, Sendable {
    /// Already on the best card. Nothing to do.
    case alreadyOptimal
    /// A better card exists and the gain clears the move bar.
    case move
    /// A better card exists but the gain doesn't clear the bar. Listed, never hidden — the
    /// owner is entitled to see what was suppressed on their behalf.
    case belowBar
    /// The owner didn't say where the bill sits, so there is no baseline to gain against.
    case baselineUnknown
}

/// Whether the recommendation survives not knowing the network's recurring-payment indicator.
public enum FlagRobustness: Equatable, Sendable {
    /// The same card wins whether or not the charge carries the flag. Act today.
    case flagIndependent
    /// A statement already settled it.
    case flagConfirmed
    case flagRefuted
    /// The two worlds disagree, so the recommendation is a bet — with the terms published.
    case flagContingent(FlagContingency)
}

/// The bounded-regret test. The recurring flag, unlike a point valuation, is *statement-
/// verifiable*: one billing cycle resolves it permanently. So the honest move is not to pick a
/// conservative branch and stay there — it is to compare the price of finding out against the
/// value of knowing.
public struct FlagContingency: Equatable, Sendable {
    public let cardIfFlagged: String
    public let cardIfNotFlagged: String
    /// Annual gain of the flagged card over the unflagged one, if the flag turns out to be real.
    public let annualGainIfFlaggedCad: Double
    /// What one billing cycle on the flagged card costs if the flag is *not* there. The total
    /// price of the experiment, because the statement ends the uncertainty.
    public let oneCycleCostIfNotFlaggedCad: Double
    /// `annualGainIfFlaggedCad > oneCycleCostIfNotFlaggedCad`. When false, the safe card is
    /// recommended and the test isn't worth running.
    public let testWorthRunning: Bool
}

/// Assumptions and caveats attached to a single line of the checklist. Facts about what the
/// engine had to supply or assume — never advice.
public enum RecurringDisclosure: Equatable, Sendable {
    /// The owner gave no MCC; this one was supplied from `RecurringCategoryDefaults`.
    case mccAssumed(Int)
    /// The winning rule is gated on an MCC list and no MCC was ever known, so the gate was
    /// never actually tested. `RuleMatcher` falls through to a match in this case.
    case mccGateUnverified(ruleId: String)
    /// An Amex card won and the owner never said whether the biller takes Amex.
    case amexAcceptanceAssumed
    /// The winner changes if points are valued at their guaranteed floor instead of the
    /// declared value. Decision #14, one layer up.
    case valuationSensitive(alternateCardId: String)
    /// The winning card is scored on a Tangerine category the owner may not have selected.
    case hypotheticalTangerineSelection
}

public struct RecurringAssignment: Equatable, Sendable, Identifiable {
    public let paymentId: String
    public let label: String
    public let annualCad: Double
    public let currentPlacement: Placement
    public let recommendedCardId: String
    /// Annual value on the recommended card, and on the current placement. Both at the wallet
    /// optimum — see the note on the auditor about why the switch threshold is not applied here.
    public let recommendedAnnualValueCad: Double
    public let currentAnnualValueCad: Double?
    /// `nil` when the placement is unknown. For an `assumed` flag this is the *lower* of the
    /// two worlds' gains, so a move that clears the bar clears it however the flag lands.
    public let annualGainCad: Double?
    public let advantagePercentagePoints: Double?
    public let action: RecurringAction
    public let robustness: FlagRobustness
    public let disclosures: [RecurringDisclosure]

    public var id: String { paymentId }
}

public struct RecurringAudit: Equatable, Sendable {
    public let planId: String
    public let basis: String
    public let asOf: String
    public let totalAnnualDeclaredCad: Double
    public let assignments: [RecurringAssignment]
    /// Where the caps are heading if nothing changes, and where they head if the checklist is
    /// followed. Two runs of the same projector over two placements — the difference is the
    /// only form of this answer an owner can act on.
    public let projectionsAtCurrentPlacement: [CapProjectionOutcome]
    public let projectionsAtRecommendedPlacement: [CapProjectionOutcome]

    public func assignment(_ paymentId: String) -> RecurringAssignment? {
        assignments.first { $0.paymentId == paymentId }
    }
}

/// Assigns owner-declared recurring bills to cards, and says how much of each answer depends
/// on a fact the engine has never observed.
///
/// **A parallel component.** Like `BenefitsAdvisor` and `PortfolioAnalyzer`, nothing in the
/// scoring pipeline calls this and it reimplements no scoring. It has no write path to
/// `OwnerState`: declared amounts never advance `capProgress`, which is a live input to the
/// 30-checkout experiment's arithmetic check. A projection built from numbers nobody verified
/// must not become an input to the measurement that is supposed to catch bad numbers.
///
/// **Ranking is at the wallet optimum, not the threshold-gated recommendation** — the same
/// choice `PortfolioAnalyzer` documents. The switch threshold models the friction of digging a
/// second card out of a wallet at a checkout; an autopay is set once and never dug out again.
/// The friction that *does* exist here — logging into a biller to change a card on file — is a
/// one-time cost against a recurring benefit, so it gets its own bar below.
public struct RecurringAuditor {

    /// Noise floor, in percentage points, shared in spirit with decision #8: a fraction of a
    /// point is not a real difference between two cards.
    public static let minAdvantagePercentagePoints = 0.5

    /// Annual gain a reassignment must produce to be worth an owner's login. Deliberately
    /// *lower* than the checkout threshold's per-transaction C$0.25: that number prices the
    /// friction of one wallet dig, and paying it every time. This one is paid once and earns
    /// every year after. At C$5 a $203.88/yr subscription moving from 2% to 5% (+$6.12/yr)
    /// stays on the list, which is the right call for a three-minute change; the percentage-
    /// point floor above is what keeps genuine noise off it.
    public static let minAnnualGainCad = 5.0

    let catalogue: Catalogue
    let ownerState: OwnerState

    public init(catalogue: Catalogue, ownerState: OwnerState) {
        self.catalogue = catalogue
        self.ownerState = ownerState
    }

    /// `capProgressAsOf` is the date the owner last read their cap figures off a statement.
    /// Passing it is what lets the projection claim its starting point is anchored.
    public func audit(_ plan: RecurringPlan, asOf: String,
                      capProgressAsOf: String? = nil) -> RecurringAudit {
        let assignments = plan.payments.map { assign($0, asOf: asOf) }
        let byId = Dictionary(plan.payments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let projector = CapProjector(catalogue: catalogue, ownerState: ownerState)

        // The flag reading travels with the placement: a bill the owner calls recurring is
        // projected as recurring unless a statement refuted it. Nothing here writes back.
        func placements(_ cardId: (RecurringAssignment) -> String?) -> [PlacedPayment] {
            assignments.compactMap { assignment in
                guard let payment = byId[assignment.paymentId],
                      let cardId = cardId(assignment) else { return nil }
                return PlacedPayment(payment: payment, cardId: cardId,
                                     assumeFlagged: payment.flagStatus != .refuted)
            }
        }

        return RecurringAudit(
            planId: plan.planId,
            basis: plan.basis,
            asOf: asOf,
            totalAnnualDeclaredCad: plan.totalAnnualCad,
            assignments: assignments,
            projectionsAtCurrentPlacement: projector.project(
                placements { assignment in
                    if case .card(let id) = assignment.currentPlacement { return id }
                    return nil
                }, asOf: asOf, capProgressAsOf: capProgressAsOf),
            projectionsAtRecommendedPlacement: projector.project(
                placements { $0.recommendedCardId }, asOf: asOf,
                capProgressAsOf: capProgressAsOf))
    }

    // MARK: - One bill

    private func assign(_ payment: RecurringPayment, asOf: String) -> RecurringAssignment {
        var disclosures: [RecurringDisclosure] = []
        let mcc = resolvedMcc(payment, disclosures: &disclosures)

        let flagged = world(payment, mcc: mcc, flagged: true, asOf: asOf)
        let unflagged = world(payment, mcc: mcc, flagged: false, asOf: asOf)
        let verdict = resolve(payment, flagged: flagged, unflagged: unflagged)
        let recommendedId = verdict.recommendedCardId

        let recommendedValue = verdict.value(recommendedId)
        var currentValue: Double?
        if case .card(let currentId) = payment.placement {
            currentValue = verdict.value(currentId)
        } else if payment.placement == .offWallet {
            currentValue = 0
        }

        let gain = currentValue.map { _ in verdict.gain(from: payment.placement,
                                                        to: recommendedId) }
        disclose(payment, verdict: verdict, mcc: mcc, into: &disclosures)
        let advantagePP = gain.map { payment.annualCad > 0 ? $0 / payment.annualCad * 100 : 0 }

        return RecurringAssignment(
            paymentId: payment.id,
            label: payment.label,
            annualCad: payment.annualCad,
            currentPlacement: payment.placement,
            recommendedCardId: recommendedId,
            recommendedAnnualValueCad: recommendedValue,
            currentAnnualValueCad: currentValue,
            annualGainCad: gain,
            advantagePercentagePoints: advantagePP,
            action: action(payment: payment, recommendedId: recommendedId,
                           gain: gain, advantagePP: advantagePP),
            robustness: verdict.robustness,
            disclosures: disclosures)
    }

    private func action(payment: RecurringPayment, recommendedId: String,
                        gain: Double?, advantagePP: Double?) -> RecurringAction {
        guard let gain, let advantagePP else { return .baselineUnknown }
        if case .card(let currentId) = payment.placement, currentId == recommendedId {
            return .alreadyOptimal
        }
        let clears = gain >= Self.minAnnualGainCad
            && advantagePP >= Self.minAdvantagePercentagePoints
        return clears ? .move : .belowBar
    }

    // MARK: - Disclosures

    /// Facts about what the engine had to supply or assume to reach this line. None of them
    /// re-rank anything — they are the falsification handles, in the spirit of decision #14:
    /// publish the assumption alongside the advice that rests on it.
    private func disclose(_ payment: RecurringPayment, verdict: Verdict, mcc: Int?,
                          into disclosures: inout [RecurringDisclosure]) {
        let world = verdict.representativeWorld
        guard let score = world.score(verdict.recommendedCardId),
              let card = catalogue.cards.first(where: { $0.cardId == verdict.recommendedCardId })
        else { return }

        // An MCC-gated rule won without an MCC ever being known. `RuleMatcher.matches` falls
        // through to a match in that case, so the gate was never actually tested.
        if mcc == nil, let ruleId = score.appliedRuleId,
           card.earnRules.first(where: { $0.ruleId == ruleId })?.predicate.mccInclude != nil {
            disclosures.append(.mccGateUnverified(ruleId: ruleId))
        }

        if card.network == .amex, payment.declaredAcceptedNetworks == nil {
            disclosures.append(.amexAcceptanceAssumed)
        }

        if let floorWinner = world.floorWinner, floorWinner.cardId != verdict.recommendedCardId {
            disclosures.append(.valuationSensitive(alternateCardId: floorWinner.cardId))
        }

        if score.warnings.contains(.hypotheticalSelection) {
            disclosures.append(.hypotheticalTangerineSelection)
        }
    }

    // MARK: - Resolving the flag

    /// The recommendation plus the reading of the flag it was made under. `mode` decides which
    /// world's numbers the checklist quotes, so a figure is never blended across two worlds the
    /// owner would have to distinguish.
    private struct Verdict {
        enum Mode { case flaggedOnly, unflaggedOnly, conservativeBoth }

        let recommendedCardId: String
        let robustness: FlagRobustness
        let mode: Mode
        let flagged: ScoredWorld
        let unflagged: ScoredWorld

        /// The world whose applied rules and warnings the disclosures describe. For a verdict
        /// that doesn't depend on the flag, that is the unflagged one: the guaranteed reading.
        var representativeWorld: ScoredWorld { mode == .flaggedOnly ? flagged : unflagged }

        func value(_ cardId: String) -> Double {
            switch mode {
            case .flaggedOnly: return flagged.annualValue(cardId)
            case .unflaggedOnly: return unflagged.annualValue(cardId)
            case .conservativeBoth: return min(flagged.annualValue(cardId),
                                               unflagged.annualValue(cardId))
            }
        }

        /// When the winner doesn't depend on the flag, the *gain* still can — the card the bill
        /// sits on today may be the flag-dependent one. Reporting the smaller of the two worlds'
        /// improvements means a move that clears the bar clears it however the flag lands.
        func gain(from placement: Placement, to recommendedId: String) -> Double {
            func current(_ world: ScoredWorld) -> Double {
                if case .card(let id) = placement { return world.annualValue(id) }
                return 0
            }
            switch mode {
            case .flaggedOnly:
                return flagged.annualValue(recommendedId) - current(flagged)
            case .unflaggedOnly:
                return unflagged.annualValue(recommendedId) - current(unflagged)
            case .conservativeBoth:
                return min(flagged.annualValue(recommendedId) - current(flagged),
                           unflagged.annualValue(recommendedId) - current(unflagged))
            }
        }
    }

    private func resolve(_ payment: RecurringPayment, flagged: ScoredWorld,
                         unflagged: ScoredWorld) -> Verdict {
        func verdict(_ cardId: String?, _ robustness: FlagRobustness,
                     _ mode: Verdict.Mode) -> Verdict {
            Verdict(recommendedCardId: cardId ?? "", robustness: robustness, mode: mode,
                    flagged: flagged, unflagged: unflagged)
        }

        switch payment.flagStatus {
        case .confirmed:
            return verdict(flagged.winner?.cardId, .flagConfirmed, .flaggedOnly)
        case .refuted:
            return verdict(unflagged.winner?.cardId, .flagRefuted, .unflaggedOnly)
        case .assumed:
            guard let ifFlagged = flagged.winner?.cardId,
                  let ifNot = unflagged.winner?.cardId else {
                return verdict(nil, .flagIndependent, .conservativeBoth)
            }
            guard ifFlagged != ifNot else {
                return verdict(ifFlagged, .flagIndependent, .conservativeBoth)
            }

            // The bounded-regret test. One billing cycle is the entire price of the experiment,
            // because the statement that follows it settles the question for good.
            let gainIfFlagged = flagged.annualValue(ifFlagged) - unflagged.annualValue(ifNot)
            let oneCycleCost = (unflagged.annualValue(ifNot) - unflagged.annualValue(ifFlagged))
                / payment.cadence.chargesPerYear
            let worthRunning = gainIfFlagged > oneCycleCost

            return verdict(worthRunning ? ifFlagged : ifNot,
                           .flagContingent(FlagContingency(
                               cardIfFlagged: ifFlagged,
                               cardIfNotFlagged: ifNot,
                               annualGainIfFlaggedCad: gainIfFlagged,
                               oneCycleCostIfNotFlaggedCad: oneCycleCost,
                               testWorthRunning: worthRunning)),
                           worthRunning ? .flaggedOnly : .unflaggedOnly)
        }
    }

    // MARK: - The two worlds

    /// One scored world: every card's annual value for this bill, under one reading of the
    /// network's recurring-payment indicator.
    private struct ScoredWorld {
        let candidates: [CandidateScore]
        let perYear: Double
        let defaultCardId: String

        var winner: CandidateScore? { candidates.first }

        func score(_ cardId: String) -> CandidateScore? {
            candidates.first { $0.cardId == cardId }
        }

        /// A card the bill sits on but that cannot be scored at all — gated out by network or
        /// unresolved owner state — earns nothing, which is the honest baseline.
        func annualValue(_ cardId: String) -> Double {
            (score(cardId)?.netValueCad ?? 0) * perYear
        }

        /// The winner if points were redeemed at their guaranteed cash floor. Tie-broken exactly
        /// as `RecommendationEngine.rank` does, so a tie never reads as a changed winner.
        var floorWinner: CandidateScore? {
            candidates.sorted { a, b in
                if a.floorNetValueCad != b.floorNetValueCad {
                    return a.floorNetValueCad > b.floorNetValueCad
                }
                if a.cardId == defaultCardId { return true }
                if b.cardId == defaultCardId { return false }
                return a.cardId < b.cardId
            }.first
        }
    }

    private func world(_ payment: RecurringPayment, mcc: Int?, flagged: Bool,
                       asOf: String) -> ScoredWorld {
        let purchase = PurchaseContext(amountCad: payment.amountCad,
                                       currency: payment.currency,
                                       category: payment.category,
                                       mcc: mcc,
                                       merchantBrand: payment.merchantBrand,
                                       channel: "online",
                                       recurringIndicator: flagged,
                                       acceptedNetworks: payment.effectiveAcceptedNetworks)
        let candidates = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
            .recommend(purchase, asOf: asOf).allCandidates
        return ScoredWorld(candidates: candidates,
                           perYear: payment.cadence.chargesPerYear,
                           defaultCardId: ownerState.defaultCardId)
    }

    private func resolvedMcc(_ payment: RecurringPayment,
                             disclosures: inout [RecurringDisclosure]) -> Int? {
        if let declared = payment.mcc { return declared }
        guard let representative = RecurringCategoryDefaults.representativeMcc[payment.category]
        else { return nil }
        disclosures.append(.mccAssumed(representative))
        return representative
    }
}
