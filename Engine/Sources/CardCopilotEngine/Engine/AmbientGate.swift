import Foundation

/// Confidence in the local merchant truth graph.
///
/// This was a binary — owner-verified, or not — and the not-verified half was silent. That
/// policy is correct for a wallet built entirely out of terminals the owner has reconciled, and
/// wrong for one that discovers merchants: a discovered POI is never verified, so a strict
/// binary means discovery can never speak.
///
/// The middle rung exists because "the POI is literally named Costco" and "the POI is an
/// unnamed store pin" are not the same guess. The first can be checked against the engine's own
/// brand vocabulary (`canonicalEngineBrand`); the second cannot be checked against anything.
public enum AmbientMerchantConfidence: String, Codable, Equatable, Sendable {
    /// The owner reconciled THIS terminal against a statement. Was `.high`.
    case verified
    /// A POI whose name resolves to a brand the catalogue knows. A guess, but a checkable one.
    case brandMatched
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
}

/// A decision carries every failed conjunct rather than a single arbitrary first failure. This
/// makes the field-test counters diagnostic while keeping the firing rule a strict conjunction.
public struct AmbientGateDecision: Codable, Equatable, Sendable {
    public let suppressionReasons: Set<AmbientSuppressionReason>

    public init(suppressionReasons: Set<AmbientSuppressionReason>) {
        self.suppressionReasons = suppressionReasons
    }

    public var fires: Bool { suppressionReasons.isEmpty }
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
            if !clearsSwitchThreshold(input.advantage, threshold: scaled(input.switchThreshold)) {
                reasons.insert(.advantageBelowUnverifiedThreshold)
            }
        }

        return AmbientGateDecision(suppressionReasons: reasons)
    }

    /// Scales both floors, leaving `semantics` alone. Scaling only one axis would silently turn
    /// an `either` threshold into a stricter rule on whichever axis was left unscaled.
    static func scaled(_ threshold: SwitchThreshold) -> SwitchThreshold {
        SwitchThreshold(
            minAdvantagePercentagePoints: threshold.minAdvantagePercentagePoints * unverifiedAdvantageMultiplier,
            minAdvantageCad: threshold.minAdvantageCad * unverifiedAdvantageMultiplier,
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
