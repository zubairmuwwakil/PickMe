import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class MerchantMCCSeedCatalogueTests: XCTestCase {
    func testBundledSeedContainsAll500Merchants() {
        XCTAssertEqual(MerchantMCCSeedCatalogue.graphVersion, "1.0")
        XCTAssertEqual(MerchantMCCSeedCatalogue.merchants.count, 500)
    }

    func testMetroResolvesToGrocery5411WithoutSubstringGuessing() throws {
        let metro = try XCTUnwrap(MerchantMCCSeedCatalogue.match(merchantName: "Metro"))
        XCTAssertEqual(metro.merchant.id, "metro")
        XCTAssertEqual(metro.profile.primaryMcc, 5411)

        XCTAssertNil(MerchantMCCSeedCatalogue.match(merchantName: "Metropolitan Hotel"),
                     "Metro must not leak into unrelated merchant names")
    }

    func testNearbyRouteCandidatesUseSeedGraphAndPhysicalDistance() throws {
        let route = try XCTUnwrap(PurchaseRouteCatalogue.canadaV1.first)
        let places = [
            NearbyPlace(id: "rexall", name: "Rexall", poiCategoryRaw: nil,
                        latitude: 43.0, longitude: -79.0, distanceMeters: 80),
            NearbyPlace(id: "sobeys", name: "Sobeys", poiCategoryRaw: nil,
                        latitude: 43.0, longitude: -79.0, distanceMeters: 300),
            NearbyPlace(id: "metro", name: "Metro", poiCategoryRaw: nil,
                        latitude: 43.0, longitude: -79.0, distanceMeters: 120)
        ]

        let candidates = PurchaseRouteAcquisitionResolver.candidates(for: route, nearby: places)
        XCTAssertEqual(candidates.map(\.place.name), ["Metro", "Sobeys"])
        XCTAssertTrue(candidates.allSatisfy { $0.mcc == 5411 })
        XCTAssertTrue(candidates.allSatisfy { $0.confidence > 0 && $0.confidence < 0.8 })
    }

    func testResolvedRouteUsesActualMerchantAcceptance() throws {
        let route = try XCTUnwrap(PurchaseRouteCatalogue.canadaV1.first)
        let place = NearbyPlace(id: "no-frills", name: "No Frills", poiCategoryRaw: nil,
                                latitude: 43.0, longitude: -79.0, distanceMeters: 50)
        let candidate = try XCTUnwrap(
            PurchaseRouteAcquisitionResolver.candidates(for: route, nearby: [place]).first)
        let resolved = PurchaseRouteAcquisitionResolver.resolvedRoute(from: route,
                                                                       candidate: candidate)
        XCTAssertEqual(resolved.acquisitionMerchantLabel, "No Frills")
        XCTAssertEqual(resolved.acquisitionMcc, 5411)
        XCTAssertFalse(resolved.acceptedNetworks.contains(.amex),
                       "No Frills route must not recommend an Amex acquisition leg")
    }

    func testDirectOwnerEvidenceCanOverrideSeedForRouteEligibility() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let route = try XCTUnwrap(PurchaseRouteCatalogue.canadaV1.first)
        let place = NearbyPlace(id: "costco", name: "Costco Wholesale", poiCategoryRaw: nil,
                                merchantCategoryCode: nil,
                                latitude: 43.1, longitude: -79.1, distanceMeters: 100)
        let purchase = StoredPurchase(
            createdAt: now,
            merchantLabel: "Costco Wholesale",
            merchantKey: "Costco Wholesale",
            merchantLatitude: 43.1,
            merchantLongitude: -79.1,
            categoryAtPurchase: "wholesaleClub")
        purchase.observation = StoredObservation(
            observedCategory: "grocery",
            observedMerchantCategoryCode: 5411,
            confirmedAt: now)

        let candidates = PurchaseRouteAcquisitionResolver.candidates(
            for: route, nearby: [place], purchases: [purchase], now: now)
        XCTAssertEqual(candidates.first?.mcc, 5411,
                       "local direct evidence must be allowed to beat a 5300 wholesale seed")
    }
}
