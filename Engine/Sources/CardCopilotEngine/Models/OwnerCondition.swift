import Foundation

/// How a condition is answered, and therefore which owner-state field carries the answer.
///
/// `boolean` answers live in `CardState.flags`, keyed by condition id — so a new yes/no condition
/// is an entry in `contracts/owner-conditions.json` and nothing else. `categorySelection` is
/// Tangerine's existing selection machinery, which stays structural because specific engine logic
/// reads it (`selectedCategories`, `treatAsAllSelected`, `thirdCategoryUnlocked`,
/// `nextChangeEffectiveDate`) rather than generic condition resolution. The catalogue-scalability
/// spec (§3.2) draws that line; this enum encodes it so the distinction is checkable rather than
/// remembered.
public enum OwnerConditionAnswerKind: String, Codable, Equatable, Sendable {
    case boolean
    case categorySelection
}

/// One owner condition, as declared in `contracts/owner-conditions.json`.
public struct OwnerCondition: Codable, Equatable, Sendable {
    public var answerKind: OwnerConditionAnswerKind

    /// The ENGLISH SOURCE string, not the display string. Consumers resolve
    /// `ownerCondition.<id>.prompt` from their own string catalogue and fall back to this, so a
    /// new condition ships askable in English the day it lands and picks up translations without
    /// a contract release. Present for every `boolean` condition — the schema requires it, because
    /// a yes/no condition with no question is one nobody can answer.
    public var prompt: String?

    /// What answering buys the owner. Shown beneath the question and in the setup checklist.
    public var detail: String?

    /// `categorySelection` only: how many categories the issuer permits at once.
    public var maxSelections: Int?

    public init(answerKind: OwnerConditionAnswerKind, prompt: String? = nil,
                detail: String? = nil, maxSelections: Int? = nil) {
        self.answerKind = answerKind
        self.prompt = prompt
        self.detail = detail
        self.maxSelections = maxSelections
    }
}

/// The registry file.
///
/// Same shape and role as `ProgramCatalogue`: an open set declared as data, with a machine check
/// that the catalogue never references an entry that is missing. `amazonEligiblePrimeLinked`
/// shipped in the catalogue with no `RuleMatcher` case and no schema complaint, so
/// `amazon-ca-prime-2_5x` could not fire in any build — this file is the half of the problem that
/// opening the schema's vocabulary did not solve.
public struct OwnerConditionRegistry: Codable, Equatable, Sendable {
    public var conditionsVersion: String
    public var conditions: [String: OwnerCondition]

    public init(conditionsVersion: String = "1.0", conditions: [String: OwnerCondition] = [:]) {
        self.conditionsVersion = conditionsVersion
        self.conditions = conditions
    }
}
