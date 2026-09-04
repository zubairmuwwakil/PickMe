import XCTest
@testable import CardCopilotStore

final class MerchantMCCImportedJoinProjectionTests: XCTestCase {
    func testSafelyJoinedIssuerMCCProjectsAsObservedMCCAtSameLocation() throws {
        let suite = "MerchantMCCImportedJoinProjectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let imported = MerchantMCCImportedEvidenceStore(defaults: defaults, storageKey: "imports")
        let feedback = MerchantMCCRewardFeedbackStore(defaults: defaults, storageKey: "rewards")
        let community = CommunityMerchantMCCCacheStore(suiteName: suite)

        let purchase = locatedPurchase()
        let summary = try imported.importCSV(Data(csv(mcc: 5411).utf8), localPurchases: [purchase],
                                             cardNetworksByID: ["visa-card": "visa"])
        XCTAssertEqual(summary.locationJoinedRows, 1)

        let prediction = try XCTUnwrap(merchantMCCGraphPrediction(
            for: NearbyPlace(id: "metro", name: "Metro", poiCategoryRaw: nil,
                             latitude: 43.653, longitude: -79.383),
            feedbackStore: feedback,
            importedStore: imported,
            communityStore: community))

        XCTAssertEqual(prediction.merchantCategoryCode, 5411)
        XCTAssertEqual(prediction.confidenceSource, .observedMcc)
        XCTAssertEqual(prediction.rawCategory, "merchantMccGraph:ownerLocatedExact")
        XCTAssertGreaterThanOrEqual(prediction.confidenceScore, ConfidenceSource.observedMcc.defaultScore)
    }

    func testSameStoredObservationAndIssuerRowCountAsOneDirectObservation() throws {
        let suite = "MerchantMCCImportedJoinProjectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let imported = MerchantMCCImportedEvidenceStore(defaults: defaults, storageKey: "imports")
        let purchase = locatedPurchase()
        let observation = StoredObservation(observedCategory: "grocery",
                                            observedMerchantCategoryCode: 5411,
                                            confirmedAt: purchase.createdAt)
        purchase.observation = observation

        _ = try imported.importCSV(Data(csv(mcc: 5411).utf8), localPurchases: [purchase],
                                   cardNetworksByID: ["visa-card": "visa"])
        let importedEvidence = try XCTUnwrap(imported.evidence().first)
        XCTAssertEqual(importedEvidence.id, "observation:\(observation.id.uuidString)")

        let historicalEvidence = MerchantMCCGraphEvidenceBuilder.evidence(from: [purchase])
        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Metro", latitude: 43.653,
                                  longitude: -79.383, channel: .inStore),
            evidence: historicalEvidence + imported.evidence(),
            now: purchase.createdAt.addingTimeInterval(86_400))

        XCTAssertEqual(prediction.directObservationCount, 1,
                       "one transaction seen through two acquisition paths must not become two corroborations")
    }

    func testConflictingStoredObservationAndIssuerRowRemainVisibleAsConflict() throws {
        let suite = "MerchantMCCImportedJoinProjectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let imported = MerchantMCCImportedEvidenceStore(defaults: defaults, storageKey: "imports")
        let purchase = locatedPurchase()
        purchase.observation = StoredObservation(observedCategory: "generalMerchandise",
                                                 observedMerchantCategoryCode: 5311,
                                                 confirmedAt: purchase.createdAt)

        _ = try imported.importCSV(Data(csv(mcc: 5411).utf8), localPurchases: [purchase],
                                   cardNetworksByID: ["visa-card": "visa"])
        let historicalEvidence = MerchantMCCGraphEvidenceBuilder.evidence(from: [purchase])
        let importedEvidence = try XCTUnwrap(imported.evidence().first)

        XCTAssertNotEqual(importedEvidence.id, historicalEvidence.first?.id,
                          "a disagreement must not be hidden by cross-source dedupe")
        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Metro", latitude: 43.653,
                                  longitude: -79.383, channel: .inStore),
            evidence: historicalEvidence + [importedEvidence],
            now: purchase.createdAt.addingTimeInterval(86_400))
        XCTAssertEqual(Set(prediction.candidates.map(\.mcc)), Set([5311, 5411]))
    }

    func testUnlocatedIssuerMCCStillProjectsAsBrandPrior() throws {
        let suite = "MerchantMCCImportedJoinProjectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let imported = MerchantMCCImportedEvidenceStore(defaults: defaults, storageKey: "imports")
        let feedback = MerchantMCCRewardFeedbackStore(defaults: defaults, storageKey: "rewards")
        let community = CommunityMerchantMCCCacheStore(suiteName: suite)

        let csv = "Merchant,MCC,Transaction Date\nMetro,5411,09/01/2026\n"
        _ = try imported.importCSV(Data(csv.utf8))

        let prediction = try XCTUnwrap(merchantMCCGraphPrediction(
            for: NearbyPlace(id: "metro", name: "Metro", poiCategoryRaw: nil,
                             latitude: 43.653, longitude: -79.383),
            feedbackStore: feedback,
            importedStore: imported,
            communityStore: community))

        XCTAssertEqual(prediction.merchantCategoryCode, 5411)
        XCTAssertEqual(prediction.confidenceSource, .brandPrior)
        XCTAssertEqual(prediction.rawCategory, "merchantMccGraph:ownerImportedExact")
    }

    private func locatedPurchase() -> StoredPurchase {
        let purchase = StoredPurchase(
            createdAt: ISO8601DateFormatter().date(from: "2026-09-01T16:00:00Z")!,
            merchantLabel: "Metro",
            merchantKey: "Metro",
            merchantLatitude: 43.653,
            merchantLongitude: -79.383)
        purchase.amountCad = 42.17
        purchase.cardUsedId = "visa-card"
        return purchase
    }

    private func csv(mcc: Int) -> String {
        """
        Merchant,MCC,Transaction Date,Billing Amount,Billing Currency Code,Network
        Metro,\(mcc),09/01/2026,42.17,CAD,Visa
        """
    }
}
