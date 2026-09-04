import XCTest
import SwiftData
@testable import CardCopilotStore

final class MerchantMCCLearningEraseTests: XCTestCase {
    func testLocalHistoryEraseClearsRewardAndImportedMCCEvidence() throws {
        let suite = "MerchantMCCLearningEraseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let rewardStore = MerchantMCCRewardFeedbackStore(
            defaults: defaults, storageKey: "reward")
        let importedStore = MerchantMCCImportedEvidenceStore(
            defaults: defaults, storageKey: "imported")
        _ = rewardStore.recordRewardOutcome(
            merchantName: "Metro", candidateMCCs: [5411],
            sourceFingerprint: "purchase-1")
        _ = try importedStore.importCSV(Data(
            "Merchant,MCC,Transaction Date\nMetro,5411,09/01/2026\n".utf8))

        XCTAssertFalse(rewardStore.evidence().isEmpty)
        XCTAssertFalse(importedStore.evidence().isEmpty)

        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self, ExploredCell.self, ShoppingArea.self, AreaMember.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try LocalDataEraser(context: ModelContext(container),
                            metrics: CategoryResolutionMetricsStore(defaults: defaults, key: "metrics"),
                            rewardFeedbackStore: rewardStore,
                            importedEvidenceStore: importedStore)
            .eraseLocalHistory()

        XCTAssertTrue(rewardStore.evidence().isEmpty)
        XCTAssertTrue(importedStore.evidence().isEmpty)
    }
}
