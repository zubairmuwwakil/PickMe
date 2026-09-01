import XCTest
@testable import CardCopilot

@MainActor
final class AmbientVisitStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "AmbientVisitStoreTests.\(UUID().uuidString)")!
        return suite
    }

    func testDismissalFlagSurvivesAWriteAndReadCycle() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        store.begin(AmbientVisit(enteredAt: .now, didEngage: false, purchaseId: nil,
                                 merchantName: "Loblaws"),
                    forRegionId: "area.1")

        XCTAssertEqual(store.visit(forRegionId: "area.1")?.liveActivityDismissed, false)

        store.update(regionId: "area.1") { $0.liveActivityDismissed = true }

        XCTAssertEqual(store.visit(forRegionId: "area.1")?.liveActivityDismissed, true)
    }

    /// Visits written before this field existed must still decode. Synthesised `Codable` throws
    /// on a missing key even when the property has a default, so the flag needs an explicit
    /// `decodeIfPresent` — without it every in-flight visit is silently dropped on upgrade.
    func testVisitsWrittenBeforeTheFieldExistedStillDecode() throws {
        let defaults = makeDefaults()
        let legacy = """
        {"area.1":{"enteredAt":0,"didEngage":false,"merchantName":"Loblaws"}}
        """
        defaults.set(Data(legacy.utf8), forKey: "ambientVisits.v1")

        let store = AmbientVisitStore(defaults: defaults)
        let visit = try XCTUnwrap(store.visit(forRegionId: "area.1"))
        XCTAssertEqual(visit.merchantName, "Loblaws")
        XCTAssertFalse(visit.liveActivityDismissed)
    }

    // MARK: - Dismissal survives the visit record

    /// The flag on `AmbientVisit` cannot answer "was this swiped away" across a geofence flap:
    /// an exit calls `end(regionId:)` and the next entry calls `begin(_:forRegionId:)`, so the
    /// record carrying the flag is destroyed and recreated between the swipe and the re-entry
    /// it is supposed to suppress. The dismissal is therefore recorded separately.
    func testADismissalOutlivesTheVisitRecordItWasMadeDuring() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        let arrival = Date()
        store.begin(AmbientVisit(enteredAt: arrival, didEngage: false, purchaseId: nil,
                                 merchantName: "Loblaws"), forRegionId: "area.1")

        store.markLiveActivityDismissed(regionId: "area.1", at: arrival)
        store.end(regionId: "area.1")

        XCTAssertNil(store.visit(forRegionId: "area.1"))
        XCTAssertTrue(store.liveActivityWasDismissed(regionId: "area.1",
                                                     now: arrival.addingTimeInterval(120)))
    }

    /// A swipe also lands on the in-flight visit, which is what the payment loop reads to decide
    /// whether a confirmation may be pushed during this visit.
    func testADismissalAlsoMarksTheVisitInFlight() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        store.begin(AmbientVisit(enteredAt: .now, didEngage: false, purchaseId: nil,
                                 merchantName: "Loblaws"), forRegionId: "area.1")

        store.markLiveActivityDismissed(regionId: "area.1")

        XCTAssertEqual(store.visit(forRegionId: "area.1")?.liveActivityDismissed, true)
    }

    func testADismissalIsHonouredInsideTheWindow() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        let swipe = Date()
        store.markLiveActivityDismissed(regionId: "area.1", at: swipe)

        XCTAssertTrue(store.liveActivityWasDismissed(
            regionId: "area.1", now: swipe.addingTimeInterval(dismissalRespectWindow - 60)))
    }

    /// Deliberately does not read inside the window first: a read refreshes the window, so doing
    /// so would measure from the refresh and this would assert nothing.
    func testADismissalExpiresOnceTheOwnerHasActuallyLeft() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        let swipe = Date()
        store.markLiveActivityDismissed(regionId: "area.1", at: swipe)

        XCTAssertFalse(store.liveActivityWasDismissed(
            regionId: "area.1", now: swipe.addingTimeInterval(dismissalRespectWindow + 60)))
    }

    /// Flapping refreshes the window, so a swipe holds for a whole long shop rather than expiring
    /// mid-visit and putting the card back while the owner is still inside the plaza.
    func testEachSuppressedReEntryExtendsTheWindow() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        let swipe = Date()
        store.markLiveActivityDismissed(regionId: "area.1", at: swipe)

        let flap = swipe.addingTimeInterval(dismissalRespectWindow - 60)
        XCTAssertTrue(store.liveActivityWasDismissed(regionId: "area.1", now: flap))

        // Without the refresh this is outside the original window and the card comes back.
        let laterFlap = flap.addingTimeInterval(dismissalRespectWindow - 60)
        XCTAssertTrue(store.liveActivityWasDismissed(regionId: "area.1", now: laterFlap))
    }

    func testADismissalAtOneRegionSaysNothingAboutAnother() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        store.markLiveActivityDismissed(regionId: "area.1")

        XCTAssertFalse(store.liveActivityWasDismissed(regionId: "area.2"))
    }

    func testForgettingEverythingClearsDismissals() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        store.markLiveActivityDismissed(regionId: "area.1")

        store.forgetAll()

        XCTAssertFalse(store.liveActivityWasDismissed(regionId: "area.1"))
    }
}
