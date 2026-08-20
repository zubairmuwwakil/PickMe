import Foundation

/// What this engine build can actually do. Earn rules declare what they need; a rule needing
/// something absent here is skipped with a warning rather than scored wrongly.
///
/// Replaces the hand-set `scoredInV1` boolean, which had no machine meaning: nothing checked that
/// a rule marked true was supported, and enabling a capability meant hunting the catalogue for
/// every flag to flip. Adding a case here turns on every rule that declared it, with no catalogue
/// edit — the maintenance burden inverts from O(rules) to O(capabilities).
public enum EngineCapability: String, CaseIterable, Codable, Sendable {
    case capCalendarMonth    = "cap.calendarMonth"
    case capCalendarYear     = "cap.calendarYear"
    case capAccountYear      = "cap.accountYear"
    case capStatementYear    = "cap.statementYear"
    case capGlobalGroup      = "cap.globalGroup"
    case merchantPartnerList = "predicate.merchantPartnerList"
    case mccStrict           = "predicate.mccStrict"
    case unitPerLitre        = "earn.perLitre"
    case marginalEarn        = "earn.marginal"

    /// Capabilities this build implements. The rest are declared so rules can name them and turn
    /// on automatically when they ship. `predicate.channelIdentity` is deliberately absent from
    /// this enum entirely — online booking channels are permanently out of scope for an
    /// at-the-register copilot, so rules needing them use `outOfScope`, not `requires`.
    public static let supported: Set<EngineCapability> = [
        .capCalendarMonth, .capCalendarYear, .capAccountYear,
    ]
}

/// A rule that will never be scored, with the reason. Distinct from `requires`, which means
/// "not yet". Collapsing the two is how someone later builds a capability that was ruled out.
public struct OutOfScope: Codable, Equatable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}
