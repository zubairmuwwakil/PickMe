import Foundation

/// A declared bill together with the card it is being projected onto, and the reading of the
/// network's recurring-payment indicator that placement assumed. The flag has to travel with
/// the placement: whether an insurance charge burns Scotia's 4% bucket at all depends on it.
public struct PlacedPayment: Equatable, Sendable {
    public let payment: RecurringPayment
    public let cardId: String
    public let assumeFlagged: Bool

    public init(payment: RecurringPayment, cardId: String, assumeFlagged: Bool) {
        self.payment = payment
        self.cardId = cardId
        self.assumeFlagged = assumeFlagged
    }
}

/// One month of projected burn against one cap.
public struct MonthlyBurn: Equatable, Sendable {
    public let month: String
    public let burnCad: Double
    /// Starting usage plus every month's burn up to and including this one.
    public let cumulativeCad: Double
}

/// What the projection is standing on. The distinction is the whole point: one of these is a
/// bound, the other is a guess with a stated source.
public enum ProjectionBasis: Equatable, Sendable {
    /// Declared recurring spend only. On a cap shared with categories the owner didn't declare,
    /// this understates burn — so the crossing month is the LATEST possible, not an estimate.
    case declaredRecurringOnly
}

/// Declared demand for a cap exceeds the room left in it. Reported, never resolved: allocating
/// scarce cap room between competing categories is an optimisation the owner should make with
/// their eyes open, not one the engine should make silently on their behalf.
public struct CapContention: Equatable, Sendable {
    public let capId: String
    public let roomCad: Double
    public let declaredDemandCad: Double
    public let competingCategories: [String]
}

/// What a cap actually applies to. An empty category list on a rule means no category clause
/// at all — the cap is burned by every purchase on the card — which is a stronger statement
/// than "covers nothing", and the one an empty array would have quietly rendered.
public enum CapCoverage: Equatable, Sendable {
    case categories([String])
    case allSpendOnCard
}

public struct CapProjection: Equatable, Sendable {
    public let cardId: String
    public let capId: String
    public let limitCad: Double
    public let window: CapWindow.Window
    public let startingUsageCad: Double
    /// False when the starting figure carries no as-of date — as the seeded Scotia progress
    /// does not. A date computed from an undated start is a date the owner cannot check.
    public let startingUsageIsAnchored: Bool
    public let monthlyBurn: [MonthlyBurn]
    public let cumulativeAtWindowEndCad: Double
    /// First month the cap is exceeded, or `nil` if declared spend never gets there.
    public let crossingMonth: String?
    public let basis: ProjectionBasis
    public let coverage: CapCoverage
    /// Categories this cap covers that no bill *placed on this card* touches. This is precisely
    /// what makes the crossing month a bound rather than an estimate: spend in these categories
    /// on this card burns the same cap, and the audit knows nothing about it. A category the
    /// owner declared but placed on a different card still counts as undeclared here — it
    /// contributes nothing to *this* cap.
    public let undeclaredCategories: [String]
    /// At least one bill burning this cap does so *because of* a recurring flag that no
    /// statement has confirmed — losing the flag would move the bill off this cap entirely.
    /// Caps the flag cannot affect are deliberately silent here: a warning that always fires is
    /// one the owner learns to skip.
    public let restsOnAssumedFlags: Bool
    public let contention: CapContention?
}

public enum CapProjectionOutcome: Equatable, Sendable {
    case projected(CapProjection)
    /// The projection could not be made, and why. Naming the missing owner-state field is the
    /// deliverable: it is the difference between "no answer" and "here is how to get one".
    case refused(cardId: String, capId: String, reason: String)
}

/// Projects declared recurring spend against cap room, for any placement of the bills.
///
/// **It never advances `capProgress`.** `OwnerState` is read-only here. Declared amounts are
/// unverified by construction, and `capProgress` is a live input to the checkout scoring that
/// the 30-checkout experiment measures — feeding a guess into it would manufacture arithmetic
/// misses that are artefacts of the guess.
///
/// **The disagreement is the product.** A forecast nobody can verify directly is most useful as
/// a detector: if a statement shows materially more burn than declared spend accounts for,
/// something is charging that card the owner has not declared.
public struct CapProjector {
    let catalogue: Catalogue
    let ownerState: OwnerState

    public init(catalogue: Catalogue, ownerState: OwnerState) {
        self.catalogue = catalogue
        self.ownerState = ownerState
    }

    /// One outcome per cap that declared spend actually touches. A cap no declared bill burns is
    /// omitted rather than reported at zero — the audit speaks only about what it was told.
    ///
    /// `capProgressAsOf` is the date the owner's cap figures were read from a statement. It is
    /// optional because nothing in owner state records one today, and its absence is published
    /// rather than hidden.
    public func project(_ placements: [PlacedPayment], asOf: String,
                        capProgressAsOf: String? = nil) -> [CapProjectionOutcome] {
        var burnsByCap: [CapKey: [PlacedPayment]] = [:]
        for placement in placements {
            let keys = capsBurned(by: placement, asOf: asOf)
            for key in keys {
                burnsByCap[key, default: []].append(placement)
            }
        }

        return burnsByCap.keys.sorted().compactMap { key in
            outcome(for: key, placements: burnsByCap[key] ?? [], asOf: asOf,
                    capProgressAsOf: capProgressAsOf)
        }
    }

    struct CapKey: Hashable, Comparable {
        let cardId: String
        let capId: String

        static func < (a: CapKey, b: CapKey) -> Bool {
            (a.cardId, a.capId) < (b.cardId, b.capId)
        }
    }

    /// Which caps this bill burns on the card it sits on — decided by the rule that would
    /// actually apply, not by the category the owner typed. A bill that falls to an uncapped
    /// base rule burns nothing.
    private func capsBurned(by placement: PlacedPayment, asOf: String) -> [CapKey] {
        capIds(for: placement, flagged: placement.assumeFlagged, asOf: asOf)
            .map { CapKey(cardId: placement.cardId, capId: $0) }
    }

    /// Whether this bill lands on this cap *because* of the recurring flag. Re-resolving without
    /// the flag is the only honest way to answer it — the rule, not the category, decides.
    private func flagIsLoadBearing(for placement: PlacedPayment, capId: String,
                                   asOf: String) -> Bool {
        guard placement.assumeFlagged else { return false }
        return !self.capIds(for: placement, flagged: false, asOf: asOf).contains(capId)
    }

    private func capIds(for placement: PlacedPayment, flagged: Bool, asOf: String) -> [String] {
        guard let card = catalogue.cards.first(where: { $0.cardId == placement.cardId })
        else { return [] }
        var purchase = context(for: placement)
        purchase.recurringIndicator = flagged
        guard case .applied(let rule, _) = RuleMatcher.resolve(card: card, purchase: purchase,
                                                           ownerState: ownerState, asOf: asOf)
        else { return [] }
        return rule.effectiveCapIds
    }

    private func context(for placement: PlacedPayment) -> PurchaseContext {
        let payment = placement.payment
        return PurchaseContext(amountCad: payment.amountCad,
                               currency: payment.currency,
                               category: payment.category,
                               mcc: payment.mcc
                                   ?? RecurringCategoryDefaults.representativeMcc[payment.category],
                               merchantBrand: payment.merchantBrand,
                               channel: "online",
                               recurringIndicator: placement.assumeFlagged,
                               acceptedNetworks: payment.effectiveAcceptedNetworks)
    }

    private func outcome(for key: CapKey, placements: [PlacedPayment], asOf: String,
                         capProgressAsOf: String?) -> CapProjectionOutcome? {
        guard let card = catalogue.cards.first(where: { $0.cardId == key.cardId }),
              let cap = card.caps.first(where: { $0.capId == key.capId })
        else { return nil }

        guard let window = CapWindow.resolve(cap: cap, cardId: card.cardId,
                                             ownerState: ownerState, asOf: asOf) else {
            return .refused(cardId: key.cardId, capId: key.capId,
                            reason: "account-year anchor unresolved — set "
                                + (cap.anchor ?? "the cap's anchor") + " in owner state")
        }

        let start = max(CapWindow.monthIndex(asOf), CapWindow.monthIndex(window.startMonth))
        let end = CapWindow.monthIndex(window.endMonth)
        var burnByMonth = [Double](repeating: 0, count: max(0, end - start + 1))
        for placement in placements {
            for (month, amount) in burnSchedule(placement.payment, from: start, to: end) {
                burnByMonth[month - start] += amount
            }
        }

        let startingUsage = ownerState.cardStates[key.cardId]?.capProgress?[key.capId] ?? 0
        var cumulative = startingUsage
        var crossingMonth: String?
        var monthly: [MonthlyBurn] = []
        for (offset, burn) in burnByMonth.enumerated() {
            cumulative += burn
            let month = CapWindow.month(start + offset)
            if crossingMonth == nil, cumulative > cap.limit { crossingMonth = month }
            monthly.append(MonthlyBurn(month: month, burnCad: burn, cumulativeCad: cumulative))
        }

        let coverage = coverage(card: card, capId: key.capId)
        let declared = Set(placements.map { $0.payment.category })
        let undeclared: [String]
        if case .categories(let categories) = coverage {
            undeclared = categories.filter { !declared.contains($0) }
        } else {
            undeclared = []
        }
        let demand = burnByMonth.reduce(0, +)
        let room = max(0, cap.limit - startingUsage)

        return .projected(CapProjection(
            cardId: key.cardId,
            capId: key.capId,
            limitCad: cap.limit,
            window: window,
            startingUsageCad: startingUsage,
            startingUsageIsAnchored: capProgressAsOf != nil,
            monthlyBurn: monthly,
            cumulativeAtWindowEndCad: cumulative,
            crossingMonth: crossingMonth,
            basis: .declaredRecurringOnly,
            coverage: coverage,
            undeclaredCategories: undeclared,
            restsOnAssumedFlags: placements.contains {
                $0.payment.flagStatus == .assumed
                    && flagIsLoadBearing(for: $0, capId: key.capId, asOf: asOf)
            },
            contention: demand > room
                ? CapContention(capId: key.capId, roomCad: room, declaredDemandCad: demand,
                                competingCategories: {
                                    if case .categories(let c) = coverage { return c }
                                    return []
                                }())
                : nil))
    }

    private func coverage(card: CardProduct, capId: String) -> CapCoverage {
        let rules = card.earnRules.filter { $0.effectiveCapIds.contains(capId) }
        guard rules.allSatisfy({ $0.predicate.categories != nil }) else { return .allSpendOnCard }
        return .categories(Array(Set(rules.flatMap { $0.predicate.categories ?? [] })).sorted())
    }

    /// What this bill burns in each month of `[from, to]`.
    ///
    /// Cadences that charge at least monthly are spread evenly — the burn is the same either
    /// way. Lumpy cadences land on specific months, and when the owner didn't say which, the
    /// charge is placed as LATE as the window allows: any real charge date then moves the
    /// crossing earlier, never later, which is what keeps the answer a "no later than".
    private func burnSchedule(_ payment: RecurringPayment, from: Int,
                              to: Int) -> [(month: Int, amountCad: Double)] {
        guard to >= from else { return [] }
        guard let interval = monthsBetweenCharges(payment.cadence) else {
            // Weekly and biweekly bills charge a non-integer number of times per month; the
            // month's burn is what matters, not which day inside it.
            let perMonth = payment.amountCad * payment.cadence.chargesPerYear / 12
            return (from...to).map { ($0, perMonth) }
        }
        var months: [(month: Int, amountCad: Double)] = []
        if let declared = payment.nextChargeMonth {
            var month = CapWindow.monthIndex(declared)
            while month < from { month += interval }
            while month <= to {
                months.append((month, payment.amountCad))
                month += interval
            }
        } else {
            var month = to
            while month >= from {
                months.append((month, payment.amountCad))
                month -= interval
            }
        }
        return months
    }

    /// `nil` for cadences that charge at least once a month.
    private func monthsBetweenCharges(_ cadence: Cadence) -> Int? {
        switch cadence {
        case .weekly, .biweekly, .monthly: return nil
        case .quarterly: return 3
        case .semiAnnual: return 6
        case .annual: return 12
        }
    }
}
