import XCTest
@testable import CardCopilotStore

final class PatronagePolicyTests: XCTestCase {
    /// Fixed zone so a day boundary is a day boundary regardless of where the test runs.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }()

    private let now = Date(timeIntervalSince1970: 1_787_000_000)  // 2026-08-27ish

    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    private func keys(_ dates: [Date]) -> Set<String> {
        Set(dates.map { patronageDayKey(for: $0, calendar: calendar) })
    }

    // MARK: - The day key

    func testDayKeyIsAnIsoCalendarDay() {
        XCTAssertEqual(patronageDayKey(for: now, calendar: calendar).count, 10)
        XCTAssertEqual(patronageDayKey(for: now, calendar: calendar).filter { $0 == "-" }.count, 2)
    }

    /// Lexicographic order must agree with chronological order — the window filter is a string
    /// comparison, and it is only correct because zero-padded ISO days sort that way.
    func testDayKeysSortChronologically() {
        XCTAssertLessThan(patronageDayKey(for: daysAgo(40), calendar: calendar),
                          patronageDayKey(for: now, calendar: calendar))
    }

    // MARK: - The threshold

    func testThreeDistinctDaysInsideTheWindowQualifies() {
        let visits = keys([now, daysAgo(10), daysAgo(30)])
        XCTAssertTrue(isFrequented(visitDayKeys: visits, asOf: now, calendar: calendar))
    }

    func testTwoDistinctDaysDoesNotQualify() {
        let visits = keys([now, daysAgo(10)])
        XCTAssertFalse(isFrequented(visitDayKeys: visits, asOf: now, calendar: calendar))
    }

    /// The rule that separates this from counting captures. Three taps in one morning — a coffee,
    /// a refill, a sandwich — is one visit, and counting them as three would make the owner's
    /// most-interrupted store the one they buy small things at.
    func testThreeCapturesOnOneDayIsOneVisit() {
        let sameDay = [now, now.addingTimeInterval(600), now.addingTimeInterval(3_600)]
        XCTAssertFalse(isFrequented(visitDayKeys: keys(sameDay), asOf: now, calendar: calendar))
    }

    func testVisitsOlderThanTheWindowDoNotCount() {
        let visits = keys([now, daysAgo(10), daysAgo(120)])
        XCTAssertFalse(isFrequented(visitDayKeys: visits, asOf: now, calendar: calendar),
                       "the 120-day-old visit is outside the window, leaving only two")
    }

    /// A store the owner stopped going to must release its standing, not hold it forever.
    func testStandingLapsesOnceEveryVisitAgesOut() {
        let visits = keys([daysAgo(100), daysAgo(110), daysAgo(120)])
        XCTAssertFalse(isFrequented(visitDayKeys: visits, asOf: now, calendar: calendar))
        XCTAssertTrue(isFrequented(visitDayKeys: visits, asOf: daysAgo(95), calendar: calendar),
                      "the same three visits qualified while they were still inside the window")
    }

    /// Monthly cadence is the case the window exists for: a big-shop store visited once a month
    /// would never reach three visits in thirty days, and it is the highest-value store to catch.
    func testMonthlyCadenceQualifies() {
        let visits = keys([now, daysAgo(30), daysAgo(60)])
        XCTAssertTrue(isFrequented(visitDayKeys: visits, asOf: now, calendar: calendar))
    }
}
