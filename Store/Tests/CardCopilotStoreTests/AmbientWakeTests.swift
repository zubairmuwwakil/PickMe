import XCTest
@testable import CardCopilotStore

/// What ambient monitoring actually costs, counted.
///
/// The only item in this instrument that speaks to whether background monitoring is affordable at
/// all. A battery cost discovered in week one is a design input; the same cost discovered after
/// launch is a review.
final class AmbientWakeTests: XCTestCase {

    /// Four causes, counted apart. They are not interchangeable: a region entry is the app doing
    /// its job, and a significant-change wake that only ever re-aims geofences is overhead.
    func testWakesAreCountedByCause() {
        var log = AmbientCoverageLog()
        log.recordWake(.regionEntry, durationMilliseconds: 400)
        log.recordWake(.regionEntry, durationMilliseconds: 600)
        log.recordWake(.regionExit, durationMilliseconds: 50)
        log.recordWake(.significantChange, durationMilliseconds: 2_000)
        log.recordWake(.stateSynthesis, durationMilliseconds: 900)

        XCTAssertEqual(log.wakesByCause[.regionEntry], 2)
        XCTAssertEqual(log.wakesByCause[.regionExit], 1)
        XCTAssertEqual(log.wakesByCause[.significantChange], 1)
        XCTAssertEqual(log.wakesByCause[.stateSynthesis], 1)
        XCTAssertEqual(log.wakes, 5)
    }

    /// Wall-clock time awake, summed per cause rather than listed per wake. A list of wake
    /// durations with the days they fell on is a movement trace; a daily total is a battery bill.
    func testWakeDurationIsSummedByCauseAndTheLongestIsKept() {
        var log = AmbientCoverageLog()
        log.recordWake(.regionEntry, durationMilliseconds: 400)
        log.recordWake(.regionEntry, durationMilliseconds: 600)
        log.recordWake(.significantChange, durationMilliseconds: 2_000)

        XCTAssertEqual(log.wakeMillisecondsByCause[.regionEntry], 1_000)
        XCTAssertEqual(log.averageWakeMilliseconds(for: .regionEntry), 500)
        XCTAssertEqual(log.longestWakeMilliseconds, 2_000)
        XCTAssertEqual(log.totalWakeMilliseconds, 3_000)
    }

    /// A negative duration is a clock artefact, not a wake that ran backwards. Letting it through
    /// would drag the daily total below what was actually spent.
    func testANegativeDurationIsClampedToZero() {
        var log = AmbientCoverageLog()
        log.recordWake(.regionEntry, durationMilliseconds: -5)

        XCTAssertEqual(log.wakeMillisecondsByCause[.regionEntry], 0)
        XCTAssertEqual(log.wakes, 1)
    }

    func testAverageIsAbsentForACauseThatNeverWoke() {
        XCTAssertNil(AmbientCoverageLog().averageWakeMilliseconds(for: .regionExit))
    }

    /// A wake that spent its whole window waiting for a fix that never came is the expensive kind,
    /// and a wake that never asked for one is nearly free. Pooling them would hide which sort the
    /// battery is going on.
    func testFixOutcomesAreCountedApartFromEachOther() {
        var log = AmbientCoverageLog()
        log.recordWakeFixOutcome(.fixLanded)
        log.recordWakeFixOutcome(.fixUnavailable)
        log.recordWakeFixOutcome(.fixUnavailable)
        log.recordWakeFixOutcome(.notRequested)

        XCTAssertEqual(log.wakeFixOutcomes[.fixLanded], 1)
        XCTAssertEqual(log.wakeFixOutcomes[.fixUnavailable], 2)
        XCTAssertEqual(log.wakeFixOutcomes[.notRequested], 1)
    }

    func testWakeCountsSumOverTheWeek() {
        var week = AmbientCoverageLog()
        var today = AmbientCoverageLog()
        today.recordWake(.regionEntry, durationMilliseconds: 400)
        today.recordWakeFixOutcome(.fixLanded)
        week.merge(today)
        week.merge(today)

        XCTAssertEqual(week.wakesByCause[.regionEntry], 2)
        XCTAssertEqual(week.wakeMillisecondsByCause[.regionEntry], 800)
        XCTAssertEqual(week.wakeFixOutcomes[.fixLanded], 2)
    }

    /// The longest wake of the week is the longest of any day in it, not the sum of the daily
    /// maxima — which would report a wake nobody ever had.
    func testTheLongestWakeAcrossTheWeekIsAMaximumNotASum() {
        var week = AmbientCoverageLog()
        var monday = AmbientCoverageLog()
        monday.recordWake(.regionEntry, durationMilliseconds: 400)
        var tuesday = AmbientCoverageLog()
        tuesday.recordWake(.significantChange, durationMilliseconds: 3_000)
        week.merge(monday)
        week.merge(tuesday)

        XCTAssertEqual(week.longestWakeMilliseconds, 3_000)
    }

    /// Persisted per day, so a day written before these counters existed must still decode.
    /// `DailyLogStore` reads a throw as an empty history and would delete the week this is meant
    /// to be compared against.
    func testADayRecordedBeforeTheWakeCountersExistedStillDecodes() throws {
        let legacy = """
        {"rotations":4,"rotationsAtCapacity":1,"evictedByTier":[],
         "arrivals":6,"arrivalsUnresolved":0,"arrivalsNotAdvised":0,"arrivalsSynthesised":0}
        """
        let decoded = try JSONDecoder().decode(AmbientCoverageLog.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.arrivals, 6)
        XCTAssertEqual(decoded.wakes, 0)
        XCTAssertTrue(decoded.wakesByCause.isEmpty)
        XCTAssertTrue(decoded.wakeFixOutcomes.isEmpty)
        XCTAssertEqual(decoded.longestWakeMilliseconds, 0)
    }
}
