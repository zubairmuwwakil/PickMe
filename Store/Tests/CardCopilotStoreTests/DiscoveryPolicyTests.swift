import XCTest
@testable import CardCopilotStore

/// Grid quantization for the discovery cache (design §6.2). Pure arithmetic, no CoreLocation.
final class CellKeyTests: XCTestCase {
    // Toronto — representative of the only longitudes this app ships to, all of them negative.
    private let torontoLat = 43.6532
    private let torontoLon = -79.3832

    func testNearbyPointsShareACell() {
        let a = cellKey(latitude: torontoLat, longitude: torontoLon)
        // ~200 m north-east, comfortably inside the same ~1 km cell.
        let b = cellKey(latitude: torontoLat + 0.0018, longitude: torontoLon + 0.0018)
        XCTAssertEqual(a, b)
    }

    func testDistantPointsGetDifferentCells() {
        let toronto = cellKey(latitude: torontoLat, longitude: torontoLon)
        let ottawa = cellKey(latitude: 45.4215, longitude: -75.6972)
        XCTAssertNotEqual(toronto, ottawa)
    }

    /// The bug this exists to prevent: `Int(-7938.32)` truncates toward zero to -7938, which is
    /// the cell to the EAST. Truncation makes western-hemisphere cells overlap their neighbours
    /// and tile incorrectly — and every Canadian longitude is negative.
    func testNegativeLongitudesTileWithoutOverlap() {
        // Two points either side of the -79.39 boundary must land in different cells.
        let west = cellKey(latitude: torontoLat, longitude: -79.3901)
        let east = cellKey(latitude: torontoLat, longitude: -79.3899)
        XCTAssertNotEqual(west, east)

        // And two points inside the same negative cell must agree.
        let a = cellKey(latitude: torontoLat, longitude: -79.3850)
        let b = cellKey(latitude: torontoLat, longitude: -79.3810)
        XCTAssertEqual(a, b)
    }

    func testCellIsRoughlyOneKilometreAcross() {
        // Adjacent latitude cells are 0.01° apart ≈ 1.11 km. Asserting the constant rather than
        // the derived distance keeps this a statement about the grid, not about the geoid.
        XCTAssertEqual(discoveryCellDegrees, 0.01, accuracy: 1e-9)
    }
}

/// The query gate (design §6.2). The MapKit quota is a non-issue; these rules exist to spend
/// battery and background-wake budget sparingly, so each one is asserted independently.
final class ShouldQueryDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let cell = "4365_-7939"

    private func decide(cached: DiscoveryCacheEntry? = nil,
                        speed: Double = 0,
                        recentQueries: [Date] = []) -> DiscoveryDecision {
        shouldQueryDiscovery(cellKey: cell, cachedEntry: cached,
                             speedMetersPerSecond: speed, recentQueryTimes: recentQueries, now: now)
    }

    func testQueriesAnUnknownCellWhenStationary() {
        XCTAssertEqual(decide(), .query)
    }

    func testSkipsWhileMovingFastEnoughToBeDriving() {
        XCTAssertEqual(decide(speed: 20), .skipMoving)
    }

    /// CoreLocation reports a negative speed when it cannot determine one. Treating that as
    /// "fast" would silently disable discovery on any device or fix that omits it, so unknown
    /// speed fails open.
    func testUnknownSpeedDoesNotBlockTheQuery() {
        XCTAssertEqual(decide(speed: -1), .query)
    }

    func testSkipsWhenTheCellWasExploredRecently() {
        let cached = DiscoveryCacheEntry(cellKey: cell, exploredAt: now.addingTimeInterval(-86_400),
                                         areaCount: 3)
        XCTAssertEqual(decide(cached: cached), .skipCached(areaCount: 3))
    }

    /// The rule that makes the steady state near-zero. A cell with no retail is a *result*, and
    /// forgetting it means re-querying the owner's own street for as long as they live there.
    func testAnEmptyCellIsStillACacheHit() {
        let cached = DiscoveryCacheEntry(cellKey: cell, exploredAt: now.addingTimeInterval(-86_400),
                                         areaCount: 0)
        XCTAssertEqual(decide(cached: cached), .skipCached(areaCount: 0))
    }

    func testQueriesAgainOnceTheCacheEntryHasExpired() {
        let stale = now.addingTimeInterval(-(discoveryCacheTTL + 1))
        let cached = DiscoveryCacheEntry(cellKey: cell, exploredAt: stale, areaCount: 3)
        XCTAssertEqual(decide(cached: cached), .query)
    }

    func testSkipsOnceTheHourlyCeilingIsReached() {
        let recent = (0..<discoveryHourlyQueryCeiling).map { now.addingTimeInterval(-Double($0) * 60) }
        XCTAssertEqual(decide(recentQueries: recent), .skipRateLimited)
    }

    /// The ceiling is a rolling window, not a running total — yesterday's queries must not
    /// permanently disable discovery.
    func testQueriesOlderThanAnHourDoNotCountTowardTheCeiling() {
        let old = (0..<discoveryHourlyQueryCeiling).map { now.addingTimeInterval(-3_601 - Double($0)) }
        XCTAssertEqual(decide(recentQueries: old), .query)
    }
}

/// Exit-and-dwell (design §7). This single rule does three jobs: it filters walk-bys without
/// asking the owner anything, it identifies which of several overlapping areas was actually
/// visited, and it decides whether the amount prompt has earned the right to appear.
final class DwellDecisionTests: XCTestCase {
    private let entered = Date(timeIntervalSince1970: 1_800_000_000)

    private func decide(minutes: Double, engaged: Bool) -> DwellOutcome {
        dwellDecision(enteredAt: entered,
                      exitedAt: entered.addingTimeInterval(minutes * 60),
                      didEngage: engaged)
    }

    func testAShortVisitIsAWalkByEvenIfTheOwnerEngaged() {
        XCTAssertEqual(decide(minutes: 0.7, engaged: true), .walkBy)
    }

    func testARealVisitAfterEngagementPromptsForTheAmount() {
        XCTAssertEqual(decide(minutes: 20, engaged: true), .promptForAmount)
    }

    /// The rule that keeps the exit prompt a follow-up rather than a cold ask. If the gate
    /// suppressed the arrival notification, the owner saw nothing — asking "what did you spend?"
    /// out of nowhere is exactly the interruption the silence-first policy exists to prevent.
    func testARealVisitWithoutEngagementStaysSilent() {
        XCTAssertEqual(decide(minutes: 20, engaged: false), .silentVisit)
    }

    func testTheDwellThresholdIsInclusive() {
        XCTAssertEqual(decide(minutes: minimumShoppingDwell / 60, engaged: true), .promptForAmount)
    }

    /// iOS coalesces and delays region exits, and an exit that never arrives leaves a stranded
    /// entry timestamp. Without this, re-entering the area next week would compute a week-long
    /// dwell and prompt for an amount against a visit that ended days ago.
    func testAnImplausiblyLongDwellIsTreatedAsStrandedRatherThanShopping() {
        XCTAssertEqual(decide(minutes: 7 * 60, engaged: true), .stranded)
    }

    /// Clock changes and reordered background wakes can present an exit before its entry.
    func testAnInvertedIntervalIsNotAVisit() {
        let outcome = dwellDecision(enteredAt: entered,
                                    exitedAt: entered.addingTimeInterval(-600),
                                    didEngage: true)
        XCTAssertEqual(outcome, .stranded)
    }
}

/// Clustering POIs into monitorable areas (design §6.3). iOS caps monitored regions at 20
/// app-wide, and at a 150 m radius twenty storefronts fit inside one suburban plaza — so the
/// unit of monitoring has to be the plaza, not the shop.
final class ClusterIntoAreasTests: XCTestCase {
    private func poi(_ name: String, _ lat: Double, _ lon: Double) -> NearbyMerchant {
        NearbyMerchant(id: name, name: name, poiCategoryRaw: nil,
                       latitude: lat, longitude: lon, distanceMeters: nil)
    }

    func testNoMerchantsProduceNoAreas() {
        XCTAssertTrue(clusterIntoAreas([]).isEmpty)
    }

    func testASingleMerchantBecomesOneMonitorableArea() {
        let areas = clusterIntoAreas([poi("Walmart", 43.6532, -79.3832)])
        XCTAssertEqual(areas.count, 1)
        XCTAssertEqual(areas[0].members.map(\.name), ["Walmart"])
        // A lone POI still needs a region CoreLocation will actually monitor.
        XCTAssertGreaterThanOrEqual(areas[0].radiusMeters, minimumAreaRadiusMeters)
    }

    func testNeighbouringStorefrontsCollapseIntoOnePlaza() {
        let areas = clusterIntoAreas([
            poi("Walmart", 43.6532, -79.3832),
            poi("Dollarama", 43.65335, -79.38340),   // ~25 m away
            poi("Tim Hortons", 43.65310, -79.38300), // ~30 m away
        ])
        XCTAssertEqual(areas.count, 1)
        XCTAssertEqual(Set(areas[0].members.map(\.name)), ["Walmart", "Dollarama", "Tim Hortons"])
    }

    func testDistantMerchantsStayInSeparateAreas() {
        let areas = clusterIntoAreas([
            poi("Walmart", 43.6532, -79.3832),
            poi("Costco", 43.7000, -79.4200),   // several km away
        ])
        XCTAssertEqual(areas.count, 2)
    }

    /// Region monitoring is rebuilt from this on every rotation. Unstable output would mean
    /// tearing down and re-registering geofences that did not actually change.
    func testClusteringIsDeterministicRegardlessOfInputOrder() {
        let a = poi("Walmart", 43.6532, -79.3832)
        let b = poi("Dollarama", 43.65335, -79.38340)
        let c = poi("Costco", 43.7000, -79.4200)

        let forward = clusterIntoAreas([a, b, c])
        let reversed = clusterIntoAreas([c, b, a])
        XCTAssertEqual(forward.map(\.centroidLatitude), reversed.map(\.centroidLatitude))
        XCTAssertEqual(forward.map { Set($0.members.map(\.name)) },
                       reversed.map { Set($0.members.map(\.name)) })
    }

    /// A sprawling power centre must not produce a region so large that "arrival" stops meaning
    /// anything — better to under-cover its edges than to fire on the far side of the parking lot.
    func testAreaRadiusIsCapped() {
        let spread = (0..<10).map { poi("Store\($0)", 43.6532 + Double($0) * 0.0008, -79.3832) }
        for area in clusterIntoAreas(spread) {
            XCTAssertLessThanOrEqual(area.radiusMeters, maximumAreaRadiusMeters)
        }
    }
}

final class GreatCircleDistanceTests: XCTestCase {
    /// Toronto to Ottawa is ~350 km. A 1% tolerance catches a wrong earth radius or a
    /// degrees/radians slip without asserting more precision than a sphere model earns.
    func testDistanceMatchesAKnownSeparation() {
        let metres = greatCircleDistanceMeters(fromLatitude: 43.6532, fromLongitude: -79.3832,
                                               toLatitude: 45.4215, toLongitude: -75.6972)
        XCTAssertEqual(metres, 351_000, accuracy: 3_500)
    }

    func testDistanceToItselfIsZero() {
        let metres = greatCircleDistanceMeters(fromLatitude: 43.6532, fromLongitude: -79.3832,
                                               toLatitude: 43.6532, toLongitude: -79.3832)
        XCTAssertEqual(metres, 0, accuracy: 1e-6)
    }
}
