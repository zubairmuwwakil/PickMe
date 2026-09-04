import XCTest
import CardCopilotStore
@testable import CardCopilot

/// The Radar counters, on the store that already holds the Radar's operational counters.
///
/// A fourth counter system was recommended against and the owner overrode that, so these go where
/// the existing ones are rather than into a parallel store — and they keep its stated privacy
/// property: no coordinates, no identity, no query text, no timestamps precise enough to
/// reconstruct a visit. Everything identity-bearing lives in the `FIELD_DIAGNOSTICS` record log.
@MainActor
final class RadarMetricsTests: XCTestCase {

    private func makeStore() -> NearbyLookupMetricsStore {
        NearbyLookupMetricsStore(
            defaults: UserDefaults(suiteName: "RadarMetrics.\(UUID().uuidString)")!)
    }

    // MARK: - Buckets

    /// Bucketed, not exact. An exact result count per scan, accumulated, is a shape that could be
    /// matched back to particular plazas; a bucket answers "is the response being truncated"
    /// without describing any one of them.
    func testResultCountsBucketAtTheBoundaries() {
        XCTAssertEqual(NearbyResultBucket(count: 0), .none)
        XCTAssertEqual(NearbyResultBucket(count: 1), .oneOrTwo)
        XCTAssertEqual(NearbyResultBucket(count: 2), .oneOrTwo)
        XCTAssertEqual(NearbyResultBucket(count: 3), .threeToFive)
        XCTAssertEqual(NearbyResultBucket(count: 5), .threeToFive)
        XCTAssertEqual(NearbyResultBucket(count: 6), .sixToTen)
        XCTAssertEqual(NearbyResultBucket(count: 10), .sixToTen)
        XCTAssertEqual(NearbyResultBucket(count: 11), .elevenToTwenty)
        XCTAssertEqual(NearbyResultBucket(count: 20), .elevenToTwenty)
        XCTAssertEqual(NearbyResultBucket(count: 21), .moreThanTwenty)
    }

    // MARK: - Recording

    /// Raw and deduped separately. A cap that truncates upstream is invisible once the list is
    /// deduped, and the gap between the two buckets is the whole point of recording both.
    func testAScanIsCountedWithBothItsResultBuckets() {
        let store = makeStore()

        store.record(.radarScan(rawResultCount: 25, dedupedResultCount: 8,
                                containedRecognisedChain: true,
                                topRankedMissedARecognisedChain: false))

        let metrics = store.snapshot
        XCTAssertEqual(metrics.radarScans, 1)
        XCTAssertEqual(metrics.radarRawResultBuckets[.moreThanTwenty], 1)
        XCTAssertEqual(metrics.radarDedupedResultBuckets[.sixToTen], 1)
    }

    /// The denominator for "was the anchor tenant returned at all". Against `radarScans`, a low
    /// figure here says the result set is the mechanism.
    func testScansContainingARecognisedChainAreCounted() {
        let store = makeStore()

        store.record(.radarScan(rawResultCount: 4, dedupedResultCount: 4,
                                containedRecognisedChain: true,
                                topRankedMissedARecognisedChain: false))
        store.record(.radarScan(rawResultCount: 4, dedupedResultCount: 4,
                                containedRecognisedChain: false,
                                topRankedMissedARecognisedChain: false))

        XCTAssertEqual(store.snapshot.radarScans, 2)
        XCTAssertEqual(store.snapshot.radarScansWithARecognisedChain, 1)
    }

    /// **The counter that decides which of the two fixes is needed.** A chain was in the set and
    /// something else was ranked above it — result-set truncation cannot produce that, and pin
    /// geometry can.
    func testThePinGeometrySignatureIsCountedSeparately() {
        let store = makeStore()

        store.record(.radarScan(rawResultCount: 6, dedupedResultCount: 6,
                                containedRecognisedChain: true,
                                topRankedMissedARecognisedChain: true))
        store.record(.radarScan(rawResultCount: 6, dedupedResultCount: 6,
                                containedRecognisedChain: true,
                                topRankedMissedARecognisedChain: false))

        XCTAssertEqual(store.snapshot.radarScansWithARecognisedChain, 2)
        XCTAssertEqual(store.snapshot.radarScansWhereTopRankedMissedAChain, 1)
    }

    func testCountsAccumulateAcrossScans() {
        let store = makeStore()

        for _ in 0..<3 {
            store.record(.radarScan(rawResultCount: 12, dedupedResultCount: 12,
                                    containedRecognisedChain: true,
                                    topRankedMissedARecognisedChain: true))
        }

        XCTAssertEqual(store.snapshot.radarScans, 3)
        XCTAssertEqual(store.snapshot.radarRawResultBuckets[.elevenToTwenty], 3)
        XCTAssertEqual(store.snapshot.radarScansWhereTopRankedMissedAChain, 3)
    }

    // MARK: - Migration

    /// **The counter is only interpretable against the weeks before it existed.** This blob is a
    /// single value in `UserDefaults` and a decode failure reads as all-zeroes, so a synthesized
    /// decoder — which throws on a missing key even where the property has a default — would
    /// silently delete the baseline the moment this build first ran.
    func testMetricsWrittenBeforeTheRadarCountersExistedStillDecode() throws {
        let defaults = UserDefaults(suiteName: "RadarMetricsLegacy.\(UUID().uuidString)")!
        let legacy = """
        {"prefetchAttempts":12,"movementCacheHits":3,"preparedTaps":7,"tapLookups":2,
         "locationTimeouts":1,"merchantTimeouts":0,"emptyResults":2,"failures":1,
         "totalTapLatencyMilliseconds":4500,"maximumTapLatencyMilliseconds":900}
        """
        defaults.set(Data(legacy.utf8), forKey: "nearbyLookupMetrics.v1")

        let metrics = NearbyLookupMetricsStore(defaults: defaults).snapshot

        XCTAssertEqual(metrics.prefetchAttempts, 12)
        XCTAssertEqual(metrics.emptyResults, 2)
        XCTAssertEqual(metrics.maximumTapLatencyMilliseconds, 900)
        XCTAssertEqual(metrics.radarScans, 0)
        XCTAssertTrue(metrics.radarRawResultBuckets.isEmpty)
    }

    /// The new counters survive a save and reload like the old ones.
    func testTheNewCountersRoundTripThroughDefaults() {
        let defaults = UserDefaults(suiteName: "RadarMetricsRoundTrip.\(UUID().uuidString)")!
        NearbyLookupMetricsStore(defaults: defaults).record(
            .radarScan(rawResultCount: 3, dedupedResultCount: 2,
                       containedRecognisedChain: true, topRankedMissedARecognisedChain: true))

        let reloaded = NearbyLookupMetricsStore(defaults: defaults).snapshot

        XCTAssertEqual(reloaded.radarScans, 1)
        XCTAssertEqual(reloaded.radarRawResultBuckets[.threeToFive], 1)
        XCTAssertEqual(reloaded.radarDedupedResultBuckets[.oneOrTwo], 1)
        XCTAssertEqual(reloaded.radarScansWhereTopRankedMissedAChain, 1)
    }

    /// The privacy property this store's header states, held as a test rather than a comment.
    ///
    /// An allowlist rather than a search for forbidden words: `merchantTimeouts` is a perfectly
    /// good counter name that contains "merchant", so a substring check would either fail on it or
    /// be weakened until it caught nothing. Pinning the whole key set means a field that carries a
    /// coordinate, a name or a timestamp has to be added here deliberately, in a diff someone
    /// reads, rather than arriving as a plausible-looking extra line.
    func testAnEncodedSnapshotCarriesOnlyTheCountersItIsAllowedTo() throws {
        let store = makeStore()
        store.record(.radarScan(rawResultCount: 9, dedupedResultCount: 4,
                                containedRecognisedChain: true,
                                topRankedMissedARecognisedChain: true))

        let encoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(store.snapshot))
        let keys = Set(try XCTUnwrap(encoded as? [String: Any]).keys)

        XCTAssertEqual(keys, [
            "prefetchAttempts", "movementCacheHits", "preparedTaps", "tapLookups",
            "locationTimeouts", "merchantTimeouts", "emptyResults", "failures",
            "totalTapLatencyMilliseconds", "maximumTapLatencyMilliseconds",
            "radarScans", "radarRawResultBuckets", "radarDedupedResultBuckets",
            "radarScansWithARecognisedChain", "radarScansWhereTopRankedMissedAChain",
            "radarEligibilityScans", "radarEligibleResults",
            "radarExcludedPublicTransportResults", "radarExcludedMissingCategoryResults",
            "radarExcludedUnsupportedCategoryResults",
        ])
    }
}
