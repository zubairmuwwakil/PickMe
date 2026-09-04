import XCTest
@testable import CardCopilotStore

final class CommunityMerchantMCCTests: XCTestCase {
    private let settingKey = "pickme.communityMerchantMCC.enabled.v1"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: settingKey)
        super.tearDown()
    }

    func testSharingDefaultsOff() {
        let suite = "CommunityMerchantMCCTests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = CommunityMerchantMCCSettingsStore(suiteName: suite)

        XCTAssertFalse(settings.isEnabled)
        settings.setEnabled(true)
        XCTAssertTrue(settings.isEnabled)
        settings.setEnabled(false)
        XCTAssertFalse(settings.isEnabled)
        defaults.removePersistentDomain(forName: suite)
    }

    func testRevocationPreventsLateRefreshFromRestoringCachedEvidence() throws {
        let suite = "CommunityMerchantMCCTests.revocation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CommunityMerchantMCCSettingsStore(suiteName: suite)
        let cache = CommunityMerchantMCCCacheStore(suiteName: suite)
        let evidence = MerchantMCCEvidence(
            merchantKey: "walmart",
            placeID: "apple-walmart",
            mcc: 5411,
            kind: .externalLocationReport,
            sourceReference: "community-mcc-v1:test")

        settings.setEnabled(true)
        cache.replace([evidence])
        XCTAssertEqual(cache.evidence().count, 1)

        // Emulate Settings.bundle, which writes UserDefaults without calling `setEnabled`.
        defaults.set(false, forKey: settingKey)
        cache.replace([evidence])
        XCTAssertNil(defaults.data(forKey: "pickme.communityMerchantMCC.cache.v1"))

        settings.setEnabled(true)
        cache.replace([evidence])
        defaults.set(false, forKey: settingKey)
        settings.reconcileConsent()
        XCTAssertNil(defaults.data(forKey: "pickme.communityMerchantMCC.cache.v1"))
    }

    func testOnlyLiteralLocatedCanonicalMccCanBecomeAReport() {
        let purchase = StoredPurchase(merchantLabel: "Walmart",
                                      merchantLatitude: 43.85,
                                      merchantLongitude: -79.02)
        purchase.observation = StoredObservation(observedCategory: "grocery",
                                                 observedMerchantCategoryCode: 5411)

        let report = CommunityMerchantMCCWire.report(from: purchase, network: nil)
        XCTAssertEqual(report?.merchantID, "walmart")
        XCTAssertEqual(report?.mcc, 5411)
        XCTAssertNil(report?.network)

        let categoryOnly = StoredPurchase(merchantLabel: "Walmart",
                                          merchantLatitude: 43.85,
                                          merchantLongitude: -79.02)
        categoryOnly.observation = StoredObservation(observedCategory: "grocery")
        XCTAssertNil(CommunityMerchantMCCWire.report(from: categoryOnly, network: nil))

        let unlocated = StoredPurchase(merchantLabel: "Walmart")
        unlocated.observation = StoredObservation(observedCategory: "grocery",
                                                  observedMerchantCategoryCode: 5411)
        XCTAssertNil(CommunityMerchantMCCWire.report(from: unlocated, network: nil))
    }

    func testPendingQueueRequiresOptInAndDeduplicatesObservationUUID() {
        let suite = "CommunityMerchantMCCTests.pending.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let queue = CommunityMerchantMCCPendingStore(defaults: defaults, key: "pending")
        let purchase = StoredPurchase(merchantLabel: "Walmart",
                                      merchantLatitude: 43.85,
                                      merchantLongitude: -79.02)
        let observation = StoredObservation(observedCategory: "grocery",
                                            observedMerchantCategoryCode: 5411)
        purchase.observation = observation

        UserDefaults.standard.set(false, forKey: settingKey)
        XCTAssertFalse(queue.enqueue(purchase: purchase))
        XCTAssertTrue(queue.reports().isEmpty)

        UserDefaults.standard.set(true, forKey: settingKey)
        XCTAssertTrue(queue.enqueue(purchase: purchase))
        XCTAssertFalse(queue.enqueue(purchase: purchase), "one observation UUID must enter the queue once")
        XCTAssertEqual(queue.reports().map(\.observationID), [observation.id])

        queue.markSubmitted(observation.id)
        XCTAssertTrue(queue.reports().isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }

    func testWireRejectsServerSignalBelowThreeSupportDays() throws {
        let json = """
        {"schemaVersion":1,"signals":[{
          "candidateKey":"p:apple-walmart|ch:inStore",
          "merchantId":"walmart","placeId":"apple-walmart",
          "latitude":null,"longitude":null,"channel":"inStore","network":null,
          "mcc":5411,"supportDays":2,"supportUnits":2,"totalUnits":2,
          "confidence":1.0,"latestDay":"2026-09-04"
        }]}
        """
        XCTAssertTrue(try CommunityMerchantMCCWire.decodeEvidence(Data(json.utf8)).isEmpty)
    }

    func testPublishedCommunitySignalStaysExternalAndCannotBecomeTrusted() throws {
        let json = """
        {"schemaVersion":1,"signals":[{
          "candidateKey":"p:apple-walmart|ch:inStore",
          "merchantId":"walmart","placeId":"apple-walmart",
          "latitude":null,"longitude":null,"channel":"inStore","network":null,
          "mcc":5411,"supportDays":4,"supportUnits":4,"totalUnits":5,
          "confidence":0.8,"latestDay":"2026-09-04"
        }]}
        """
        let evidence = try CommunityMerchantMCCWire.decodeEvidence(Data(json.utf8))
        let row = try XCTUnwrap(evidence.first)
        XCTAssertEqual(row.kind, .externalLocationReport)
        XCTAssertLessThanOrEqual(row.sourceConfidence, 0.80)

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Walmart", placeID: "apple-walmart"),
            evidence: evidence,
            now: ISO8601DateFormatter().date(from: "2026-09-04T18:00:00Z")!)
        XCTAssertFalse(prediction.isTrusted)
        XCTAssertEqual(prediction.directObservationCount, 0)
    }
}
