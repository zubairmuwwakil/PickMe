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

        let purchase = StoredPurchase(
            createdAt: ISO8601DateFormatter().date(from: "2026-09-01T16:00:00Z")!,
            merchantLabel: "Metro",
            merchantKey: "Metro",
            merchantLatitude: 43.653,
            merchantLongitude: -79.383)
        purchase.amountCad = 42.17
        purchase.cardUsedId = "visa-card"

        let csv = """
        Merchant,MCC,Transaction Date,Billing Amount,Billing Currency Code,Network
        Metro,5411,09/01/2026,42.17,CAD,Visa
        """
        let summary = try imported.importCSV(Data(csv.utf8), localPurchases: [purchase],
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
}
