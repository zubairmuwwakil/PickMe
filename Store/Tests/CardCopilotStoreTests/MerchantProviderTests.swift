import XCTest
@testable import CardCopilotStore

final class MerchantProviderTests: XCTestCase {
    private func merchant(id: String, name: String, distance: Double?) -> NearbyPlace {
        NearbyPlace(id: id, name: name, poiCategoryRaw: "foodMarket",
                       latitude: 43.65107, longitude: -79.347015, distanceMeters: distance)
    }

    func testRankingSortsByDistanceAscending() {
        let far = merchant(id: "far", name: "Far Shop", distance: 300)
        let near = merchant(id: "near", name: "Near Shop", distance: 50)
        let mid = merchant(id: "mid", name: "Mid Shop", distance: 150)

        let ranked = rankNearbyPlaces([far, near, mid])

        XCTAssertEqual(ranked.map(\.id), ["near", "mid", "far"])
    }

    func testRankingBreaksTiesByNameCaseInsensitively() {
        let banana = merchant(id: "b", name: "banana", distance: 100)
        let apple = merchant(id: "a", name: "Apple", distance: 100)

        let ranked = rankNearbyPlaces([banana, apple])

        XCTAssertEqual(ranked.map(\.id), ["a", "b"])
    }

    func testRankingSortsUnknownDistanceLast() {
        let unknown = merchant(id: "unknown", name: "Mystery Shop", distance: nil)
        let known = merchant(id: "known", name: "Zzz Shop", distance: 500)

        let ranked = rankNearbyPlaces([unknown, known])

        XCTAssertEqual(ranked.map(\.id), ["known", "unknown"])
    }

    func testRankingDedupesByIdKeepingClosestCopy() {
        let farCopy = merchant(id: "dup", name: "Duplicate", distance: 200)
        let nearCopy = merchant(id: "dup", name: "Duplicate", distance: 20)
        let other = merchant(id: "other", name: "Other Shop", distance: 100)

        let ranked = rankNearbyPlaces([farCopy, other, nearCopy])

        XCTAssertEqual(ranked.map(\.id), ["dup", "other"])
        XCTAssertEqual(ranked.first?.distanceMeters, 20)
    }

    func testStubMerchantProviderReturnsConfiguredNearbyResults() async throws {
        let expected = [merchant(id: "loblaws", name: "Loblaws", distance: 40)]
        let provider = StubMerchantProvider(nearbyResult: expected)

        let results = try await provider.nearby(latitude: 43.65107, longitude: -79.347015)

        XCTAssertEqual(results, expected)
    }

    func testStubMerchantProviderReturnsConfiguredSearchResults() async throws {
        let expected = [merchant(id: "costco", name: "Costco", distance: nil)]
        let provider = StubMerchantProvider(searchResult: expected)

        let results = try await provider.search(text: "costco")

        XCTAssertEqual(results, expected)
    }

    func testStubMerchantProviderThrowsConfiguredNearbyError() async {
        struct SampleError: Error {}
        let provider = StubMerchantProvider(nearbyError: SampleError())

        do {
            _ = try await provider.nearby(latitude: 0, longitude: 0)
            XCTFail("expected nearby to throw")
        } catch is SampleError {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
