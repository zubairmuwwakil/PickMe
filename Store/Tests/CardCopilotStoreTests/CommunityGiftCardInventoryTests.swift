import XCTest
@testable import CardCopilotStore

final class CommunityGiftCardInventoryTests: XCTestCase {
    func testSharingDefaultsOffAndCanBeRevoked() {
        let suite = "CommunityGiftCardInventoryTests.\(UUID().uuidString)"
        let settings = CommunityGiftCardInventorySettingsStore(suiteName: suite)
        XCTAssertFalse(settings.isEnabled)
        settings.setEnabled(true)
        XCTAssertTrue(settings.isEnabled)
        settings.setEnabled(false)
        XCTAssertFalse(settings.isEnabled)
    }

    func testRevocationPreventsLateRefreshFromRestoringCachedEvidence() throws {
        let suite = "CommunityGiftCardInventoryTests.revocation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommunityGiftCardInventorySettingsStore(suiteName: suite)
        let cache = CommunityGiftCardInventoryCacheStore(suiteName: suite)
        let evidence = GiftCardInventoryObservation(
            merchantKey: "metro",
            placeID: "metro-oshawa",
            instrumentKey: "Shoppers Drug Mart gift card",
            availability: .available,
            source: .communityObserved)

        settings.setEnabled(true)
        cache.replace([evidence])
        XCTAssertEqual(cache.evidence().count, 1)

        // Emulate Settings.bundle, which writes UserDefaults without calling `setEnabled`.
        defaults.set(false, forKey: "pickme.communityGiftCardInventory.enabled.v1")
        cache.replace([evidence])
        XCTAssertNil(defaults.data(forKey: "pickme.communityGiftCardInventory.cache.v1"))

        settings.setEnabled(true)
        cache.replace([evidence])
        defaults.set(false, forKey: "pickme.communityGiftCardInventory.enabled.v1")
        settings.reconcileConsent()
        XCTAssertNil(defaults.data(forKey: "pickme.communityGiftCardInventory.cache.v1"))
    }

    func testSubmissionWithPlaceIDOmitCoordinatesAndFinancialFields() throws {
        let observation = GiftCardInventoryObservation(
            id: "52d3231d-d17b-47ac-a7d7-4cd3604a618a",
            merchantKey: "Metro",
            placeID: "metro-oshawa",
            latitude: 43.897123,
            longitude: -78.865812,
            instrumentKey: "Shoppers Drug Mart gift card",
            availability: .available,
            source: .ownerConfirmed,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let data = try CommunityGiftCardInventoryWire.submissionData(for: observation)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["placeId"] as? String, "metro-oshawa")
        XCTAssertNil(json["latitude"])
        XCTAssertNil(json["longitude"])
        XCTAssertNil(json["cardId"])
        XCTAssertNil(json["amount"])
        XCTAssertNil(json["accountId"])
        XCTAssertNil(json["deviceId"])
    }

    func testTwoIndependentCommunityUnitsCanBecomeActionableButOneCannot() throws {
        let oneUnit = """
        {"schemaVersion":1,"signals":[{"candidateKey":"p:metro-oshawa","merchantKey":"metro","placeId":"metro-oshawa","latitude":null,"longitude":null,"day":"2026-09-04","availableUnits":1,"unavailableUnits":0}]}
        """.data(using: .utf8)!
        let twoUnits = """
        {"schemaVersion":1,"signals":[{"candidateKey":"p:metro-oshawa","merchantKey":"metro","placeId":"metro-oshawa","latitude":null,"longitude":null,"day":"2026-09-04","availableUnits":2,"unavailableUnits":0}]}
        """.data(using: .utf8)!
        let instrument = "Shoppers Drug Mart gift card"
        let query = GiftCardInventoryQuery(merchantKey: "Metro",
                                           placeID: "metro-oshawa",
                                           instrumentKey: instrument)
        let now = ISO8601DateFormatter().date(from: "2026-09-04T16:00:00Z")!

        let one = try CommunityGiftCardInventoryWire.decodeEvidence(oneUnit,
                                                                    instrumentKey: instrument)
        let two = try CommunityGiftCardInventoryWire.decodeEvidence(twoUnits,
                                                                    instrumentKey: instrument)
        XCTAssertFalse(GiftCardInventoryGraph.predict(for: query, evidence: one, now: now)
            .isActionableAvailable)
        XCTAssertTrue(GiftCardInventoryGraph.predict(for: query, evidence: two, now: now)
            .isActionableAvailable)
    }

    func testConflictingCommunityAggregateStaysUnknown() throws {
        let data = """
        {"schemaVersion":1,"signals":[{"candidateKey":"p:metro-oshawa","merchantKey":"metro","placeId":"metro-oshawa","latitude":null,"longitude":null,"day":"2026-09-04","availableUnits":1,"unavailableUnits":1}]}
        """.data(using: .utf8)!
        let instrument = "Shoppers Drug Mart gift card"
        let evidence = try CommunityGiftCardInventoryWire.decodeEvidence(data,
                                                                         instrumentKey: instrument)
        let query = GiftCardInventoryQuery(merchantKey: "Metro",
                                           placeID: "metro-oshawa",
                                           instrumentKey: instrument)
        let now = ISO8601DateFormatter().date(from: "2026-09-04T16:00:00Z")!
        XCTAssertEqual(GiftCardInventoryGraph.predict(for: query, evidence: evidence, now: now).state,
                       .unknown)
    }
}
