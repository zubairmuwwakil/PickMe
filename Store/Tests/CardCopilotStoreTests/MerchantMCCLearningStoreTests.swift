import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class MerchantMCCLearningStoreTests: XCTestCase {
    private func makeStore() -> (MerchantMCCLearningStore, UserDefaults, String) {
        let suite = "MerchantMCCLearningStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let seed = MerchantMCCRuntimeSeed(
            graphVersion: "1.0", generatedAt: "test",
            merchants: [MerchantMCCSeedMerchant(id: "walmart", name: "Walmart", seedMcc: 5411,
                                                candidateMccs: [5411, 5441], weights: [0.7, 0.3],
                                                confidence: 0.40)])
        return (MerchantMCCLearningStore(defaults: defaults, storageKey: "evidence", seed: seed),
                defaults, suite)
    }

    func testDescriptorMatchesSeedAndExactMCCPersists() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.seedMerchant(matching: "WALMART #123 TORONTO")?.id, "walmart")
        XCTAssertTrue(store.recordExactMCC(merchantName: "Walmart #123", mcc: 5411,
                                           sourceFingerprint: "purchase-1"))
        XCTAssertFalse(store.recordExactMCC(merchantName: "Walmart #123", mcc: 5411,
                                            sourceFingerprint: "purchase-1"),
                       "the same evidence fingerprint must not vote twice")

        let reloadedSeed = MerchantMCCRuntimeSeed(
            graphVersion: "1.0", generatedAt: "test",
            merchants: [MerchantMCCSeedMerchant(id: "walmart", name: "Walmart", seedMcc: 5411,
                                                candidateMccs: [5411, 5441], weights: [0.7, 0.3],
                                                confidence: 0.40)])
        let reloaded = MerchantMCCLearningStore(defaults: defaults, storageKey: "evidence",
                                                 seed: reloadedSeed)
        XCTAssertEqual(reloaded.evidenceCount(for: "Walmart"), 1)
    }

    func testGraphPosteriorProjectsToScoreableCategory() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = store.recordExactMCC(merchantName: "Walmart", mcc: 5411,
                                 sourceFingerprint: "purchase-1")
        _ = store.recordExactMCC(merchantName: "Walmart", mcc: 5411,
                                 sourceFingerprint: "purchase-2")
        let merchant = NearbyPlace(id: "walmart", name: "Walmart", poiCategoryRaw: "store",
                                   latitude: 0, longitude: 0, distanceMeters: nil)
        let prediction = try XCTUnwrap(merchantMCCGraphPrediction(for: merchant,
                                                                 learningStore: store))
        XCTAssertEqual(prediction.category, "grocery")
        XCTAssertEqual(prediction.merchantCategoryCode, 5411)
        XCTAssertNotEqual(prediction.confidenceSource, .observedMcc,
                          "user-derived graph evidence is not a network-observed MCC")
    }
}
