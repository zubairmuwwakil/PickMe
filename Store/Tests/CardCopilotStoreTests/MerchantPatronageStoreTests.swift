import XCTest
@testable import CardCopilotStore

final class MerchantPatronageStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: MerchantPatronageStore!

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_787_000_000)
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    override func setUp() {
        super.setUp()
        suiteName = "MerchantPatronageStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = MerchantPatronageStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil; defaults = nil
        super.tearDown()
    }

    private func record(_ key: String, _ dates: [Date]) {
        for date in dates { store.recordVisit(merchantKey: key, at: date, calendar: calendar) }
    }

    func testThreeSeparateDaysEarnStanding() {
        record("loblaws", [now, daysAgo(7), daysAgo(20)])
        XCTAssertTrue(store.isFrequented(merchantKey: "loblaws", asOf: now, calendar: calendar))
    }

    func testRepeatedCapturesOnOneDayDoNotEarnStanding() {
        record("starbucks", [now, now.addingTimeInterval(600), now.addingTimeInterval(4_000)])
        XCTAssertFalse(store.isFrequented(merchantKey: "starbucks", asOf: now, calendar: calendar))
    }

    func testMerchantsAreCountedIndependently() {
        record("loblaws", [now, daysAgo(7), daysAgo(20)])
        record("sobeys", [now])
        XCTAssertTrue(store.isFrequented(merchantKey: "loblaws", asOf: now, calendar: calendar))
        XCTAssertFalse(store.isFrequented(merchantKey: "sobeys", asOf: now, calendar: calendar))
    }

    /// Bounded retention is a promise the privacy labels make, so it cannot depend on anyone
    /// remembering to ask whether a merchant still qualifies. Writing prunes.
    func testAgedOutDaysArePrunedOnWrite() {
        record("metro", [daysAgo(200), daysAgo(150)])
        record("metro", [now])
        let kept = store.visitDayKeys(for: "metro")
        XCTAssertEqual(kept, [patronageDayKey(for: now, calendar: calendar)])
    }

    func testFrequentedKeysListsOnlyMerchantsThatQualify() {
        record("loblaws", [now, daysAgo(7), daysAgo(20)])
        record("sobeys", [now, daysAgo(7)])
        XCTAssertEqual(store.frequentedKeys(asOf: now, calendar: calendar), ["loblaws"])
    }

    func testForgetAllErasesEveryMerchant() {
        record("loblaws", [now, daysAgo(7), daysAgo(20)])
        store.forgetAll()
        XCTAssertTrue(store.frequentedKeys(asOf: now, calendar: calendar).isEmpty)
        XCTAssertTrue(store.visitDayKeys(for: "loblaws").isEmpty)
    }

    // MARK: - forget

    func testForgetOneMerchantOnlyClearsThatMerchant() {
        record("loblaws", [now, daysAgo(7), daysAgo(20)])
        record("sobeys", [now, daysAgo(7), daysAgo(20)])
        store.forget(merchantKey: "loblaws")
        XCTAssertTrue(store.visitDayKeys(for: "loblaws").isEmpty)
        XCTAssertFalse(store.visitDayKeys(for: "sobeys").isEmpty)
    }

    // MARK: - block list

    func testBlockingAMerchantStopsFutureVisitsFromAccruing() {
        store.block(merchantKey: "esso")
        record("esso", [now, daysAgo(7), daysAgo(20)])
        XCTAssertTrue(store.visitDayKeys(for: "esso").isEmpty)
        XCTAssertFalse(store.isFrequented(merchantKey: "esso", asOf: now, calendar: calendar))
    }

    func testBlockingAnAlreadyFrequentedMerchantRemovesItFromStanding() {
        record("loblaws", [now, daysAgo(7), daysAgo(20)])
        XCTAssertTrue(store.isFrequented(merchantKey: "loblaws", asOf: now, calendar: calendar))
        store.block(merchantKey: "loblaws")
        XCTAssertFalse(store.isFrequented(merchantKey: "loblaws", asOf: now, calendar: calendar))
        XCTAssertTrue(store.frequentedKeys(asOf: now, calendar: calendar).isEmpty)
    }

    func testUnblockingAllowsVisitsToAccrueAgain() {
        store.block(merchantKey: "esso")
        store.unblock(merchantKey: "esso")
        record("esso", [now, daysAgo(7), daysAgo(20)])
        XCTAssertTrue(store.isFrequented(merchantKey: "esso", asOf: now, calendar: calendar))
    }

    func testIsBlockedAndBlockedKeys() {
        store.block(merchantKey: "esso")
        XCTAssertTrue(store.isBlocked(merchantKey: "esso"))
        XCTAssertEqual(store.blockedKeys(), ["esso"])
        store.unblock(merchantKey: "esso")
        XCTAssertFalse(store.isBlocked(merchantKey: "esso"))
        XCTAssertTrue(store.blockedKeys().isEmpty)
    }

    func testForgetAllClearsTheBlockListToo() {
        // "Erase this iPhone's history" is a full wipe. Leaving the block list behind would
        // silently keep suppressing a merchant the owner has no remaining way to see or reverse.
        store.block(merchantKey: "esso")
        store.forgetAll()
        XCTAssertTrue(store.blockedKeys().isEmpty)
        XCTAssertFalse(store.isBlocked(merchantKey: "esso"))
    }

    // MARK: - learnedMerchants

    func testLearnedMerchantsReturnsCountsAndQualification() {
        record("loblaws", [daysAgo(20), daysAgo(7), now])
        record("sobeys", [daysAgo(7), now])
        let learned = store.learnedMerchants(asOf: now, calendar: calendar)
        let loblaws = learned.first { $0.merchantKey == "loblaws" }
        let sobeys = learned.first { $0.merchantKey == "sobeys" }
        XCTAssertEqual(loblaws?.visitCount, 3)
        XCTAssertEqual(loblaws?.qualifies, true)
        XCTAssertEqual(loblaws?.displayName, "Loblaws")
        XCTAssertEqual(loblaws?.earliestDayKey, patronageDayKey(for: daysAgo(20), calendar: calendar))
        XCTAssertEqual(loblaws?.latestDayKey, patronageDayKey(for: now, calendar: calendar))
        XCTAssertEqual(sobeys?.visitCount, 2)
        XCTAssertEqual(sobeys?.qualifies, false)
        XCTAssertEqual(sobeys?.displayName, "Sobeys")
    }

    func testLearnedMerchantsFallsBackToRawKeyWhenUnindexed() {
        record("some-unindexed-place", [now])
        let learned = store.learnedMerchants(asOf: now, calendar: calendar)
        XCTAssertEqual(learned.first?.displayName, "some-unindexed-place")
    }

    func testLearnedMerchantsOnlyCountsDaysInsideTheWindow() {
        record("loblaws", [daysAgo(200), daysAgo(150), now, daysAgo(7), daysAgo(20)])
        let learned = store.learnedMerchants(asOf: now, calendar: calendar)
        XCTAssertEqual(learned.first { $0.merchantKey == "loblaws" }?.visitCount, 3)
    }
}
