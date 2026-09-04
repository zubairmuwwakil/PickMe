import XCTest
@testable import CardCopilotStore

/// The over-merge half: `merchantActivityKey` collapsing every same-named independent in the
/// country into one key, and what that key addresses — the owner's block list, their alert choice,
/// and the list of places they are told they keep going to.
///
/// The claim this suite exists to pin down is that fixing it moved nothing. Every key, preference
/// and block already on a device stays valid; it simply becomes the weaker of two tiers.
final class MerchantActivityKeyTests: XCTestCase {
    private let bloor = (latitude: 43.6532, longitude: -79.3832)
    private let vancouver = (latitude: 49.2827, longitude: -123.1207)

    private func key(_ name: String, _ fix: (latitude: Double, longitude: Double)?) -> String? {
        merchantActivityKey(name: name, locationIdentifier: nil,
                            latitude: fix?.latitude, longitude: fix?.longitude)
    }

    // MARK: - The split

    func testTwoSameNamedIndependentsInDifferentCitiesNoLongerShareAKey() {
        XCTAssertNotEqual(key("Rose Cafe", bloor), key("Rose Cafe", vancouver))
    }

    func testTheSameShopKeepsOneKeyAcrossASmallCoordinateDrift() {
        let drifted = (latitude: bloor.latitude + 0.0001, longitude: bloor.longitude - 0.0001)
        XCTAssertEqual(key("Rose Cafe", bloor), key("Rose Cafe", drifted))
    }

    /// A recognised chain is deliberately untouched. Sharing one key across every branch is what
    /// lets a Metro the owner has never entered inherit standing from the Metro they shop at, and
    /// what `ArrivalAlertScope.chain` exists to let them opt into.
    func testARecognisedChainKeepsOneKeyEverywhere() throws {
        XCTAssertEqual(key("Metro", bloor), key("Metro", vancouver))
        XCTAssertFalse(try XCTUnwrap(key("Metro", bloor)).hasPrefix(localMerchantKeyPrefix))
    }

    // MARK: - Nothing moved

    /// The compatibility claim, stated directly: with no coordinates the function returns exactly
    /// what it always returned. That is why no stored key had to be rewritten.
    func testWithoutCoordinatesTheKeyIsUnchangedFromBefore() {
        XCTAssertEqual(merchantActivityKey(name: "Rose Cafe", locationIdentifier: nil), "local:rosecafe")
        XCTAssertEqual(key("Rose Cafe", nil), "local:rosecafe")
    }

    func testAQualifiedKeyReportsTheProvisionalKeyItSupersedes() throws {
        let qualified = try XCTUnwrap(key("Rose Cafe", bloor))
        XCTAssertEqual(qualified, "local:rosecafe#4365_-7939")
        XCTAssertEqual(provisionalMerchantKey(for: qualified), "local:rosecafe")
    }

    func testAProvisionalKeyAndAChainKeyHaveNoWeakerTier() {
        XCTAssertNil(provisionalMerchantKey(for: "local:rosecafe"))
        XCTAssertNil(provisionalMerchantKey(for: "metro"))
    }

    /// A coordinate of exactly (0, 0) is the "brand only, no place" sentinel used throughout —
    /// `NearbyPlace.hasMonitorableLocation` says so — and must not be treated as a real cell off
    /// the coast of Ghana.
    func testTheNullIslandSentinelDoesNotQualifyAKey() {
        XCTAssertEqual(key("Rose Cafe", (latitude: 0, longitude: 0)), "local:rosecafe")
    }

    func testAKeylessNameStaysKeyless() {
        XCTAssertNil(merchantActivityKey(name: "", locationIdentifier: nil))
    }
}

/// The patronage and consent stores under a split keyspace.
final class SplitMerchantKeyStoreTests: XCTestCase {
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

    private let provisional = "local:rosecafe"
    private let qualified = "local:rosecafe#4365_-7939"
    private let neighbour = "local:rosecafe#4366_-7939"
    private let elsewhere = "local:rosecafe#4928_-12313"

    override func setUp() {
        super.setUp()
        suiteName = "SplitMerchantKeyStoreTests.\(UUID().uuidString)"
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

    // MARK: - Existing owner data survives

    /// The upgrade case. Months of visits sit under the name-only key; the first visit recorded
    /// with a fix opens a qualified one. Without the union the shop would look like it was
    /// discovered today and lose the standing it had already earned.
    func testStandingEarnedBeforeALocationWasKnownCarriesForward() {
        record(provisional, [daysAgo(30), daysAgo(20)])
        record(qualified, [now])

        XCTAssertEqual(store.visitDayKeys(for: qualified).count, 3)
        XCTAssertTrue(store.isFrequented(merchantKey: qualified, asOf: now, calendar: calendar))
        XCTAssertTrue(store.frequentedKeys(asOf: now, calendar: calendar).contains(qualified))
    }

    /// And it carries forward without being taken away from anyone. The provisional key is exactly
    /// the one that pooled namesakes, so a promotion that emptied it would move a different shop's
    /// history into this one's row.
    func testCarryingHistoryForwardDoesNotEmptyTheSharedKey() {
        record(provisional, [daysAgo(30), daysAgo(20)])
        record(qualified, [now])

        XCTAssertEqual(store.visitDayKeys(for: provisional).count, 2)
        XCTAssertEqual(store.visitDayKeys(for: elsewhere).count, 2,
                       "a namesake keeps the shared days it always had")
    }

    /// New days are the ones that must split. This is the defect stated positively: two unrelated
    /// shops accruing visits at the same time do not add up to one frequented merchant.
    func testNewVisitsAtNamesakesDoNotPoolTogether() {
        record(qualified, [now, daysAgo(1)])
        record(elsewhere, [daysAgo(2)])

        XCTAssertEqual(store.visitDayKeys(for: qualified).count, 2)
        XCTAssertEqual(store.visitDayKeys(for: elsewhere).count, 1)
    }

    func testTheOwnerFacingListShowsOneRowPerRealPlace() {
        record(provisional, [daysAgo(30)])
        record(qualified, [now])
        record(elsewhere, [daysAgo(1)])

        let learned = store.learnedMerchants(asOf: now, calendar: calendar)
        XCTAssertEqual(Set(learned.map(\.merchantKey)), [qualified, elsewhere])
        XCTAssertFalse(learned.contains { $0.merchantKey == provisional },
                       "the superseded row would show the same history a second time")
    }

    // MARK: - Consent

    /// A block is a promise about the future, and a cell edge is an arbitrary line through the
    /// world. A pin revision that crosses one must not silently lift it.
    func testABlockSurvivesTheShopMovingIntoAnAdjacentCell() {
        store.block(merchantKey: qualified)

        XCTAssertTrue(store.isBlocked(merchantKey: qualified))
        XCTAssertTrue(store.isBlocked(merchantKey: neighbour))
    }

    func testABlockDoesNotReachANamesakeInAnotherCity() {
        store.block(merchantKey: qualified)
        XCTAssertFalse(store.isBlocked(merchantKey: elsewhere))
    }

    /// Blocking widens; counting does not. Over-suppressing is a safe failure for a block and
    /// over-counting is not a safe failure for patronage, so the neighbourhood stops at consent.
    func testVisitsDoNotLeakBetweenAdjacentCells() {
        record(neighbour, [now, daysAgo(1), daysAgo(2)])
        XCTAssertTrue(store.visitDayKeys(for: qualified).isEmpty)
    }

    /// A block set before local keys carried a place token still binds afterwards, which is what
    /// lets the block list stay where it is instead of being rewritten.
    func testAnOlderNameOnlyBlockStillBinds() {
        store.block(merchantKey: provisional)
        XCTAssertTrue(store.isBlocked(merchantKey: qualified))
    }

    /// A delete that leaves the shared days behind is not a delete: `visitDayKeys` would keep
    /// reporting every day this shop accrued before its location was known.
    func testForgettingAMerchantTakesItsPreLocationHistoryWithIt() {
        record(provisional, [daysAgo(30), daysAgo(20)])
        record(qualified, [now])

        store.forget(merchantKey: qualified)
        XCTAssertTrue(store.visitDayKeys(for: qualified).isEmpty)
    }
}

/// Arrival preferences under the same split.
final class SplitMerchantKeyPreferenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: ArrivalAlertPreferenceStore!

    private let provisional = "local:rosecafe"
    private let qualified = "local:rosecafe#4365_-7939"
    private let elsewhere = "local:rosecafe#4928_-12313"

    override func setUp() {
        super.setUp()
        suiteName = "SplitMerchantKeyPreferenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ArrivalAlertPreferenceStore(defaults: defaults, key: "test.preferences")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil; defaults = nil
        super.tearDown()
    }

    private func preference(_ key: String, _ scope: ArrivalAlertScope) -> ArrivalAlertPreference {
        ArrivalAlertPreference(merchantKey: key, merchantName: "Rose Cafe", scope: scope)
    }

    /// A choice made before local keys carried a place token is still the owner's choice. This
    /// fallback is the entire reason no stored preference had to be rewritten.
    func testAChoiceMadeBeforeLocationsWereKnownStillApplies() {
        store.save(preference(provisional, .disabled))
        XCTAssertEqual(store.preference(for: qualified)?.scope, .disabled)
    }

    /// One-way, though: a shop the owner has since decided about individually must not be dragged
    /// back to the shared answer.
    func testAPerLocationChoiceOutranksTheOlderSharedOne() {
        store.save(preference(provisional, .disabled))
        store.save(preference(qualified, .exactLocation))
        XCTAssertEqual(store.preference(for: qualified)?.scope, .exactLocation)
        XCTAssertEqual(store.preference(for: elsewhere)?.scope, .disabled)
    }

    /// The defect stated positively: silencing one shop used to silence every shop in the country
    /// that happened to share its name.
    func testSilencingOneShopDoesNotSilenceANamesakeThatHasItsOwnChoice() {
        store.save(preference(qualified, .disabled))
        store.save(preference(elsewhere, .exactLocation))
        XCTAssertEqual(store.preference(for: elsewhere)?.scope, .exactLocation)
    }

    func testRemovingAChoiceAlsoClearsTheOlderSharedOneItFellBackTo() {
        store.save(preference(provisional, .disabled))
        store.save(preference(qualified, .exactLocation))

        store.remove(merchantKey: qualified)
        XCTAssertNil(store.preference(for: qualified))
    }
}
