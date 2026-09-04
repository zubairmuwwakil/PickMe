import XCTest
import SwiftData
@testable import CardCopilotStore

final class MerchantMCCIdentityPipelineTests: XCTestCase {
    private var container: ModelContainer!
    private var predictionLog: PredictionLog!
    private var defaults: UserDefaults!
    private var suite: String!
    private var identityStore: MerchantMCCIdentityLearningStore!
    private var autoLog: AutoCaptureLog!

    private let noon = Date(timeIntervalSince1970: 1_788_528_000)

    override func setUpWithError() throws {
        suite = "MerchantMCCIdentityPipelineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        identityStore = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")
        container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        predictionLog = PredictionLog(context: context)
        autoLog = AutoCaptureLog(context: context, identityStore: identityStore)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        autoLog = nil
        identityStore = nil
        predictionLog = nil
        container = nil
        defaults = nil
        suite = nil
        super.tearDown()
    }

    private func openWalmartPrediction(id: String, at date: Date) throws -> StoredPrediction {
        let prediction = try predictionLog.record(StoredPrediction(
            merchantName: "Walmart", merchantIdentifier: id,
            predictedCategory: "other", confidenceSource: .brandPrior,
            winnerCardId: "test-card", winnerValueCad: 0,
            headline: "test", recordedAt: date))
        _ = try predictionLog.recordPurchase(for: prediction, at: date)
        return prediction
    }

    private func capture(id: String, at date: Date,
                         currency: String? = "CAD",
                         resolvedCardId: String? = "test-card") -> WalletFeedback {
        WalletFeedback(eventId: id, capturedAt: date.addingTimeInterval(60),
                       merchantRaw: "MART #1234", merchantNormalized: nil,
                       amountMinor: 1250, currency: currency,
                       cardRaw: "Test Card", resolvedCardId: resolvedCardId,
                       verdict: "best", warning: nil)
    }

    func testTwoStrictAutomaticMatchesTrainAnActionableAlias() throws {
        let firstDate = noon
        let first = try openWalmartPrediction(id: "poi-walmart-1", at: firstDate)
        XCTAssertTrue(try autoLog.ingest(feedback: [capture(id: "evt-1", at: firstDate)],
                                         openPredictions: [first]).isEmpty)
        XCTAssertEqual(identityStore.evidenceCount(for: "MART #1234"), 1)
        XCTAssertNil(identityStore.match(merchantName: "MART #1234"))

        let secondDate = noon.addingTimeInterval(3_600)
        let second = try openWalmartPrediction(id: "poi-walmart-2", at: secondDate)
        XCTAssertTrue(try autoLog.ingest(feedback: [capture(id: "evt-2", at: secondDate)],
                                         openPredictions: [second]).isEmpty)

        XCTAssertEqual(identityStore.evidenceCount(for: "MART #1234"), 2)
        XCTAssertEqual(identityStore.match(merchantName: "MART #1234")?.merchant.id, "walmart")
    }

    func testIncompleteCaptureDoesNotTrainIdentity() throws {
        let prediction = try openWalmartPrediction(id: "poi-walmart-1", at: noon)
        _ = try autoLog.ingest(feedback: [capture(id: "evt-1", at: noon, currency: nil)],
                               openPredictions: [prediction])

        XCTAssertEqual(identityStore.evidenceCount(for: "MART #1234"), 0)
    }

    func testUnresolvedCardDoesNotTrainIdentity() throws {
        let prediction = try openWalmartPrediction(id: "poi-walmart-1", at: noon)
        _ = try autoLog.ingest(
            feedback: [capture(id: "evt-1", at: noon, resolvedCardId: nil)],
            openPredictions: [prediction])

        XCTAssertEqual(identityStore.evidenceCount(for: "MART #1234"), 0)
    }
}
