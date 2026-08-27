import Foundation

/// The third Phase-3 gate criterion. `fired` and `suppressed` already exist on `SuppressionLog`;
/// `coverage` did not, and could not be derived from them.
///
/// `SuppressionLog` records at one point in `evaluateArrival`, behind three earlier `return`s: a
/// geofence must have fired, resolution must have succeeded, and the engine must have advised. It
/// therefore describes the quality of decisions at regions the app WAS monitoring, and is
/// structurally blind to the two silences that matter most:
///
///  1. A merchant that lost its slot in the rotation produces no entry event at all. There is no
///     arrival, no decision, and nothing to count. Slot pressure is invisible to a log that only
///     counts arrivals.
///  2. A background wake that resolved to nothing, or that the engine declined to advise on,
///     returns before recording — so the explainer reports it as though it never happened.
///
/// Both are counted here. Deliberately counters only: no coordinates, no merchant identities, no
/// timestamps beyond the day partition the caller applies. Reading "9 regions with standing were
/// dropped this week" needs none of those, and keeping them would turn a diagnostic into a
/// retention liability — the same argument `MerchantPatronageStore` makes about day keys.
public struct AmbientCoverageLog: Codable, Equatable, Sendable {
    /// Every time the 20-region budget was re-aimed.
    public private(set) var rotations: Int
    /// Of those, how many used every slot. The denominator for "is the cap binding at all?" — if
    /// this stays near zero, frequency-aware ranking is solving a problem the app does not have.
    public private(set) var rotationsAtCapacity: Int
    /// What was dropped, by the tier that lost the slot. The numerator.
    public private(set) var evictedByTier: [AmbientRegionTier: Int]

    /// Geofence entries that reached `evaluateArrival`.
    public private(set) var arrivals: Int
    /// …of which the resolution ladder could name nothing at all. An area whose cached members
    /// have gone stale, or a stored merchant deleted since the region was registered.
    public private(set) var arrivalsUnresolved: Int
    /// …of which the engine declined to advise. Distinct from a *suppressed* decision: the gate
    /// never ran, so no suppression reason describes it.
    public private(set) var arrivalsNotAdvised: Int

    public init(rotations: Int = 0, rotationsAtCapacity: Int = 0,
                evictedByTier: [AmbientRegionTier: Int] = [:],
                arrivals: Int = 0, arrivalsUnresolved: Int = 0, arrivalsNotAdvised: Int = 0) {
        self.rotations = rotations
        self.rotationsAtCapacity = rotationsAtCapacity
        self.evictedByTier = evictedByTier
        self.arrivals = arrivals
        self.arrivalsUnresolved = arrivalsUnresolved
        self.arrivalsNotAdvised = arrivalsNotAdvised
    }

    // MARK: - Derived read-outs
    //
    // Computed here rather than at the call site so the explainer and any future report agree on
    // what the numbers mean. A view re-deriving "how many evictions had standing" by summing two
    // specific tiers is a view that silently stops being correct when a tier is added.

    public var evicted: Int { evictedByTier.values.reduce(0, +) }

    /// Evictions that cost the app evidence the owner actually shops there. **This is the number
    /// the deferred place-level-patronage work turns on.** Zero over a dogfood week means the cap
    /// only ever drops ground the owner has never shopped, and re-ranking slots by frequency
    /// would change nothing.
    public var evictedWithStanding: Int {
        evictedByTier.filter { $0.key.carriesStanding }.values.reduce(0, +)
    }

    /// Arrivals that actually reached `AmbientGate`. `SuppressionLog.fired + .suppressed` should
    /// equal this; a gap means a wake was lost somewhere neither log describes.
    public var arrivalsReachingTheGate: Int {
        arrivals - arrivalsUnresolved - arrivalsNotAdvised
    }

    // MARK: - Recording

    public mutating func record(_ allocation: RegionAllocation) {
        rotations += 1
        if allocation.isAtCapacity { rotationsAtCapacity += 1 }
        for candidate in allocation.evicted {
            evictedByTier[candidate.tier, default: 0] += 1
        }
    }

    public mutating func recordArrival(_ outcome: AmbientArrivalOutcome) {
        arrivals += 1
        switch outcome {
        case .resolved: break
        case .unresolved: arrivalsUnresolved += 1
        case .notAdvised: arrivalsNotAdvised += 1
        }
    }

    /// Mirrors `SuppressionLog.merge` so a seven-day read-out is assembled the same way for both.
    public mutating func merge(_ other: AmbientCoverageLog) {
        rotations += other.rotations
        rotationsAtCapacity += other.rotationsAtCapacity
        for (tier, count) in other.evictedByTier {
            evictedByTier[tier, default: 0] += count
        }
        arrivals += other.arrivals
        arrivalsUnresolved += other.arrivalsUnresolved
        arrivalsNotAdvised += other.arrivalsNotAdvised
    }
}

/// How far one geofence entry got. Named for the dropout, not the cause, because the causes are
/// several and the counters exist to say which stage is leaking.
public enum AmbientArrivalOutcome: Equatable, Sendable {
    /// Reached `AmbientGate`. Whether it fired is `SuppressionLog`'s business, not this one's.
    case resolved
    case unresolved
    case notAdvised
}
