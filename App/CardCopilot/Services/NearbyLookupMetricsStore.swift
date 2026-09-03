import Foundation

/// How many places one scan returned, coarsened.
///
/// Bucketed rather than exact on purpose. An exact result count per scan, accumulated over a
/// fortnight, is a shape that could be matched back to particular plazas; a bucket answers "is the
/// response being truncated" without describing any one of them.
enum NearbyResultBucket: String, Codable, Equatable, CaseIterable {
    case none = "0"
    case oneOrTwo = "1-2"
    case threeToFive = "3-5"
    case sixToTen = "6-10"
    case elevenToTwenty = "11-20"
    case moreThanTwenty = "21+"

    init(count: Int) {
        switch count {
        case ..<1: self = .none
        case ..<3: self = .oneOrTwo
        case ..<6: self = .threeToFive
        case ..<11: self = .sixToTen
        case ..<21: self = .elevenToTwenty
        default: self = .moreThanTwenty
        }
    }
}

/// Privacy-safe operational counters for the checkout Radar. This model deliberately has no
/// coordinates, merchant identity, query text, or timestamps precise enough to reconstruct a
/// visit. It answers only whether prefetching is buying latency and where requests fail.
///
/// The Radar counters below hold to the same rule. Which chain was recognised, and where, lives
/// in the `FIELD_DIAGNOSTICS` record log and nowhere near here — a counter says how often, the
/// record says what happened that time, and neither is derived from the other.
struct NearbyLookupMetrics: Codable, Equatable {
    var prefetchAttempts = 0
    var movementCacheHits = 0
    var preparedTaps = 0
    var tapLookups = 0
    var locationTimeouts = 0
    var merchantTimeouts = 0
    var emptyResults = 0
    var failures = 0
    var totalTapLatencyMilliseconds = 0
    var maximumTapLatencyMilliseconds = 0

    /// Scans that actually issued a query. A movement-cache hit is not one.
    var radarScans = 0
    /// What MapKit returned before `rankNearbyMerchants` deduped, and what survived. Both, because
    /// a cap that truncates upstream is invisible once the list is deduped.
    var radarRawResultBuckets: [NearbyResultBucket: Int] = [:]
    var radarDedupedResultBuckets: [NearbyResultBucket: Int] = [:]
    /// Scans in which at least one candidate resolved to a `CanadianMerchantPreIndex` row. The
    /// denominator for "was the anchor tenant returned at all"; low against `radarScans` says the
    /// result set is the mechanism.
    var radarScansWithARecognisedChain = 0
    /// **The counter that decides which of the two fixes is needed.** A recognised chain was in
    /// the set and something else was ranked above it. Result-set truncation cannot produce that;
    /// a pin sitting at a building centroid can.
    var radarScansWhereTopRankedMissedAChain = 0

    var averageTapLatencyMilliseconds: Int? {
        let count = preparedTaps + tapLookups
        return count == 0 ? nil : totalTapLatencyMilliseconds / count
    }

    init() {}

    /// Tolerant of a blob written before a counter existed.
    ///
    /// **The counter is only interpretable against the weeks before it existed.** This is a single
    /// value in `UserDefaults` and `snapshot` reads a decode failure as all-zeroes, so a
    /// synthesized decoder — which throws on a missing key even where the property has a default —
    /// would silently delete that baseline the first time this build ran. `AmbientCoverageLog` and
    /// `AmbientVisit` carry the same decoder for the same reason.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int {
            try container.decodeIfPresent(Int.self, forKey: key) ?? 0
        }
        prefetchAttempts = try count(.prefetchAttempts)
        movementCacheHits = try count(.movementCacheHits)
        preparedTaps = try count(.preparedTaps)
        tapLookups = try count(.tapLookups)
        locationTimeouts = try count(.locationTimeouts)
        merchantTimeouts = try count(.merchantTimeouts)
        emptyResults = try count(.emptyResults)
        failures = try count(.failures)
        totalTapLatencyMilliseconds = try count(.totalTapLatencyMilliseconds)
        maximumTapLatencyMilliseconds = try count(.maximumTapLatencyMilliseconds)
        radarScans = try count(.radarScans)
        radarRawResultBuckets = try container.decodeIfPresent(
            [NearbyResultBucket: Int].self, forKey: .radarRawResultBuckets) ?? [:]
        radarDedupedResultBuckets = try container.decodeIfPresent(
            [NearbyResultBucket: Int].self, forKey: .radarDedupedResultBuckets) ?? [:]
        radarScansWithARecognisedChain = try count(.radarScansWithARecognisedChain)
        radarScansWhereTopRankedMissedAChain = try count(.radarScansWhereTopRankedMissedAChain)
    }
}

@MainActor
final class NearbyLookupMetricsStore {
    enum Event {
        case prefetchAttempt
        case movementCacheHit
        case tap(prepared: Bool, durationMilliseconds: Int)
        case locationTimeout
        case merchantTimeout
        case emptyResult
        case failure
        /// One Radar query, reduced to counts. The identity-bearing version of this scan — which
        /// chain, where, ranked how — is the field-log record, and the two are never derived from
        /// each other.
        case radarScan(rawResultCount: Int, dedupedResultCount: Int,
                       containedRecognisedChain: Bool, topRankedMissedARecognisedChain: Bool)
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "nearbyLookupMetrics.v1") {
        self.defaults = defaults
        self.key = key
    }

    var snapshot: NearbyLookupMetrics {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(NearbyLookupMetrics.self, from: data) else {
            return NearbyLookupMetrics()
        }
        return decoded
    }

    func record(_ event: Event) {
        var metrics = snapshot
        switch event {
        case .prefetchAttempt:
            metrics.prefetchAttempts += 1
        case .movementCacheHit:
            metrics.movementCacheHits += 1
        case .tap(let prepared, let duration):
            if prepared { metrics.preparedTaps += 1 } else { metrics.tapLookups += 1 }
            let safeDuration = max(0, duration)
            metrics.totalTapLatencyMilliseconds += safeDuration
            metrics.maximumTapLatencyMilliseconds = max(metrics.maximumTapLatencyMilliseconds,
                                                         safeDuration)
        case .locationTimeout:
            metrics.locationTimeouts += 1
        case .merchantTimeout:
            metrics.merchantTimeouts += 1
        case .emptyResult:
            metrics.emptyResults += 1
        case .failure:
            metrics.failures += 1
        case .radarScan(let raw, let deduped, let containedChain, let topRankedMissed):
            metrics.radarScans += 1
            metrics.radarRawResultBuckets[NearbyResultBucket(count: raw), default: 0] += 1
            metrics.radarDedupedResultBuckets[NearbyResultBucket(count: deduped),
                                              default: 0] += 1
            if containedChain { metrics.radarScansWithARecognisedChain += 1 }
            if topRankedMissed { metrics.radarScansWhereTopRankedMissedAChain += 1 }
        }
        if let data = try? JSONEncoder().encode(metrics) { defaults.set(data, forKey: key) }
    }

    func forgetAll() { defaults.removeObject(forKey: key) }
}
