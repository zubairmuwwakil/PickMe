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
    /// …of which iOS never delivered a wake for, and the app had to ask about.
    ///
    /// `didEnterRegion` fires only on a boundary *crossing*, so a region registered while the
    /// owner is already inside it cannot fire for the visit that created it — and `rotateRegions`
    /// runs off a significant location change, which is roughly the event that happens when
    /// someone arrives somewhere new. The first visit to any newly discovered place was silent by
    /// construction, and invisible to `arrivals`, which counts wakes that happened.
    ///
    /// Counted separately rather than folded in: the difference between the two totals is the
    /// size of that problem, and pooling them erases the only evidence that asking helped.
    public private(set) var arrivalsSynthesised: Int

    /// What became of each arrival's notification. **"Fired" only ever counted that iOS accepted
    /// a request**, which cannot separate an alert the app never asked for, one iOS refused, one
    /// that never reached Notification Center, and one the owner simply missed. Those are four
    /// different faults with four different fixes, and this is the counter that tells them apart.
    ///
    /// No identity, no timing — just how many of each, per day, like every other counter here.
    public private(set) var notificationDeliveryByOutcome: [ArrivalNotificationDelivery: Int]

    // MARK: - What monitoring costs
    //
    // The only counters here that speak to whether ambient monitoring is affordable at all. A
    // battery cost found in week one is a design input; the same cost found after launch is a
    // review.
    //
    // Deliberately totals and not a list. A list of wake durations with the days they fell on is
    // a movement trace — it says when the owner left the house — while a daily sum is a battery
    // bill and says nothing about where anyone was.

    public private(set) var wakesByCause: [AmbientWakeCause: Int]
    /// Wall-clock milliseconds awake, summed per cause.
    public private(set) var wakeMillisecondsByCause: [AmbientWakeCause: Int]
    /// The single longest wake of the day. Merged as a maximum, never a sum: adding two days'
    /// maxima would report a wake nobody ever had.
    public private(set) var longestWakeMilliseconds: Int
    /// Whether each wake asked for an arrival fix, and whether it got one. A wake that spent its
    /// whole window waiting for a fix that never came is the expensive kind; one that never asked
    /// is nearly free, and pooling them hides which sort the battery is going on.
    public private(set) var wakeFixOutcomes: [AmbientWakeFixOutcome: Int]

    public init(rotations: Int = 0, rotationsAtCapacity: Int = 0,
                evictedByTier: [AmbientRegionTier: Int] = [:],
                arrivals: Int = 0, arrivalsUnresolved: Int = 0, arrivalsNotAdvised: Int = 0,
                arrivalsSynthesised: Int = 0,
                notificationDeliveryByOutcome: [ArrivalNotificationDelivery: Int] = [:],
                wakesByCause: [AmbientWakeCause: Int] = [:],
                wakeMillisecondsByCause: [AmbientWakeCause: Int] = [:],
                longestWakeMilliseconds: Int = 0,
                wakeFixOutcomes: [AmbientWakeFixOutcome: Int] = [:]) {
        self.rotations = rotations
        self.rotationsAtCapacity = rotationsAtCapacity
        self.evictedByTier = evictedByTier
        self.arrivals = arrivals
        self.arrivalsUnresolved = arrivalsUnresolved
        self.arrivalsNotAdvised = arrivalsNotAdvised
        self.arrivalsSynthesised = arrivalsSynthesised
        self.notificationDeliveryByOutcome = notificationDeliveryByOutcome
        self.wakesByCause = wakesByCause
        self.wakeMillisecondsByCause = wakeMillisecondsByCause
        self.longestWakeMilliseconds = longestWakeMilliseconds
        self.wakeFixOutcomes = wakeFixOutcomes
    }

    /// Tolerant of days recorded before a counter existed.
    ///
    /// These are persisted per day in `UserDefaults` and summed over a rolling week. A
    /// synthesized decoder would throw on every day written by an earlier build, and
    /// `DailyLogStore` would read that as an empty history — deleting the baseline a new counter
    /// exists to be compared against.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rotations = try container.decodeIfPresent(Int.self, forKey: .rotations) ?? 0
        rotationsAtCapacity = try container.decodeIfPresent(Int.self,
                                                            forKey: .rotationsAtCapacity) ?? 0
        evictedByTier = try container.decodeIfPresent([AmbientRegionTier: Int].self,
                                                      forKey: .evictedByTier) ?? [:]
        arrivals = try container.decodeIfPresent(Int.self, forKey: .arrivals) ?? 0
        arrivalsUnresolved = try container.decodeIfPresent(Int.self,
                                                           forKey: .arrivalsUnresolved) ?? 0
        arrivalsNotAdvised = try container.decodeIfPresent(Int.self,
                                                           forKey: .arrivalsNotAdvised) ?? 0
        arrivalsSynthesised = try container.decodeIfPresent(Int.self,
                                                            forKey: .arrivalsSynthesised) ?? 0
        notificationDeliveryByOutcome = try container.decodeIfPresent(
            [ArrivalNotificationDelivery: Int].self,
            forKey: .notificationDeliveryByOutcome) ?? [:]
        wakesByCause = try container.decodeIfPresent([AmbientWakeCause: Int].self,
                                                     forKey: .wakesByCause) ?? [:]
        wakeMillisecondsByCause = try container.decodeIfPresent(
            [AmbientWakeCause: Int].self, forKey: .wakeMillisecondsByCause) ?? [:]
        longestWakeMilliseconds = try container.decodeIfPresent(
            Int.self, forKey: .longestWakeMilliseconds) ?? 0
        wakeFixOutcomes = try container.decodeIfPresent([AmbientWakeFixOutcome: Int].self,
                                                        forKey: .wakeFixOutcomes) ?? [:]
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

    /// Arrivals the gate decided were worth interrupting for, whatever became of the request.
    public var notificationsRequested: Int {
        notificationDeliveryByOutcome
            .filter { $0.key != .neverRequested }
            .values.reduce(0, +)
    }

    /// …of which the alert was actually in Notification Center when it was looked for. **The
    /// number the investigation turns on**: a large gap between these two is a delivery defect,
    /// and no gap at all means the silence was policy and the gate is where to look.
    public var notificationsThatLanded: Int {
        notificationDeliveryByOutcome[.acceptedAndPresent] ?? 0
    }

    public var wakes: Int { wakesByCause.values.reduce(0, +) }

    public var totalWakeMilliseconds: Int { wakeMillisecondsByCause.values.reduce(0, +) }

    /// Nil rather than zero for a cause that never woke: "never happened" and "happened and took
    /// no time" are different readings, and only one of them is good news.
    public func averageWakeMilliseconds(for cause: AmbientWakeCause) -> Int? {
        guard let count = wakesByCause[cause], count > 0 else { return nil }
        return (wakeMillisecondsByCause[cause] ?? 0) / count
    }

    // MARK: - Recording

    public mutating func record(_ allocation: RegionAllocation) {
        rotations += 1
        if allocation.isAtCapacity { rotationsAtCapacity += 1 }
        for candidate in allocation.evicted {
            evictedByTier[candidate.tier, default: 0] += 1
        }
    }

    public mutating func recordArrival(_ outcome: AmbientArrivalOutcome,
                                       source: AmbientArrivalSource = .regionEntry) {
        arrivals += 1
        if source == .alreadyInside { arrivalsSynthesised += 1 }
        switch outcome {
        case .resolved: break
        case .unresolved: arrivalsUnresolved += 1
        case .notAdvised: arrivalsNotAdvised += 1
        }
    }

    /// Recorded for every arrival, including the ones the gate never spoke on — `.neverRequested`
    /// is the denominator that makes the other three readable as a rate.
    public mutating func recordNotificationDelivery(_ outcome: ArrivalNotificationDelivery) {
        notificationDeliveryByOutcome[outcome, default: 0] += 1
    }

    /// A negative duration is a clock artefact, not a wake that ran backwards; letting one
    /// through would drag the daily total below what was actually spent.
    public mutating func recordWake(_ cause: AmbientWakeCause, durationMilliseconds: Int) {
        let duration = max(0, durationMilliseconds)
        wakesByCause[cause, default: 0] += 1
        wakeMillisecondsByCause[cause, default: 0] += duration
        longestWakeMilliseconds = max(longestWakeMilliseconds, duration)
    }

    public mutating func recordWakeFixOutcome(_ outcome: AmbientWakeFixOutcome) {
        wakeFixOutcomes[outcome, default: 0] += 1
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
        arrivalsSynthesised += other.arrivalsSynthesised
        for (outcome, count) in other.notificationDeliveryByOutcome {
            notificationDeliveryByOutcome[outcome, default: 0] += count
        }
        for (cause, count) in other.wakesByCause {
            wakesByCause[cause, default: 0] += count
        }
        for (cause, milliseconds) in other.wakeMillisecondsByCause {
            wakeMillisecondsByCause[cause, default: 0] += milliseconds
        }
        // A maximum, not a sum. Adding two days' longest wakes reports one nobody ever had.
        longestWakeMilliseconds = max(longestWakeMilliseconds, other.longestWakeMilliseconds)
        for (outcome, count) in other.wakeFixOutcomes {
            wakeFixOutcomes[outcome, default: 0] += count
        }
    }
}

/// How an arrival came to be evaluated.
///
/// Not a quality judgement: a synthesised arrival is exactly as real a visit as a delivered one.
/// It is a provenance mark, so the field log and the counters can say which arrivals iOS would
/// never have mentioned.
public enum AmbientArrivalSource: String, Codable, Equatable, Sendable {
    /// iOS delivered `didEnterRegion` — the owner crossed a boundary.
    case regionEntry
    /// `requestState(for:)` reported `.inside` for a region just registered around the owner.
    case alreadyInside
    /// Not an arrival at all: the owner tapped Radar and the foreground scan ran. Carried on the
    /// same enum because the field log records both, and the one question worth asking of the
    /// log — which storefronts were on the table and which one was named — is the same question
    /// in both directions. Every counter that means "a geofence fired" must exclude it.
    case radar
}

/// Why iOS woke the app in the background.
///
/// Counted apart because they are not interchangeable. A region entry is the app doing the job it
/// exists for; a significant-change wake that only re-aims geofences is pure overhead, and a
/// synthesis wake is the app asking a question iOS did not volunteer.
public enum AmbientWakeCause: String, Codable, Equatable, Sendable, CaseIterable {
    /// `didEnterRegion` — the owner crossed into a monitored region.
    case regionEntry
    /// `didExitRegion`, which closes a visit and settles dwell.
    case regionExit
    /// `didUpdateLocations` on the significant-change service: refresh discovery, re-aim regions.
    case significantChange
    /// `didDetermineState` reported `.inside` for a region registered around the owner, and the
    /// app turned it into an arrival iOS would never have delivered.
    case stateSynthesis
}

/// Whether a wake asked iOS where the owner was, and whether it found out.
public enum AmbientWakeFixOutcome: String, Codable, Equatable, Sendable, CaseIterable {
    case fixLanded
    /// Asked, and the window closed — or CoreLocation reported the fix invalid, which is the same
    /// answer for the arrival's purposes and the same cost in battery.
    case fixUnavailable
    /// Never asked. An exit or a discovery refresh needs no arrival fix, and counting those with
    /// the timeouts would make the expensive case look routine.
    case notRequested
}

/// How far one geofence entry got. Named for the dropout, not the cause, because the causes are
/// several and the counters exist to say which stage is leaking.
public enum AmbientArrivalOutcome: Equatable, Sendable {
    /// Reached `AmbientGate`. Whether it fired is `SuppressionLog`'s business, not this one's.
    case resolved
    case unresolved
    case notAdvised
}
