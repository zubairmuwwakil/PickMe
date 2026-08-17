import Foundation

/// Confidence in the local merchant truth graph. Ambient recommendations deliberately accept
/// only the terminal-level, owner-verified rung; a brand or MapKit guess is not enough to
/// interrupt the owner.
public enum AmbientMerchantConfidence: String, Codable, Equatable, Sendable {
    case high
    case low
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
    /// A3: fire only for a high-confidence merchant, a non-default recommendation whose
    /// advantage clears the existing switch threshold, and a merchant the owner has not muted.
    public static func evaluate(_ input: AmbientGateInput) -> AmbientGateDecision {
        var reasons = Set<AmbientSuppressionReason>()
        if input.merchantConfidence != .high { reasons.insert(.merchantConfidenceLow) }
        if input.recommendedCardId == input.defaultCardId { reasons.insert(.recommendedDefaultCard) }
        if !clearsSwitchThreshold(input.advantage, threshold: input.switchThreshold) {
            reasons.insert(.advantageBelowSwitchThreshold)
        }
        if input.isMuted { reasons.insert(.merchantMuted) }
        return AmbientGateDecision(suppressionReasons: reasons)
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
