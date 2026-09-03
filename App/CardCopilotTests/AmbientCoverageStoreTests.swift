import XCTest
import CardCopilotStore
@testable import CardCopilot

/// The new counters going through `DailyLogStore`, not just through the model.
///
/// Written after the counters themselves rather than before them, to close a gap the model tests
/// structurally cannot reach: `AmbientWakeCause` and `ArrivalNotificationDelivery` are enum
/// dictionary *keys*, which `JSONEncoder` writes as a flat array rather than an object, and that
/// encoding has to survive being nested inside the `[String: AmbientCoverageLog]` map of days.
/// If it did not, every new counter would read as zero and nothing would say so.
@MainActor
final class AmbientCoverageStoreTests: XCTestCase {

    private func makeStore() -> (AmbientCoverageStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "AmbientCoverageStore.\(UUID().uuidString)")!
        return (AmbientCoverageStore(defaults: defaults), defaults)
    }

    func testDeliveryOutcomesSurviveTheDailyRoundTrip() {
        let (store, defaults) = makeStore()

        store.recordNotificationDelivery(.acceptedAndPresent)
        store.recordNotificationDelivery(.acceptedThenAbsent)
        store.recordNotificationDelivery(.acceptedThenAbsent)

        let reloaded = AmbientCoverageStore(defaults: defaults).lastSevenDays()
        XCTAssertEqual(reloaded.notificationDeliveryByOutcome[.acceptedAndPresent], 1)
        XCTAssertEqual(reloaded.notificationDeliveryByOutcome[.acceptedThenAbsent], 2)
        XCTAssertEqual(reloaded.notificationsRequested, 3)
        XCTAssertEqual(reloaded.notificationsThatLanded, 1)
    }

    func testWakeCountsAndDurationsSurviveTheDailyRoundTrip() {
        let (store, defaults) = makeStore()

        store.recordWake(.regionEntry, durationMilliseconds: 400)
        store.recordWake(.regionEntry, durationMilliseconds: 600)
        store.recordWake(.significantChange, durationMilliseconds: 2_000)
        store.recordWakeFixOutcome(.fixUnavailable)

        let reloaded = AmbientCoverageStore(defaults: defaults).lastSevenDays()
        XCTAssertEqual(reloaded.wakes, 3)
        XCTAssertEqual(reloaded.wakesByCause[.regionEntry], 2)
        XCTAssertEqual(reloaded.averageWakeMilliseconds(for: .regionEntry), 500)
        XCTAssertEqual(reloaded.longestWakeMilliseconds, 2_000)
        XCTAssertEqual(reloaded.wakeFixOutcomes[.fixUnavailable], 1)
    }

    /// The counters this expansion added must not cost the ones already there. A single
    /// undecodable day empties the whole history, so this asserts they read back together.
    func testTheNewCountersDoNotDisplaceTheExistingOnes() {
        let (store, defaults) = makeStore()

        store.recordArrival(.resolved)
        store.recordArrival(.unresolved, source: .alreadyInside)
        store.recordNotificationDelivery(.neverRequested)
        store.recordWake(.regionEntry, durationMilliseconds: 120)

        let reloaded = AmbientCoverageStore(defaults: defaults).lastSevenDays()
        XCTAssertEqual(reloaded.arrivals, 2)
        XCTAssertEqual(reloaded.arrivalsSynthesised, 1)
        XCTAssertEqual(reloaded.arrivalsUnresolved, 1)
        XCTAssertEqual(reloaded.notificationDeliveryByOutcome[.neverRequested], 1)
        XCTAssertEqual(reloaded.wakes, 1)
    }

    /// Yesterday's counters and today's sum rather than replace each other, which is what makes a
    /// seven-day read-out of a new counter mean anything at all.
    func testCountersFromSeparateDaysAreSummed() {
        let (store, defaults) = makeStore()
        let today = Date()
        let yesterday = today.addingTimeInterval(-24 * 60 * 60)

        store.recordWake(.regionEntry, durationMilliseconds: 300, at: yesterday)
        store.recordWake(.regionEntry, durationMilliseconds: 500, at: today)

        let reloaded = AmbientCoverageStore(defaults: defaults).lastSevenDays(ending: today)
        XCTAssertEqual(reloaded.wakesByCause[.regionEntry], 2)
        XCTAssertEqual(reloaded.longestWakeMilliseconds, 500)
    }
}
