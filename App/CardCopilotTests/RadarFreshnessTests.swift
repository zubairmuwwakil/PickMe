import XCTest
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

@MainActor
final class RadarFreshnessTests: XCTestCase {
    private final class StubLocationProvider: CheckoutLocationProviding {
        var authorizedLocation: CheckoutLocationFix?
        var promptedLocation: CheckoutLocationFix
        private(set) var authorizedRequestCount = 0
        private(set) var promptedRequestCount = 0

        init(promptedLocation: CheckoutLocationFix) {
            self.promptedLocation = promptedLocation
        }

        func requestLocation() async throws -> CheckoutLocationFix {
            promptedRequestCount += 1
            return promptedLocation
        }

        func requestLocationIfAuthorized() async throws -> CheckoutLocationFix? {
            authorizedRequestCount += 1
            return authorizedLocation
        }
    }

    private actor StubMerchantProvider: MerchantProviding {
        let nearbyResult: [NearbyPlace]
        private(set) var nearbyRequestCount = 0

        init(_ nearbyResult: [NearbyPlace]) {
            self.nearbyResult = nearbyResult
        }

        func nearby(latitude: Double, longitude: Double) async throws -> [NearbyPlace] {
            nearbyRequestCount += 1
            return nearbyResult
        }

        func search(text: String) async throws -> [NearbyPlace] { [] }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CardCopilotSchema.current)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeMetricsStore() -> NearbyLookupMetricsStore {
        NearbyLookupMetricsStore(
            defaults: UserDefaults(suiteName: "RadarFreshness.\(UUID().uuidString)")!)
    }

    private func makeGraph(provider: any MerchantProviding) throws -> DependencyGraph {
        let context = try makeContext()
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        return DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: [],
            ownerState: owner,
            benefits: try SeedLoader.loadBenefitsCatalogue(),
            service: CheckoutService(catalogue: catalogue, ownerState: owner, context: context),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: provider)
    }

    func testExplicitRadarRescanRefreshesAfterWalkingAboutTwentyFiveMetresIntoStore() async throws {
        let outsideFix = CheckoutLocationFix(latitude: 43.653200, longitude: -79.383200,
                                             horizontalAccuracyMeters: 10)
        // ~25 m north at Toronto's latitude: deliberately well inside the old movement-cache
        // allowance that reproduced the field report.
        let insideFix = CheckoutLocationFix(latitude: 43.653425, longitude: -79.383200,
                                            horizontalAccuracyMeters: 10)
        let location = StubLocationProvider(promptedLocation: insideFix)
        location.authorizedLocation = outsideFix

        let office = NearbyPlace(id: "office", name: "Nearby Office", poiCategoryRaw: nil,
                                 latitude: 43.653250, longitude: -79.383200,
                                 distanceMeters: 8)
        let shoppers = NearbyPlace(id: "shoppers", name: "Shoppers Drug Mart",
                                   poiCategoryRaw: "MKPOICategoryPharmacy",
                                   latitude: 43.653425, longitude: -79.383200,
                                   distanceMeters: 2)

        let outsideProvider = StubMerchantProvider([office])
        let insideProvider = StubMerchantProvider([shoppers, office])
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: try makeGraph(provider: outsideProvider))
        XCTAssertEqual(session.preparedNearbyMerchants.map(\.id), ["office"])

        let outcome = await session.rescanNearby(using: try makeGraph(provider: insideProvider))
        let outsideRequestCount = await outsideProvider.nearbyRequestCount
        let insideRequestCount = await insideProvider.nearbyRequestCount

        guard case .found(let places) = outcome else {
            return XCTFail("expected the explicit Radar refresh to return live nearby places")
        }
        XCTAssertEqual(places.first?.id, "shoppers")
        XCTAssertEqual(location.authorizedRequestCount, 1,
                       "launch prefetch should remain opportunistic")
        XCTAssertEqual(location.promptedRequestCount, 1,
                       "an explicit Radar refresh must request its own location fix")
        XCTAssertEqual(outsideRequestCount, 1)
        XCTAssertEqual(insideRequestCount, 1,
                       "the store entered after prefetch must get a fresh MapKit lookup")
        XCTAssertEqual(session.nearbyMetrics.movementCacheHits, 0,
                       "movement cache is for prefetch, not an explicit Radar refresh")
        XCTAssertEqual(session.nearbyMetrics.tapLookups, 1)
    }

    func testExplicitRadarRescanQueriesAgainEvenAtTheSameCoordinate() async throws {
        let fix = CheckoutLocationFix(latitude: 43.653200, longitude: -79.383200,
                                      horizontalAccuracyMeters: 10)
        let location = StubLocationProvider(promptedLocation: fix)
        location.authorizedLocation = fix

        let stalePlace = NearbyPlace(id: "stale", name: "Old Candidate", poiCategoryRaw: nil,
                                     latitude: fix.latitude, longitude: fix.longitude,
                                     distanceMeters: 4)
        let livePlace = NearbyPlace(id: "live", name: "Current Store",
                                    poiCategoryRaw: "MKPOICategoryStore",
                                    latitude: fix.latitude, longitude: fix.longitude,
                                    distanceMeters: 1)
        let prefetchProvider = StubMerchantProvider([stalePlace])
        let liveProvider = StubMerchantProvider([livePlace])
        let session = CopilotSession(locationProvider: location,
                                     nearbyMetricsStore: makeMetricsStore())

        await session.prefetchNearby(using: try makeGraph(provider: prefetchProvider))
        let outcome = await session.rescanNearby(using: try makeGraph(provider: liveProvider))
        let liveRequestCount = await liveProvider.nearbyRequestCount

        XCTAssertEqual(outcome, .found([livePlace]))
        XCTAssertEqual(liveRequestCount, 1,
                       "zero movement must not turn an explicit refresh into a cache hit")
        XCTAssertEqual(session.nearbyMetrics.movementCacheHits, 0)
    }
}
