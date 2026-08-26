import Foundation
import SwiftData

/// How long a cell is kept at all, independent of how long it stays *fresh*.
///
/// `discoveryCacheTTL` answers "is this answer still current?" — a staleness question about
/// shops. This answers "should we still be holding a record that the owner was here?" — a
/// privacy question about people, and the reason it exists as a separate, longer constant.
public let discoveryRetention: TimeInterval = 90 * 24 * 60 * 60

// The persisted models of schema version 1. Declared as an extension of
// `CardCopilotSchemaV1` (see Schema.swift) rather than at file scope, so that a future
// version can hold a differently shaped model of the same name. The unqualified names
// remain available through the typealiases in Schema.swift, so call sites are unchanged.
extension CardCopilotSchemaV1 {

    /// One ~1 km grid cell that discovery has looked at. `areaCount == 0` is a recorded answer, not
    /// an absence: it is what stops the owner's own street being re-queried forever.
    @Model
    public final class ExploredCell {
        public private(set) var cellKey: String = ""
        public var exploredAt: Date = Date()
        public var areaCount: Int = 0

        public init(cellKey: String, exploredAt: Date, areaCount: Int) {
            self.cellKey = cellKey
            self.exploredAt = exploredAt
            self.areaCount = areaCount
        }
    }

    /// A cluster of POIs monitored as one region. The unit of geofencing is the plaza, not the
    /// storefront — twenty shops fit inside one 150 m circle and CoreLocation allows twenty regions
    /// in total, so storefront-level monitoring spends the entire budget on a single parking lot.
    @Model
    public final class ShoppingArea {
        public private(set) var id: UUID = UUID()
        /// The cell that discovered it, so pruning a cell can take its areas with it.
        public private(set) var cellKey: String = ""
        public private(set) var centroidLatitude: Double = 0
        public private(set) var centroidLongitude: Double = 0
        public private(set) var radiusMeters: Double = 0
        public var discoveredAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \AreaMember.area)
        public var members: [AreaMember] = []

        public init(cellKey: String, centroidLatitude: Double, centroidLongitude: Double,
                    radiusMeters: Double, discoveredAt: Date) {
            self.id = UUID()
            self.cellKey = cellKey
            self.centroidLatitude = centroidLatitude
            self.centroidLongitude = centroidLongitude
            self.radiusMeters = radiusMeters
            self.discoveredAt = discoveredAt
        }
    }

    /// A POI inside an area. Its own `@Model` rather than an encoded blob so members can be queried
    /// and pruned directly, and so one can later be promoted to a confirmed `StoredMerchant` without
    /// a decode round-trip.
    @Model
    public final class AreaMember {
        public private(set) var name: String = ""
        public private(set) var identifier: String?
        public private(set) var poiCategoryRaw: String?
        public private(set) var latitude: Double = 0
        public private(set) var longitude: Double = 0
        public var area: ShoppingArea?

        public init(name: String, identifier: String?, poiCategoryRaw: String?,
                    latitude: Double, longitude: Double) {
            self.name = name
            self.identifier = identifier
            self.poiCategoryRaw = poiCategoryRaw
            self.latitude = latitude
            self.longitude = longitude
        }
    }
}

/// Persistence behind the spatial cache. Holds no policy — `shouldQueryDiscovery` decides whether
/// a query happens; this only remembers what came back.
public struct DiscoveryCache {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func entry(forCellKey key: String) throws -> DiscoveryCacheEntry? {
        guard let cell = try storedCell(forKey: key) else { return nil }
        return DiscoveryCacheEntry(cellKey: cell.cellKey, exploredAt: cell.exploredAt,
                                   areaCount: cell.areaCount)
    }

    /// Records the result of exploring a cell, replacing any previous result for it.
    ///
    /// Replace rather than append: a cell has one current answer, and stacking rows would make
    /// `entry(forCellKey:)` depend on fetch order while quietly retaining coordinates the newer
    /// answer superseded.
    public func record(cellKey key: String, areas: [ShoppingAreaCandidate], at date: Date) throws {
        try deleteAreas(forCellKey: key)

        for candidate in areas {
            let area = ShoppingArea(cellKey: key,
                                    centroidLatitude: candidate.centroidLatitude,
                                    centroidLongitude: candidate.centroidLongitude,
                                    radiusMeters: candidate.radiusMeters,
                                    discoveredAt: date)
            context.insert(area)
            for member in candidate.members {
                let stored = AreaMember(name: member.name, identifier: member.id,
                                        poiCategoryRaw: member.poiCategoryRaw,
                                        latitude: member.latitude, longitude: member.longitude)
                context.insert(stored)
                stored.area = area
            }
        }

        if let existing = try storedCell(forKey: key) {
            existing.exploredAt = date
            existing.areaCount = areas.count
        } else {
            context.insert(ExploredCell(cellKey: key, exploredAt: date, areaCount: areas.count))
        }
        try context.save()
    }

    /// Nearest areas first, bounded — the caller is filling CoreLocation's 20-region budget.
    public func areasNear(latitude: Double, longitude: Double, limit: Int) throws -> [ShoppingArea] {
        try allAreas()
            .map { area in
                (area, greatCircleDistanceMeters(fromLatitude: latitude, fromLongitude: longitude,
                                                 toLatitude: area.centroidLatitude,
                                                 toLongitude: area.centroidLongitude))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Drops cells the owner has not returned to inside the retention window, and everything
    /// discovered from them. Freshness expiry only stops the cache being *believed*; this is what
    /// stops it accreting into a lifetime movement history.
    public func prune(now: Date) throws {
        let cutoff = now.addingTimeInterval(-discoveryRetention)
        for cell in try allCells() where cell.exploredAt < cutoff {
            try deleteAreas(forCellKey: cell.cellKey)
            context.delete(cell)
        }
        try context.save()
    }

    /// Erases the whole cache. Called from `LocalDataEraser` — a wipe that spared this would
    /// leave behind a coarse record of everywhere the owner has been.
    /// Deletes through the object graph rather than by batch.
    ///
    /// `context.delete(model:)` issues a batch delete, which SwiftData refuses here: nulling the
    /// mandatory inverse on `AreaMember.area` is a constraint it will not resolve in bulk. Areas
    /// go first so their members cascade, then any orphan member, then the cells. These tables
    /// are small — a cell grid and the shops in it — so the per-object cost is irrelevant beside
    /// getting the erase to actually happen.
    public func eraseAll() throws {
        for area in try allAreas() { context.delete(area) }
        for member in try allMembers() { context.delete(member) }
        for cell in try allCells() { context.delete(cell) }
        try context.save()
    }

    public func allCells() throws -> [ExploredCell] {
        try context.fetch(FetchDescriptor<ExploredCell>())
    }

    public func allAreas() throws -> [ShoppingArea] {
        try context.fetch(FetchDescriptor<ShoppingArea>())
    }

    public func allMembers() throws -> [AreaMember] {
        try context.fetch(FetchDescriptor<AreaMember>())
    }

    private func storedCell(forKey key: String) throws -> ExploredCell? {
        try context.fetch(FetchDescriptor<ExploredCell>(
            predicate: #Predicate { $0.cellKey == key })).first
    }

    private func deleteAreas(forCellKey key: String) throws {
        for area in try context.fetch(FetchDescriptor<ShoppingArea>(
            predicate: #Predicate { $0.cellKey == key })) {
            context.delete(area)
        }
    }
}
