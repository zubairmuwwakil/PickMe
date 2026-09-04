import XCTest
@testable import CardCopilotStore

final class GiftCardInventoryGraphTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecentOwnerSightingMakesExactLocationActionable() {
        let evidence = GiftCardInventoryObservation(
            id: "found",
            merchantKey: "Metro",
            placeID: "metro-1",
            instrumentKey: "Shoppers Drug Mart gift card",
            availability: .available,
            source: .ownerConfirmed,
            observedAt: now)

        let prediction = GiftCardInventoryGraph.predict(
            for: GiftCardInventoryQuery(merchantKey: "Metro",
                                        placeID: "metro-1",
                                        instrumentKey: "Shoppers Drug Mart gift card"),
            evidence: [evidence],
            now: now)

        XCTAssertEqual(prediction.state, .available)
        XCTAssertTrue(prediction.isActionableAvailable)
        XCTAssertEqual(prediction.observationCount, 1)
    }

    func testInventoryNeverLeaksAcrossLocationsOfSameBanner() {
        let evidence = GiftCardInventoryObservation(
            id: "found",
            merchantKey: "Metro",
            placeID: "metro-toronto",
            instrumentKey: "Shoppers Drug Mart gift card",
            availability: .available,
            source: .ownerConfirmed,
            observedAt: now)

        let prediction = GiftCardInventoryGraph.predict(
            for: GiftCardInventoryQuery(merchantKey: "Metro",
                                        placeID: "metro-oshawa",
                                        instrumentKey: "Shoppers Drug Mart gift card"),
            evidence: [evidence],
            now: now)

        XCTAssertEqual(prediction.state, .unknown)
        XCTAssertEqual(prediction.observationCount, 0)
    }

    func testBrandOnlyInventoryEvidenceIsRejected() {
        let evidence = GiftCardInventoryObservation(
            id: "brand-only",
            merchantKey: "Sobeys",
            instrumentKey: "Shoppers Drug Mart gift card",
            availability: .available,
            source: .communityObserved,
            observedAt: now)

        let prediction = GiftCardInventoryGraph.predict(
            for: GiftCardInventoryQuery(merchantKey: "Sobeys",
                                        instrumentKey: "Shoppers Drug Mart gift card"),
            evidence: [evidence],
            now: now)

        XCTAssertEqual(prediction.state, .unknown)
    }

    func testNegativeStockoutEvidenceExpiresFasterThanPositiveSighting() {
        let location = (lat: 43.8971, lon: -78.8658)
        let positive = GiftCardInventoryObservation(
            id: "positive",
            merchantKey: "Metro",
            latitude: location.lat,
            longitude: location.lon,
            instrumentKey: "Shoppers Drug Mart gift card",
            availability: .available,
            source: .ownerConfirmed,
            observedAt: now.addingTimeInterval(-14 * 86_400))
        let negative = GiftCardInventoryObservation(
            id: "negative",
            merchantKey: "Metro",
            latitude: location.lat,
            longitude: location.lon,
            instrumentKey: "Shoppers Drug Mart gift card",
            availability: .unavailable,
            source: .ownerConfirmed,
            observedAt: now.addingTimeInterval(-14 * 86_400))

        let query = GiftCardInventoryQuery(merchantKey: "Metro",
                                           latitude: location.lat,
                                           longitude: location.lon,
                                           instrumentKey: "Shoppers Drug Mart gift card")
        let positivePrediction = GiftCardInventoryGraph.predict(for: query,
                                                                evidence: [positive],
                                                                now: now)
        let negativePrediction = GiftCardInventoryGraph.predict(for: query,
                                                                evidence: [negative],
                                                                now: now)

        XCTAssertGreaterThan(positivePrediction.confidence, negativePrediction.confidence)
        XCTAssertNotEqual(positivePrediction.state, .unavailable)
        XCTAssertEqual(negativePrediction.state, .unknown)
    }

    func testLocalStorePersistsAppendOnlyFeedback() async {
        let suite = "GiftCardInventoryGraphTests.\(UUID().uuidString)"
        let store = GiftCardInventoryObservationStore(suiteName: suite)
        await store.removeAllForTesting()

        _ = await store.record(merchantKey: "Metro",
                               placeID: "metro-1",
                               latitude: nil,
                               longitude: nil,
                               instrumentKey: "Shoppers Drug Mart gift card",
                               availability: .available,
                               observedAt: now)
        _ = await store.record(merchantKey: "Metro",
                               placeID: "metro-1",
                               latitude: nil,
                               longitude: nil,
                               instrumentKey: "Shoppers Drug Mart gift card",
                               availability: .unavailable,
                               observedAt: now.addingTimeInterval(60))

        let observations = await store.observations()
        XCTAssertEqual(observations.count, 2)
        XCTAssertEqual(observations.map(\.availability), [.available, .unavailable])
        await store.removeAllForTesting()
    }

    func testRapidDuplicateTapCountsOnce() async {
        let suite = "GiftCardInventoryGraphTests.\(UUID().uuidString)"
        let store = GiftCardInventoryObservationStore(suiteName: suite)
        await store.removeAllForTesting()

        _ = await store.record(merchantKey: "Metro",
                               placeID: "metro-1",
                               latitude: 43.0,
                               longitude: -79.0,
                               instrumentKey: "Shoppers Drug Mart gift card",
                               availability: .available,
                               observedAt: now)
        _ = await store.record(merchantKey: "Metro",
                               placeID: "metro-1",
                               latitude: 43.0,
                               longitude: -79.0,
                               instrumentKey: "Shoppers Drug Mart gift card",
                               availability: .available,
                               observedAt: now.addingTimeInterval(10))

        XCTAssertEqual(await store.observations().count, 1)
        await store.removeAllForTesting()
    }
}
