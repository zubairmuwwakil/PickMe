import Foundation

/// Privacy-safe operational counters for the checkout Radar. This model deliberately has no
/// coordinates, merchant identity, query text, or timestamps precise enough to reconstruct a
/// visit. It answers only whether prefetching is buying latency and where requests fail.
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

    var averageTapLatencyMilliseconds: Int? {
        let count = preparedTaps + tapLookups
        return count == 0 ? nil : totalTapLatencyMilliseconds / count
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
        }
        if let data = try? JSONEncoder().encode(metrics) { defaults.set(data, forKey: key) }
    }

    func forgetAll() { defaults.removeObject(forKey: key) }
}
