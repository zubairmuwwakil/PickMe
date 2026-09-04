import XCTest
import SwiftData
@testable import CardCopilotStore

/// Persistence for the spatial cache (design §6.2). The policy that decides *whether* to query
/// lives in DiscoveryPolicy; this is only the store behind it.
final class DiscoveryCacheTests: XCTestCase {
    var container: ModelContainer!
    var cache: DiscoveryCache!

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let torontoLat = 43.6532
    private let torontoLon = -79.3832

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: ExploredCell.self, ShoppingArea.self, AreaMember.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        cache = DiscoveryCache(context: ModelContext(container))
    }

    private func poi(_ name: String, _ lat: Double, _ lon: Double) -> NearbyPlace {
        NearbyPlace(id: name, name: name, poiCategoryRaw: "store",
                       latitude: lat, longitude: lon, distanceMeters: nil)
    }

    private var torontoCell: String { cellKey(latitude: torontoLat, longitude: torontoLon) }

    func testAnUnexploredCellHasNoEntry() throws {
        XCTAssertNil(try cache.entry(forCellKey: torontoCell))
    }

    func testRecordingACellMakesItACacheHit() throws {
        let areas = clusterIntoAreas([poi("Walmart", torontoLat, torontoLon)])
        try cache.record(cellKey: torontoCell, areas: areas, at: now)

        let entry = try XCTUnwrap(try cache.entry(forCellKey: torontoCell))
        XCTAssertEqual(entry.cellKey, torontoCell)
        XCTAssertEqual(entry.areaCount, 1)
        XCTAssertEqual(entry.exploredAt, now)
    }

    /// Negative caching has to survive a relaunch, or the owner's own street is re-queried on
    /// every significant location change forever.
    func testACellWithNoRetailIsPersistedAsAnAnswer() throws {
        try cache.record(cellKey: torontoCell, areas: [], at: now)

        let entry = try XCTUnwrap(try cache.entry(forCellKey: torontoCell))
        XCTAssertEqual(entry.areaCount, 0)
    }

    func testReExploringACellReplacesRatherThanDuplicates() throws {
        try cache.record(cellKey: torontoCell, areas: [], at: now)
        let later = now.addingTimeInterval(discoveryCacheTTL + 1)
        try cache.record(cellKey: torontoCell,
                         areas: clusterIntoAreas([poi("Walmart", torontoLat, torontoLon)]),
                         at: later)

        let entry = try XCTUnwrap(try cache.entry(forCellKey: torontoCell))
        XCTAssertEqual(entry.exploredAt, later)
        XCTAssertEqual(entry.areaCount, 1)
        XCTAssertEqual(try cache.allCells().count, 1, "the stale row must be replaced, not stacked")
    }

    func testStoredAreasKeepTheirMembers() throws {
        let areas = clusterIntoAreas([
            poi("Walmart", torontoLat, torontoLon),
            poi("Dollarama", torontoLat + 0.0002, torontoLon + 0.0002),
        ])
        try cache.record(cellKey: torontoCell, areas: areas, at: now)

        let stored = try cache.areasNear(latitude: torontoLat, longitude: torontoLon, limit: 20)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(Set(stored[0].members.map(\.name)), ["Walmart", "Dollarama"])
    }

    /// CoreLocation monitors at most 20 regions app-wide, so the caller has to be handed a
    /// bounded, nearest-first list rather than everything ever discovered.
    func testAreasComeBackNearestFirstAndBounded() throws {
        // Three clusters at increasing distance, recorded in the wrong order on purpose.
        for (index, offset) in [0.05, 0.01, 0.03].enumerated() {
            let lat = torontoLat + offset
            try cache.record(cellKey: cellKey(latitude: lat, longitude: torontoLon),
                             areas: clusterIntoAreas([poi("Store\(index)", lat, torontoLon)]),
                             at: now)
        }

        let nearest = try cache.areasNear(latitude: torontoLat, longitude: torontoLon, limit: 2)
        XCTAssertEqual(nearest.count, 2)
        let first = greatCircleDistanceMeters(fromLatitude: torontoLat, fromLongitude: torontoLon,
                                              toLatitude: nearest[0].centroidLatitude,
                                              toLongitude: nearest[0].centroidLongitude)
        let second = greatCircleDistanceMeters(fromLatitude: torontoLat, fromLongitude: torontoLon,
                                               toLatitude: nearest[1].centroidLatitude,
                                               toLongitude: nearest[1].centroidLongitude)
        XCTAssertLessThan(first, second)
    }

    // MARK: - Retention (design §10)

    /// The cache is a coarse record of everywhere the owner has been, kept purely as an
    /// optimisation. Pruning is a privacy obligation, not a freshness one — which is why the
    /// retention window is separate from, and longer than, the staleness TTL.
    func testRetentionIsLongerThanTheFreshnessTTL() {
        XCTAssertGreaterThan(discoveryRetention, discoveryCacheTTL)
    }

    func testPruningDropsCellsNotRevisitedWithinTheRetentionWindow() throws {
        let ancient = now.addingTimeInterval(-(discoveryRetention + 1))
        try cache.record(cellKey: "ancient_cell",
                         areas: clusterIntoAreas([poi("Old", 45.0, -75.0)]), at: ancient)
        try cache.record(cellKey: torontoCell,
                         areas: clusterIntoAreas([poi("Walmart", torontoLat, torontoLon)]), at: now)

        try cache.prune(now: now)

        XCTAssertNil(try cache.entry(forCellKey: "ancient_cell"))
        XCTAssertNotNil(try cache.entry(forCellKey: torontoCell))
    }

    /// A pruned cell must take its areas and their members with it — otherwise "forgetting where
    /// you have been" leaves the coordinates behind, which is the part that mattered.
    func testPruningRemovesTheAreasAndMembersOfDroppedCells() throws {
        let ancient = now.addingTimeInterval(-(discoveryRetention + 1))
        try cache.record(cellKey: "ancient_cell",
                         areas: clusterIntoAreas([poi("Old", 45.0, -75.0)]), at: ancient)

        try cache.prune(now: now)

        XCTAssertTrue(try cache.allAreas().isEmpty)
        XCTAssertTrue(try cache.allMembers().isEmpty)
    }
}
