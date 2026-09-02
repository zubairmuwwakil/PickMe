import Foundation

/// Confidence in the local merchant truth graph.
///
/// This was a binary — owner-verified, or not — and the not-verified half was silent. That
/// policy is correct for a wallet built entirely out of terminals the owner has reconciled, and
/// wrong for one that discovers merchants: a discovered POI is never verified, so a strict
/// binary means discovery can never speak.
///
/// The middle rung exists because "the POI is literally named Costco" and "the POI is an
/// unnamed store pin" are not the same guess. The first can be checked against a merchant
/// vocabulary; the second cannot be checked against anything. (Which vocabulary is the adapter's
/// business — this file only needs the tiers to mean something.)
///
/// The tiers answer two questions that happen to travel together: whether we know *which*
/// merchant this is, and whether we know how a charge here will *code*. `.frequented` exists
/// because payment evidence answers the first decisively and the second not at all.
public enum AmbientMerchantConfidence: String, Codable, Equatable, Sendable {
    /// The owner reconciled THIS terminal against a statement. Was `.high`.
    case verified
    /// A POI whose name resolves to a brand the catalogue knows. A guess, but a checkable one.
    case brandMatched
    /// A recognised merchant the owner has paid at on several separate days.
    ///
    /// Evidence of a different kind from `.verified`, not merely a weaker grade of it. A
    /// reconciled terminal proves how a charge *codes*; repeated payment proves the owner
    /// actually shops here and that this is the merchant we think it is. So this tier answers
    /// the identity and presence doubts and leaves the category question exactly where
    /// `.brandMatched` leaves it — on a brand prior.
    case frequented
    /// Apple classified the place — pharmacy, restaurant, gas station — but the name resolves to
    /// no brand we hold.
    ///
    /// Deliberately not folded into `.brandMatched`. That tier means *we recognise this brand*;
    /// this one means *we know what kind of place this is, and not which store it is*. Those are
    /// different claims, and conflating them is what put a POI Apple confidently calls a pharmacy
    /// into `.unknown` — a hard stop no multiplier can reach — while the wallet path was already
    /// treating the same evidence as sufficient to categorise a real logged purchase.
    ///
    /// It reaches the advantage conjunct because the card depends on the category, which this
    /// evidence answers. What it does not answer is identity, which is why it is its own tier
    /// with its own multiplier rather than a promotion to `.brandMatched`.
    case categoryMatched
    /// A bare pin. Was `.low`.
    case unknown
}

/// The winner's advantage over the owner's habitual card, expressed in the two units used by
/// `SwitchThreshold`. Keeping both values together prevents ambient delivery from inventing a
/// second threshold interpretation.
public struct AmbientAdvantage: Codable, Equatable, Sendable {
    public var percentagePoints: Double
    public var cad: Double

    public init(percentagePoints: Double, cad: Double) {
        self.percentagePoints = percentagePoints
        self.cad = cad
    }
}

/// Inputs to the deliberately narrow ambient-notification gate. It is independent of location,
/// notifications, and persistence so the silence-first policy remains exhaustively testable.
public struct AmbientGateInput: Codable, Equatable, Sendable {
    public var merchantConfidence: AmbientMerchantConfidence
    public var recommendedCardId: String
    public var defaultCardId: String
    public var advantage: AmbientAdvantage
    public var switchThreshold: SwitchThreshold
    public var isMuted: Bool

    public init(merchantConfidence: AmbientMerchantConfidence, recommendedCardId: String,
                defaultCardId: String, advantage: AmbientAdvantage,
                switchThreshold: SwitchThreshold, isMuted: Bool) {
        self.merchantConfidence = merchantConfidence
        self.recommendedCardId = recommendedCardId
        self.defaultCardId = defaultCardId
        self.advantage = advantage
        self.switchThreshold = switchThreshold
        self.isMuted = isMuted
    }
}

public enum AmbientSuppressionReason: String, Codable, CaseIterable, Hashable, Sendable {
    case merchantConfidenceLow
    case recommendedDefaultCard
    case advantageBelowSwitchThreshold
    /// An unverified merchant whose advantage cleared the owner's own floor but not the scaled
    /// one. Kept distinct from `advantageBelowSwitchThreshold` so the field-test counters can
    /// separate "the multiplier is too aggressive" from "the owner's threshold is simply high" —
    /// tuning §5's multiplier against evidence needs those two to be tellable apart.
    case advantageBelowUnverifiedThreshold
    case merchantMuted
    /// A frequented merchant whose advantage cleared nothing it needed to clear. Distinct from
    /// `advantageBelowSwitchThreshold` for the same reason the unverified counter is distinct:
    /// it is the only evidence that can say whether `frequentedAdvantageMultiplier` is set
    /// right, and pooling it with the verified tier's misses would answer no question at all.
    case advantageBelowFrequentedThreshold
    /// A place-type arrival whose advantage did not clear its own scaled floor. Distinct from
    /// `advantageBelowUnverifiedThreshold` for the reason that one is distinct from
    /// `advantageBelowSwitchThreshold`: `categoryAdvantageMultiplier` is separately tunable, and
    /// a multiplier whose misses are pooled with another tier's can only be tuned against
    /// evidence that does not belong to it.
    case advantageBelowCategoryThreshold
}

/// How an arrival should reach the owner.
///
/// The gate used to answer one question — interrupt or stay silent — and the Live Activity was
/// started from inside the notification path, so one boolean decided both whether PickMe spoke
/// and whether PickMe was *visible*. That coupling was a consequence of call-site placement, not
/// a policy: it left the owner seeing nothing on most arrivals.
///
/// The tiers are derived from the suppression reasons rather than added alongside them, because
/// the reasons already record the distinction that matters. Two of them are volume judgements
/// ("the answer is: keep going"), one is a correctness stop ("we do not know this merchant"), and
/// one is consent ("you told us to stop"). Those deserve different treatment and the same
/// notification budget cannot express it.
public enum AmbientDeliveryTier: String, Codable, Equatable, Sendable, CaseIterable {
    /// Nothing at all. The owner's explicit instruction, not a volume dial.
    case silent
    /// Visible, but carrying no card advice. Naming a card at a merchant we cannot identify is a
    /// confident wrong answer, which costs trust faster than silence does.
    case presence
    /// Visible and advisory, but never audible: the answer is "stay on the card you were going
    /// to use anyway", which is worth showing and not worth interrupting for.
    case confirm
    /// Sound, time-sensitive banner, and a Live Activity. Reserved for arrivals where switching
    /// cards actually earns money.
    case interrupt
}

/// A decision carries every failed conjunct rather than a single arbitrary first failure. This
/// makes the field-test counters diagnostic while keeping the firing rule a strict conjunction.
public struct AmbientGateDecision: Codable, Equatable, Sendable {
    public let suppressionReasons: Set<AmbientSuppressionReason>

    public init(suppressionReasons: Set<AmbientSuppressionReason>) {
        self.suppressionReasons = suppressionReasons
    }

    /// Precedence: consent, then correctness, then volume. Expressed as ordered checks rather
    /// than as a `Comparable` ranking so that adding a reason forces a decision about where it
    /// sits, instead of defaulting into the quietest tier by accident.
    public var tier: AmbientDeliveryTier {
        if suppressionReasons.contains(.merchantMuted) { return .silent }
        if suppressionReasons.contains(.merchantConfidenceLow) { return .presence }
        return suppressionReasons.isEmpty ? .interrupt : .confirm
    }

    /// Unchanged in meaning: PickMe interrupted. `SuppressionLog` and the TestFlight A3
    /// criterion both read this, and neither is a statement about visibility.
    public var fires: Bool { tier == .interrupt }
}

public enum AmbientGate {
    /// How much more advantage an unverified merchant must show before it earns an interruption.
    ///
    /// A starting guess, not a derived value. The honest justification for a number like this is
    /// the suppression counters: if `advantageBelowUnverifiedThreshold` dominates the log while
    /// the owner keeps confirming those merchants by hand, it is too high; if brand-matched
    /// notifications get muted, too low. It is a constant so that tuning it is one edit with one
    /// test, rather than a policy spread across call sites.
    public static let unverifiedAdvantageMultiplier: Double = 2.0

    /// What a frequented merchant's advantage is scaled by before it is judged.
    ///
    /// 1.0 — the owner's own floor, unscaled — is a judgement, not a measurement, and it is a
    /// constant so that revising it is one edit with one test. The argument for it: the 2.0 above
    /// covers three doubts at once, and patronage retires two of them. What it does not retire is
    /// the third, since the category still comes from a brand prior. If
    /// `advantageBelowFrequentedThreshold` turns out to dominate the counters while the owner
    /// keeps shopping at those merchants, this is too high; if frequented notifications get
    /// muted, too low.
    public static let frequentedAdvantageMultiplier: Double = 1.0

    /// What a place-type arrival's advantage is scaled by.
    ///
    /// Starts equal to `unverifiedAdvantageMultiplier` on purpose: introducing the tier is
    /// already a large behavioural change — arrivals that were a hard stop can now speak — and
    /// bundling a *new* bar into the same change would make the two impossible to tell apart in
    /// the counters. Whether identity-free evidence deserves a different bar from a brand guess
    /// is a question for the field log, not for a second constant chosen the same way the first
    /// one was.
    public static let categoryAdvantageMultiplier: Double = 2.0

    /// A3: fire only for a merchant confident enough to interrupt over, a non-default
    /// recommendation whose advantage clears that merchant's threshold, and a merchant the owner
    /// has not muted.
    public static func evaluate(_ input: AmbientGateInput) -> AmbientGateDecision {
        var reasons = Set<AmbientSuppressionReason>()
        if input.recommendedCardId == input.defaultCardId { reasons.insert(.recommendedDefaultCard) }
        if input.isMuted { reasons.insert(.merchantMuted) }

        // The advantage conjunct is the one place this does NOT report every failure, and the
        // exception is deliberate. `.unknown` is a hard stop: no multiplier makes it fire, so
        // recording "the advantage was also too small" would be noise. Worse, it would be
        // *misleading* noise — `advantageBelowUnverifiedThreshold` exists to tune
        // `unverifiedAdvantageMultiplier`, and mixing in decisions the multiplier cannot affect
        // makes the counter useless for the one job it has.
        switch input.merchantConfidence {
        case .unknown:
            reasons.insert(.merchantConfidenceLow)
        case .verified:
            if !clearsSwitchThreshold(input.advantage, threshold: input.switchThreshold) {
                reasons.insert(.advantageBelowSwitchThreshold)
            }
        case .brandMatched:
            if !clearsSwitchThreshold(input.advantage,
                                      threshold: scaled(input.switchThreshold,
                                                        by: unverifiedAdvantageMultiplier)) {
                reasons.insert(.advantageBelowUnverifiedThreshold)
            }
        case .frequented:
            if !clearsSwitchThreshold(input.advantage,
                                      threshold: scaled(input.switchThreshold,
                                                        by: frequentedAdvantageMultiplier)) {
                reasons.insert(.advantageBelowFrequentedThreshold)
            }
        case .categoryMatched:
            if !clearsSwitchThreshold(input.advantage,
                                      threshold: scaled(input.switchThreshold,
                                                        by: categoryAdvantageMultiplier)) {
                reasons.insert(.advantageBelowCategoryThreshold)
            }
        }

        return AmbientGateDecision(suppressionReasons: reasons)
    }

    /// Scales both floors, leaving `semantics` alone. Scaling only one axis would silently turn
    /// an `either` threshold into a stricter rule on whichever axis was left unscaled.
    static func scaled(_ threshold: SwitchThreshold, by multiplier: Double) -> SwitchThreshold {
        SwitchThreshold(
            minAdvantagePercentagePoints: threshold.minAdvantagePercentagePoints * multiplier,
            minAdvantageCad: threshold.minAdvantageCad * multiplier,
            semantics: threshold.semantics)
    }

    /// Exactly mirrors `RecommendationEngine`'s switch policy: `both` requires both floors;
    /// `either` permits either floor. Equality is a pass in both cases.
    public static func clearsSwitchThreshold(_ advantage: AmbientAdvantage,
                                             threshold: SwitchThreshold) -> Bool {
        let cadOK = advantage.cad >= threshold.minAdvantageCad
        let percentagePointsOK = advantage.percentagePoints >= threshold.minAdvantagePercentagePoints
        return threshold.semantics == "either" ? (cadOK || percentagePointsOK)
                                               : (cadOK && percentagePointsOK)
    }
}

/// Pure counter model for the ambient field test. `suppressed` counts decisions, while the
/// reason counters may total higher when more than one A3 conjunct suppresses one decision.
public struct SuppressionLog: Codable, Equatable, Sendable {
    public private(set) var fired: Int
    public private(set) var suppressed: Int
    public private(set) var suppressedByReason: [AmbientSuppressionReason: Int]

    public init(fired: Int = 0, suppressed: Int = 0,
                suppressedByReason: [AmbientSuppressionReason: Int] = [:]) {
        self.fired = fired
        self.suppressed = suppressed
        self.suppressedByReason = suppressedByReason
    }

    public mutating func record(_ decision: AmbientGateDecision) {
        if decision.fires {
            fired += 1
        } else {
            suppressed += 1
            for reason in decision.suppressionReasons {
                suppressedByReason[reason, default: 0] += 1
            }
        }
    }

    public mutating func merge(_ other: SuppressionLog) {
        fired += other.fired
        suppressed += other.suppressed
        for (reason, count) in other.suppressedByReason {
            suppressedByReason[reason, default: 0] += count
        }
    }
}
