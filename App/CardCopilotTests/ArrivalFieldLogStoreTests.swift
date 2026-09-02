import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// The dev-only ring buffer. Bounded on purpose: a field week is the unit of analysis, and an
/// unbounded log in `UserDefaults` would eventually be the reason someone turns the build off.
@MainActor
final class ArrivalFieldLogStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "arrival-field-log-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func record(regionId: String = "ambient.region.area:1",
                        at offset: TimeInterval = 0) -> ArrivalFieldRecord {
        ArrivalFieldRecord(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            regionId: regionId, source: .regionEntry, rung: .areaMember,
            resolvedMerchantName: "Riverbend Compounding", resolvedCategory: "drugStore",
            estimatedAmountCad: 25,
            gateInput: AmbientGateInput(
                merchantConfidence: .categoryMatched, recommendedCardId: "amex-cobalt",
                defaultCardId: "wealthsimple-vip",
                advantage: AmbientAdvantage(percentagePoints: 1.5, cad: 0.375),
                switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                                 minAdvantageCad: 0.25, semantics: "both"),
                isMuted: false),
            deliveryTier: .confirm, suppressionReasons: [.advantageBelowCategoryThreshold],
            policy: .shipped)
    }

    func testRecordsComeBackOldestFirst() {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 10)
        store.record(record(at: 0))
        store.record(record(at: 60))
        XCTAssertEqual(ArrivalFieldLogStore(defaults: defaults, capacity: 10).all().count, 2)
        XCTAssertEqual(store.all().first?.recordedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// The buffer drops the oldest, never the newest: a week of driving must not be unable to
    /// record the arrival that happens today.
    func testTheBufferDropsTheOldestRecord() {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 2)
        store.record(record(at: 0))
        store.record(record(at: 60))
        store.record(record(at: 120))
        XCTAssertEqual(store.all().count, 2)
        XCTAssertEqual(store.all().first?.recordedAt, Date(timeIntervalSince1970: 1_700_000_060))
    }

    /// Engagement arrives minutes later, from a notification action, carrying only the region id.
    func testEngagementLandsOnTheMostRecentArrivalForThatRegion() throws {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 10)
        store.record(record(regionId: "a", at: 0))
        store.record(record(regionId: "a", at: 3600))
        store.record(record(regionId: "b", at: 7200))

        store.recordEngagement(.usedRecommendedCard, regionId: "a")

        XCTAssertNil(store.all()[0].engagement)
        XCTAssertEqual(store.all()[1].engagement, .usedRecommendedCard)
        XCTAssertNil(store.all()[2].engagement)
    }

    /// The owner can tap "used this card" and later mute the same merchant. The first answer is
    /// the one about that alert; overwriting it would turn a useful alert into a muted one.
    func testEngagementIsNotOverwrittenOnceRecorded() {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 10)
        store.record(record(regionId: "a"))
        store.recordEngagement(.usedRecommendedCard, regionId: "a")
        store.recordEngagement(.mutedMerchant, regionId: "a")
        XCTAssertEqual(store.all()[0].engagement, .usedRecommendedCard)
    }

    func testEngagementForAnUnknownRegionIsDropped() {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 10)
        store.record(record(regionId: "a"))
        store.recordEngagement(.mutedMerchant, regionId: "nowhere")
        XCTAssertNil(store.all()[0].engagement)
    }

    func testForgettingEmptiesTheLog() {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 10)
        store.record(record())
        store.forgetAll()
        XCTAssertTrue(store.all().isEmpty)
    }

    /// A record shape that changed between builds must not take the week with it.
    func testAnUndecodableLogReadsAsEmptyRatherThanCrashing() {
        defaults.set(Data("not a log".utf8), forKey: "ambientFieldLog.v1")
        XCTAssertTrue(ArrivalFieldLogStore(defaults: defaults, capacity: 10).all().isEmpty)
    }

    /// The export is what leaves the phone, so it has to be readable by something other than
    /// this app: pretty-printed JSON with ISO-8601 dates, not a property list of binary blobs.
    func testTheExportIsReadableJsonCarryingTheDerivedMetrics() throws {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 10)
        store.record(record())
        let data = try XCTUnwrap(store.exportJSON(receipts: []))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"records\""))
        XCTAssertTrue(text.contains("\"metrics\""))
        XCTAssertTrue(text.contains("Riverbend Compounding"))

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["records"] as? [Any])?.count, 1)
    }

    /// Receipts are joined at export time rather than at capture: a charge posts minutes to hours
    /// after the arrival, long after the record was written.
    func testTheExportJoinsReceiptsRatherThanShippingThemUnmatched() throws {
        let store = ArrivalFieldLogStore(defaults: defaults, capacity: 10)
        store.record(record())
        let receipt = ArrivalReceipt(merchantDescriptor: "RIVERBEND COMPOUNDING",
                                     amountCad: 33.90,
                                     capturedAt: Date(timeIntervalSince1970: 1_700_000_600))
        let data = try XCTUnwrap(store.exportJSON(receipts: [receipt]))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("33.9"))
        XCTAssertTrue(text.contains("\"arrivalsWithAReceipt\" : 1"))
    }
}
