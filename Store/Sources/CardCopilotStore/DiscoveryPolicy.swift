import Foundation

/// Policy for merchant discovery and arrival, kept free of CoreLocation and MapKit so every rule
/// below is testable on macOS without a device. The App target's `AmbientLocationService` is the
/// adapter: frameworks in, these decisions out. No policy lives there.

// MARK: - Spatial cache grid

/// Cell edge in degrees. At Canadian latitudes 0.01° is ~1.11 km north-south and ~0.75 km
/// east-west — close enough to square, and small enough that one MapKit query covers a cell with
/// margin.
public let discoveryCellDegrees: Double = 0.01

/// Quantizes a coordinate onto the discovery grid.
///
/// `.rounded(.down)` rather than `Int()` truncation is load-bearing, not stylistic. Truncation
/// rounds toward zero, so -7938.32 becomes -7938 — the cell to the *east*. Every longitude this
/// app ships to is negative, so truncation would make cells overlap their neighbours across the
/// entire country, and a cached cell would answer for ground it never covered.
public func cellKey(latitude: Double, longitude: Double) -> String {
    let latIndex = Int((latitude / discoveryCellDegrees).rounded(.down))
    let lonIndex = Int((longitude / discoveryCellDegrees).rounded(.down))
    return "\(latIndex)_\(lonIndex)"
}

// MARK: - The query gate

/// Above this, the owner is driving rather than shopping. Highway travel is the single largest
/// generator of significant-location-change events and produces no purchases, so dropping it is
/// nearly free coverage-wise and is the cheapest saving available.
public let discoverySpeedCeilingMetersPerSecond: Double = 8   // ~29 km/h

/// Stores do not move. The TTL exists to notice new openings and closures, not staleness.
public let discoveryCacheTTL: TimeInterval = 30 * 24 * 60 * 60

/// A backstop, not the operating point. Realistic use sits one to three queries per *day*; this
/// exists so a bug in the caller cannot turn into `MKError.loadingThrottled`.
public let discoveryHourlyQueryCeiling: Int = 6

/// What the cache knows about one grid cell. `areaCount == 0` is a real answer, not an absence.
public struct DiscoveryCacheEntry: Equatable, Sendable {
    public let cellKey: String
    public let exploredAt: Date
    public let areaCount: Int

    public init(cellKey: String, exploredAt: Date, areaCount: Int) {
        self.cellKey = cellKey
        self.exploredAt = exploredAt
        self.areaCount = areaCount
    }
}

/// Why discovery did or did not run. Carrying the reason rather than a Bool keeps the caller's
/// diagnostics honest — "we skipped" and "we skipped because we already knew" are different
/// facts, and only one of them suggests the cache is working.
public enum DiscoveryDecision: Equatable, Sendable {
    case query
    case skipMoving
    case skipCached(areaCount: Int)
    case skipRateLimited
}

/// Decides whether a significant location change should spend a MapKit query.
///
/// Order is deliberate. The speed gate runs first because it is a statement about the owner
/// ("not shopping") that holds regardless of what the cache knows, and it is the rule that
/// eliminates the most events. The rate ceiling runs last because reaching it means the earlier
/// rules have already failed to do their job, and the caller should be able to see that.
public func shouldQueryDiscovery(cellKey: String,
                                 cachedEntry: DiscoveryCacheEntry?,
                                 speedMetersPerSecond: Double,
                                 recentQueryTimes: [Date],
                                 now: Date) -> DiscoveryDecision {
    // A negative speed is CoreLocation's "unknown", not a slow one. Blocking on unknown would
    // disable discovery entirely on fixes that omit speed, so it fails open.
    if speedMetersPerSecond >= 0 && speedMetersPerSecond > discoverySpeedCeilingMetersPerSecond {
        return .skipMoving
    }

    if let cachedEntry, cachedEntry.cellKey == cellKey,
       now.timeIntervalSince(cachedEntry.exploredAt) <= discoveryCacheTTL {
        return .skipCached(areaCount: cachedEntry.areaCount)
    }

    let windowStart = now.addingTimeInterval(-3_600)
    if recentQueryTimes.filter({ $0 > windowStart }).count >= discoveryHourlyQueryCeiling {
        return .skipRateLimited
    }

    return .query
}

// MARK: - Exit and dwell

/// Below this, the owner walked past rather than shopped. Chosen, not derived: it is the shortest
/// interval that reliably separates "crossed a plaza" from "bought something" without discarding
/// a genuine quick stop. Field-test data should move it.
public let minimumShoppingDwell: TimeInterval = 4 * 60

/// Above this, the interval is evidence of a missed exit event rather than a long shop. iOS
/// coalesces and delays region exits, and an exit that never arrives leaves the entry timestamp
/// behind; re-entering next week would otherwise compute a week-long dwell.
public let maximumPlausibleDwell: TimeInterval = 6 * 60 * 60

public enum DwellOutcome: Equatable, Sendable {
    /// Too short to be a purchase. No record, no prompt — this is how §8's "log nothing on
    /// arrival" survives contact with a plaza full of overlapping regions.
    case walkBy
    /// Long enough to be a purchase, but the owner never engaged with the arrival notification.
    /// A real visit that has not earned an interruption.
    case silentVisit
    case promptForAmount
    /// The interval is not usable evidence of anything. Discard the timestamp.
    case stranded
}

/// Decides what an area exit means.
///
/// The engagement conjunct is what keeps the exit prompt a follow-up rather than a cold ask, and
/// it is checked last on purpose: a walk-by is a walk-by whether or not the owner tapped
/// something, so duration disqualifies before engagement can qualify.
public func dwellDecision(enteredAt: Date, exitedAt: Date, didEngage: Bool) -> DwellOutcome {
    let dwell = exitedAt.timeIntervalSince(enteredAt)
    guard dwell >= 0, dwell <= maximumPlausibleDwell else { return .stranded }
    guard dwell >= minimumShoppingDwell else { return .walkBy }
    return didEngage ? .promptForAmount : .silentVisit
}

// MARK: - Clustering POIs into monitorable areas

/// Two POIs within this distance belong to the same shopping area.
public let areaClusterRadiusMeters: Double = 200

/// CoreLocation will not reliably monitor a region much tighter than this, and a lone storefront
/// still needs a region that fires.
public let minimumAreaRadiusMeters: Double = 100

/// Past this, "arrival" stops meaning anything — a region spanning a whole power centre fires on
/// the far side of the parking lot. Under-covering the edges of a sprawl is the better failure.
public let maximumAreaRadiusMeters: Double = 400

public struct ShoppingAreaCandidate: Equatable, Sendable {
    public let centroidLatitude: Double
    public let centroidLongitude: Double
    public let radiusMeters: Double
    public let members: [NearbyMerchant]
}

/// Spherical-earth distance. A sphere is wrong by ~0.3% against the WGS-84 ellipsoid, which is
/// far inside the tolerance of a 150 m geofence and avoids depending on CoreLocation here.
public func greatCircleDistanceMeters(fromLatitude lat1: Double, fromLongitude lon1: Double,
                                      toLatitude lat2: Double, toLongitude lon2: Double) -> Double {
    let earthRadius: Double = 6_371_000
    let toRadians = Double.pi / 180
    let dLat = (lat2 - lat1) * toRadians
    let dLon = (lon2 - lon1) * toRadians
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * toRadians) * cos(lat2 * toRadians) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
}

/// Greedy single-pass clustering: take the next unassigned POI, absorb everything within
/// `areaClusterRadiusMeters` of it, repeat.
///
/// Deliberately not k-means or DBSCAN. The output drives geofence registration, which is rebuilt
/// on every rotation — so *stability* matters more than optimality. Seeding from a sorted order
/// makes the result a pure function of the input set rather than of its arrival order, which is
/// what stops a rotation from tearing down and re-registering regions that did not change.
public func clusterIntoAreas(_ merchants: [NearbyMerchant]) -> [ShoppingAreaCandidate] {
    let ordered = merchants.sorted {
        ($0.latitude, $0.longitude, $0.id) < ($1.latitude, $1.longitude, $1.id)
    }
    var unassigned = ordered
    var areas: [ShoppingAreaCandidate] = []

    while let seed = unassigned.first {
        var members: [NearbyMerchant] = []
        var remaining: [NearbyMerchant] = []
        for candidate in unassigned {
            let distance = greatCircleDistanceMeters(fromLatitude: seed.latitude,
                                                     fromLongitude: seed.longitude,
                                                     toLatitude: candidate.latitude,
                                                     toLongitude: candidate.longitude)
            if distance <= areaClusterRadiusMeters { members.append(candidate) }
            else { remaining.append(candidate) }
        }
        unassigned = remaining

        let centroidLat = members.reduce(0) { $0 + $1.latitude } / Double(members.count)
        let centroidLon = members.reduce(0) { $0 + $1.longitude } / Double(members.count)
        let spread = members.map {
            greatCircleDistanceMeters(fromLatitude: centroidLat, fromLongitude: centroidLon,
                                      toLatitude: $0.latitude, toLongitude: $0.longitude)
        }.max() ?? 0
        let radius = min(max(spread + minimumAreaRadiusMeters / 2, minimumAreaRadiusMeters),
                         maximumAreaRadiusMeters)

        areas.append(ShoppingAreaCandidate(centroidLatitude: centroidLat,
                                           centroidLongitude: centroidLon,
                                           radiusMeters: radius,
                                           members: members))
    }
    return areas
}
