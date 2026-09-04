import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

final class MerchantMCCLearningStoreTests: XCTestCase {
    private func makeStore() -> (MerchantMCCRewardFeedbackStore, UserDefaults, String) {
        let suite = "MerchantMCCLearningStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (MerchantMCCRewardFeedbackStore(defaults: defaults, storageKey: "evidence"),
                defaults, suite)
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

        let evidence = store.evidence(for: "Walmart")
        XCTAssertEqual(evidence.count, 2,
                       "correcting one purchase must replace its old reward vote")
        XCTAssertEqual(Set(evidence.compactMap(\.mcc)), [5812, 5814])
        XCTAssertEqual(evidence.reduce(0) { $0 + $1.sourceConfidence }, 1, accuracy: 0.0001,
                       "one answer is split across candidates instead of multiplying its vote")
        XCTAssertTrue(evidence.allSatisfy { $0.kind == .rewardOutcomeInference })
    }

    func testRewardEvidencePersistsWithoutTransactionDetails() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = store.recordRewardOutcome(merchantName: "Walmart",
                                      candidateMCCs: [5411, 5462],
                                      latitude: 43.6532, longitude: -79.3832,
                                      sourceFingerprint: "purchase-1")
        let reloaded = MerchantMCCRewardFeedbackStore(defaults: defaults, storageKey: "evidence")
        let evidence = reloaded.evidence(for: "Walmart")
        XCTAssertEqual(evidence.count, 2)
        XCTAssertEqual(Set(evidence.compactMap(\.sourceReference)), ["purchase-1"])
        XCTAssertTrue(evidence.allSatisfy { $0.latitude == 43.6532 && $0.longitude == -79.3832 })
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

        XCTAssertTrue(MerchantMCCRewardFeedback.shouldPrompt(for: purchase, feedbackStore: store))
        XCTAssertEqual(MerchantMCCRewardFeedback.record(category: "grocery", for: purchase,
                                                         feedbackStore: store), 6)
        XCTAssertFalse(MerchantMCCRewardFeedback.shouldPrompt(for: purchase, feedbackStore: store),
                       "a purchase that already taught the graph must not prompt again")
        XCTAssertEqual(MerchantMCCRewardFeedback.inferredCategory(for: 5462), "grocery")

        let merchant = NearbyPlace(id: "walmart-123", name: "Walmart #123",
                                   poiCategoryRaw: "store",
                                   latitude: 43.6532, longitude: -79.3832,
                                   distanceMeters: nil)
        let prediction = try XCTUnwrap(merchantMCCGraphPrediction(for: merchant,
                                                                 feedbackStore: store))
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
        XCTAssertFalse(MerchantMCCRewardFeedback.shouldPrompt(for: purchase, feedbackStore: store))
    }

    func testRewardInferenceFeedsCanonicalGraphWithoutBecomingObserved() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let seed = try XCTUnwrap(MerchantMCCSeedCatalogue.match(merchantName: "Walmart"))

        _ = store.recordRewardOutcome(merchantName: "Walmart", candidateMCCs: [5812, 5814],
                                      sourceFingerprint: "purchase-1")
        let query = MerchantMCCQuery(merchantKey: seed.merchant.name)
        let prediction = MerchantMCCGraph.predict(
            for: query,
            seedMCC: seed.profile.primaryMcc,
            evidence: MerchantMCCSeedCatalogue.externalEvidence(for: seed.merchant)
                + store.evidence(for: "Walmart"))

        XCTAssertTrue(prediction.candidates.contains { $0.mcc == 5812 })
        XCTAssertTrue(prediction.candidates.contains { $0.mcc == 5814 })
        XCTAssertFalse(prediction.isObserved,
                       "reward inference must never masquerade as an explicit network MCC")
    }
}
