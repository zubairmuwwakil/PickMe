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

    func testRewardOutcomeFingerprintReplacesRatherThanDoubleVotes() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.recordRewardOutcome(merchantName: "Walmart",
                                                  candidateMCCs: [5411, 5462],
                                                  sourceFingerprint: "purchase-1"), 2)
        XCTAssertTrue(store.hasRewardOutcome(merchantName: "Walmart",
                                             sourceFingerprint: "purchase-1"))
        XCTAssertEqual(store.recordRewardOutcome(merchantName: "Walmart",
                                                  candidateMCCs: [5812, 5814],
                                                  sourceFingerprint: "purchase-1"), 2)
        XCTAssertEqual(store.evidenceCount(for: "Walmart"), 2,
                       "correcting one purchase must replace its old reward vote")

        let posterior = try XCTUnwrap(store.posterior(merchantName: "Walmart"))
        XCTAssertFalse(posterior.candidates.contains { $0.mcc == 5462 })
        XCTAssertTrue(posterior.candidates.contains { $0.mcc == 5812 })
        XCTAssertTrue(posterior.candidates.contains { $0.mcc == 5814 })
    }

    func testRewardFeedbackPromptsOnceAndProjectsBroadGroceryMCCs() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let purchase = StoredPurchase(
            merchantLabel: "Walmart #123",
            activitySource: .walletCapture,
            merchantIdentifier: "walmart-123",
            merchantLatitude: 43.6532,
            merchantLongitude: -79.3832,
            categoryAtPurchase: "other",
            categoryConfidence: .brandPrior)

        XCTAssertTrue(MerchantMCCRewardFeedback.shouldPrompt(for: purchase, learningStore: store))
        XCTAssertEqual(MerchantMCCRewardFeedback.record(category: "grocery", for: purchase,
                                                         learningStore: store), 6)
        XCTAssertFalse(MerchantMCCRewardFeedback.shouldPrompt(for: purchase, learningStore: store),
                       "a purchase that already taught the graph must not prompt again")
        XCTAssertEqual(MerchantMCCRewardFeedback.inferredCategory(for: 5462), "grocery")

        let merchant = NearbyPlace(id: "walmart-123", name: "Walmart #123",
                                   poiCategoryRaw: "store",
                                   latitude: 43.6532, longitude: -79.3832,
                                   distanceMeters: nil)
        let prediction = try XCTUnwrap(merchantMCCGraphPrediction(for: merchant,
                                                                 learningStore: store))
        XCTAssertEqual(prediction.category, "grocery")
        XCTAssertNotEqual(prediction.confidenceSource, .observedMcc)
    }

    func testObservedMCCSuppressesRewardFeedbackPrompt() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let purchase = StoredPurchase(
            merchantLabel: "Walmart",
            categoryAtPurchase: "grocery",
            categoryConfidence: .observedMcc,
            merchantCategoryCode: 5411)
        XCTAssertFalse(MerchantMCCRewardFeedback.shouldPrompt(for: purchase, learningStore: store))
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
