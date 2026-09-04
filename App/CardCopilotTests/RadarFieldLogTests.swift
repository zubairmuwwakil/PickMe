import XCTest
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// The Radar path writing to the field log.
///
/// `ArrivalFieldLogStore` was referenced only inside `AmbientLocationService`, so the foreground
/// scan — the path the owner's actual reported failure lives on, and the one they can trigger
/// deliberately by walking into a store and tapping — recorded nothing at all. These are the tests
/// that say it does now.
@MainActor
final class RadarFieldLogTests: XCTestCase {

    private final class StubLocationProvider: CheckoutLocationProviding {
        var authorizedLocation: CheckoutLocationFix?

        func requestLocation() async throws -> CheckoutLocationFix {
            guard let authorizedLocation else { throw LocationUnavailable.fixFailed("no stub fix") }
            return authorizedLocation
        }

        func requestLocationIfAuthorized() async throws -> CheckoutLocationFix? {
            authorizedLocation
        }
    }

    /// Reports a raw response size the way `LiveMerchantProvider` does — the count MapKit
    /// returned, before `rankNearbyPlaces` deduped it.
    private actor ScanningMerchantProvider: MerchantProviding {
        let scan: NearbyScan

        init(scan: NearbyScan) { self.scan = scan }

        func nearby(latitude: Double, longitude: Double) async throws -> [NearbyPlace] {
            scan.places
        }

        func nearbyScan(latitude: Double, longitude: Double) async throws -> NearbyScan { scan }

        func search(text: String) async throws -> [NearbyPlace] { [] }
    }

    /// Implements only the protocol's original requirement, as every other provider double in the
    /// suite does. The default `nearbyScan` has to carry it.
    private actor RankedOnlyMerchantProvider: MerchantProviding {
        let merchants: [NearbyPlace]

        init(merchants: [NearbyPlace]) { self.merchants = merchants }

        func nearby(latitude: Double, longitude: Double) async throws -> [NearbyPlace] {
            merchants
        }

        func search(text: String) async throws -> [NearbyPlace] { [] }
    }

    private func merchant(_ name: String, metresNorth: Double) -> NearbyPlace {
        NearbyPlace(id: "\(name)@\(metresNorth)", name: name, poiCategoryRaw: nil,
                       latitude: 45 + metresNorth / 111_000, longitude: -75,
                       distanceMeters: metresNorth)
    }

    private func makeFieldLogStore() -> ArrivalFieldLogStore {
        ArrivalFieldLogStore(
            defaults: UserDefaults(suiteName: "RadarFieldLog.\(UUID().uuidString)")!)
    }

    private func makeGraph(provider: any MerchantProviding) throws -> DependencyGraph {
        let schema = Schema(versionedSchema: CardCopilotSchema.current)
        let container = try ModelContainer(
            for: schema, migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        return DependencyGraph(
            catalogue: catalogue, candidateCardIds: [], ownerState: owner,
            benefits: try SeedLoader.loadBenefitsCatalogue(),
            service: CheckoutService(catalogue: catalogue, ownerState: owner,
                                     context: ModelContext(container)),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: provider)
    }

    private func makeSession(provider: any MerchantProviding,
                             fieldLogStore: ArrivalFieldLogStore) throws
    -> (CopilotSession, DependencyGraph) {
        let location = StubLocationProvider()
        location.authorizedLocation = CheckoutLocationFix(latitude: 45, longitude: -75,
                                                          horizontalAccuracyMeters: 12)
        let metrics = NearbyLookupMetricsStore(
            defaults: UserDefaults(suiteName: "RadarFieldLogMetrics.\(UUID().uuidString)")!)
        let session = CopilotSession(locationProvider: location, nearbyMetricsStore: metrics,
                                     fieldLogStore: fieldLogStore)
        return (session, try makeGraph(provider: provider))
    }

    // MARK: -

    /// The gap this group closes: a Radar scan used to leave no evidence behind at all.
    func testAScanWritesOneRadarRecordCarryingEveryCandidate() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: ScanningMerchantProvider(scan: NearbyScan(
                places: [merchant("Bergeron Notaries", metresNorth: 12),
                            merchant("Shoppers Drug Mart", metresNorth: 40)],
                rawResultCount: 9)),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)

        let records = store.all()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].source, .radar)
        XCTAssertEqual(records[0].candidates.map(\.name),
                       ["Bergeron Notaries", "Shoppers Drug Mart"])
        XCTAssertEqual(records[0].chosenCandidateIndex, 0)
    }

    /// The fix and its accuracy, because a scan through a ±65 m fix and one through a ±5 m fix are
    /// different events and the export has to be able to tell them apart.
    func testTheRecordCarriesTheFixAndItsAccuracy() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: RankedOnlyMerchantProvider(
                merchants: [merchant("Shoppers Drug Mart", metresNorth: 40)]),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)

        let fix = try XCTUnwrap(store.all().first?.fix)
        XCTAssertEqual(fix.latitude, 45, accuracy: 0.000_001)
        XCTAssertEqual(fix.horizontalAccuracyMeters, 12)
    }

    /// A cap that truncates upstream is invisible once the list is deduped, so the size MapKit
    /// actually returned has to survive the trip out of the provider.
    func testTheRawResponseSizeReachesTheRecord() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: ScanningMerchantProvider(scan: NearbyScan(
                places: [merchant("Shoppers Drug Mart", metresNorth: 40)],
                rawResultCount: 25)),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)

        XCTAssertEqual(store.all().first?.rawResultCount, 25)
        XCTAssertEqual(store.all().first?.dedupedResultCount, 1)
    }

    /// A provider that cannot see MapKit's raw response reports what it has. The count is then
    /// equal by construction rather than absent, which is honest: nothing was dropped that this
    /// provider could have seen.
    func testAProviderWithNoRawCountReportsTheRankedCount() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: RankedOnlyMerchantProvider(
                merchants: [merchant("Bergeron Notaries", metresNorth: 12),
                            merchant("Shoppers Drug Mart", metresNorth: 40)]),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)

        XCTAssertEqual(store.all().first?.rawResultCount, 2)
    }

    /// **The record that answers the owner's report.** Standing in Shoppers, the chain is in the
    /// set and a notary two doors down is ranked above it.
    func testAScanRecordsChainContainmentAndThePinGeometrySignature() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: ScanningMerchantProvider(scan: NearbyScan(
                places: [merchant("Bergeron Notaries", metresNorth: 12),
                            merchant("Shoppers Drug Mart", metresNorth: 40)],
                rawResultCount: 2)),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)

        let record = try XCTUnwrap(store.all().first)
        XCTAssertEqual(record.candidates[1].preIndexMerchantId, "shoppers drug mart")
        XCTAssertTrue(record.containsRecognisedChain)
        XCTAssertTrue(record.topRankedMissedARecognisedChain)
    }

    /// The margin, computed by the ambient path's own function so foreground and background
    /// samples can be pooled.
    func testAScanRecordsTheDiscriminabilityMargin() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: ScanningMerchantProvider(scan: NearbyScan(
                places: [merchant("Bergeron Notaries", metresNorth: 12),
                            merchant("Shoppers Drug Mart", metresNorth: 40)],
                rawResultCount: 2)),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)

        let margin = try XCTUnwrap(store.all().first?.discriminability)
        XCTAssertEqual(try XCTUnwrap(margin.marginMeters), 28, accuracy: 1)
        XCTAssertEqual(margin.fixAccuracyMeters, 12)
        // 28 m apart through a ±12 m fix: this one *was* answerable, and was answered wrong.
        XCTAssertTrue(margin.isResolvable)
    }

    /// An empty scan is the single most important record in the log if the result set is the
    /// mechanism — "I was standing in Shoppers and nothing came back" is exactly this record.
    func testAnEmptyScanIsStillRecorded() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: ScanningMerchantProvider(scan: NearbyScan(places: [],
                                                                rawResultCount: 0)),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)

        XCTAssertEqual(store.all().count, 1)
        XCTAssertTrue(try XCTUnwrap(store.all().first).candidates.isEmpty)
    }

    /// A movement-cache hit re-publishes a result already recorded. Recording it again would
    /// double-count the scan the pin-geometry figure is a rate over, and there is no raw response
    /// size to record because no query ran.
    func testAResultServedFromTheMovementCacheDoesNotWriteASecondRecord() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try makeSession(
            provider: ScanningMerchantProvider(scan: NearbyScan(
                places: [merchant("Shoppers Drug Mart", metresNorth: 40)],
                rawResultCount: 1)),
            fieldLogStore: store)

        await session.prefetchNearby(using: graph)
        await session.prefetchNearby(using: graph)

        XCTAssertEqual(store.all().count, 1)
    }
}
