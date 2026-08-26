import Foundation

/// Everything that produced one card's score, frozen at the moment it was produced.
///
/// This exists because `StoredPrediction` is the append-only log the accuracy claim is measured
/// against, and it recorded only the *outputs* of a decision. That was implicitly safe while the
/// catalogue could change only when the binary changed. Remote catalogue delivery ends that, so
/// the inputs have to travel with the row.
///
/// Declared in Engine rather than Store because it describes contract semantics. Store persists
/// it as opaque `Data` and never reasons about its contents.
///
/// `snapshotVersion` evolves in Swift, independently of the SwiftData schema. Adding a field here
/// is a decoder change, never a store migration — which is the whole reason this is a blob and
/// not a widening set of columns.
public struct ScoredRuleSnapshot: Codable, Equatable, Sendable {

    /// Bump when fields are added. Decoders must tolerate reading an older version.
    public static let currentVersion = 1

    public var snapshotVersion: Int
    /// The date the rules were resolved against — the same `asOf` handed to
    /// `RecommendationEngine.recommend(_:asOf:)`.
    public var asOf: String
    public var cardId: String

    /// The rule that won, frozen whole.
    ///
    /// Stored as the entire `EarnRule` rather than a summary of its fields: it is the actual
    /// input the scorer consumed, so a summary could only ever drift from what happened. Nil when
    /// the card was excluded before any rule matched.
    public var appliedRule: EarnRule?

    /// The valuation in force at scoring time. A later valuation change must not retroactively
    /// rewrite what past advice was based on.
    public var programId: String
    public var unit: String
    public var centsPerPoint: Double?

    public var rewardUnits: Double
    public var grossRewardCad: Double
    public var fxCostCad: Double
    public var netValueCad: Double
    public var floorNetValueCad: Double
    public var aspirationalNetValueCad: Double

    public var warnings: [Warning]
    public var excluded: Bool
    public var exclusionReason: String?

    public init(snapshotVersion: Int = ScoredRuleSnapshot.currentVersion,
                asOf: String, cardId: String, appliedRule: EarnRule?,
                programId: String, unit: String, centsPerPoint: Double?,
                rewardUnits: Double, grossRewardCad: Double, fxCostCad: Double,
                netValueCad: Double, floorNetValueCad: Double, aspirationalNetValueCad: Double,
                warnings: [Warning], excluded: Bool, exclusionReason: String?) {
        self.snapshotVersion = snapshotVersion
        self.asOf = asOf
        self.cardId = cardId
        self.appliedRule = appliedRule
        self.programId = programId
        self.unit = unit
        self.centsPerPoint = centsPerPoint
        self.rewardUnits = rewardUnits
        self.grossRewardCad = grossRewardCad
        self.fxCostCad = fxCostCad
        self.netValueCad = netValueCad
        self.floorNetValueCad = floorNetValueCad
        self.aspirationalNetValueCad = aspirationalNetValueCad
        self.warnings = warnings
        self.excluded = excluded
        self.exclusionReason = exclusionReason
    }

    /// Builds a snapshot from a score and the card it scored.
    ///
    /// Resolves the applied rule out of the card by id rather than taking it as a parameter, so
    /// the frozen rule is always the one the catalogue actually held for that id at this moment.
    public static func capture(score: CandidateScore, card: CardProduct, asOf: String,
                               programId: String, unit: String,
                               centsPerPoint: Double?) -> ScoredRuleSnapshot {
        let rule = score.appliedRuleId.flatMap { id in
            card.earnRules.first { $0.ruleId == id }
        }
        return ScoredRuleSnapshot(
            asOf: asOf, cardId: score.cardId, appliedRule: rule,
            programId: programId, unit: unit, centsPerPoint: centsPerPoint,
            rewardUnits: score.rewardUnits, grossRewardCad: score.grossRewardCad,
            fxCostCad: score.fxCostCad, netValueCad: score.netValueCad,
            floorNetValueCad: score.floorNetValueCad,
            aspirationalNetValueCad: score.aspirationalNetValueCad,
            warnings: score.warnings, excluded: score.excluded,
            exclusionReason: score.exclusionReason)
    }
}
