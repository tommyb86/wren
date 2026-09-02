import XCTest
@testable import WrenCore

final class ScheduleEngineTests: XCTestCase {

    // Brisbane has no DST — the right default for everything except the DST cases.
    private let brisbane = calendar(timeZone: "Australia/Brisbane")
    // Sydney does, and is the realistic worst case for an Australian user.
    private let sydney = calendar(timeZone: "Australia/Sydney")

    private static func calendar(timeZone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZone)!
        c.firstWeekday = 1 // Sunday, matching Calendar's weekday numbering
        return c
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Weekly

    func testWeeklyStepsSevenDaysFromAnchor() {
        let anchor = date(2026, 9, 1, 19, 0, in: brisbane) // Tuesday
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor)

        let dates = ScheduleEngine.occurrences(
            schedule,
            from: anchor,
            to: date(2026, 9, 30, in: brisbane),
            calendar: brisbane
        )

        XCTAssertEqual(dates, [
            date(2026, 9, 1, 19, 0, in: brisbane),
            date(2026, 9, 8, 19, 0, in: brisbane),
            date(2026, 9, 15, 19, 0, in: brisbane),
            date(2026, 9, 22, 19, 0, in: brisbane),
            date(2026, 9, 29, 19, 0, in: brisbane)
        ])
    }

    func testAnchorIsItselfAnOccurrence() {
        let anchor = date(2026, 9, 1, 19, 0, in: brisbane)
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor)

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: anchor, limit: 1, calendar: brisbane),
            [anchor]
        )
    }

    func testNothingIsEmittedBeforeTheAnchor() {
        let anchor = date(2026, 9, 15, 19, 0, in: brisbane)
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor)

        let dates = ScheduleEngine.occurrences(
            schedule,
            from: date(2026, 8, 1, in: brisbane),
            to: date(2026, 9, 20, in: brisbane),
            calendar: brisbane
        )

        XCTAssertEqual(dates, [anchor])
    }

    func testWeeklyWithExplicitWeekdaysEmitsEachDay() {
        // Anchored Monday, collecting Tuesday and Friday.
        let anchor = date(2026, 9, 7, 6, 30, in: brisbane)
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor, weekdays: [3, 6])

        let dates = ScheduleEngine.occurrences(
            schedule,
            from: anchor,
            to: date(2026, 9, 20, in: brisbane),
            calendar: brisbane
        )

        XCTAssertEqual(dates, [
            date(2026, 9, 8, 6, 30, in: brisbane),  // Tue
            date(2026, 9, 11, 6, 30, in: brisbane), // Fri
            date(2026, 9, 15, 6, 30, in: brisbane), // Tue
            date(2026, 9, 18, 6, 30, in: brisbane)  // Fri
        ])
    }

    func testWeekdaysEarlierInTheAnchorWeekAreSkipped() {
        // Anchored Wednesday but collecting Monday: the first occurrence is the
        // *following* Monday, not the one two days before the anchor.
        let anchor = date(2026, 9, 9, 6, 30, in: brisbane) // Wednesday
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor, weekdays: [2])

        XCTAssertEqual(
            ScheduleEngine.next(schedule, after: anchor, calendar: brisbane),
            date(2026, 9, 14, 6, 30, in: brisbane)
        )
    }

    // MARK: - Fortnightly, including the alternating case

    func testFortnightlyStepsFourteenDays() {
        let anchor = date(2026, 9, 1, 19, 0, in: brisbane)
        let schedule = Schedule(frequency: .weekly, interval: 2, anchorDate: anchor)

        let dates = ScheduleEngine.occurrences(schedule, from: anchor, limit: 4, calendar: brisbane)

        XCTAssertEqual(dates, [
            date(2026, 9, 1, 19, 0, in: brisbane),
            date(2026, 9, 15, 19, 0, in: brisbane),
            date(2026, 9, 29, 19, 0, in: brisbane),
            date(2026, 10, 13, 19, 0, in: brisbane)
        ])
    }

    /// The QLD council case the plan calls out: general waste weekly, recycling
    /// and green waste fortnightly on the same night, alternating with each other.
    /// Two fortnightly schedules anchored a week apart — no special support needed.
    func testAlternatingFortnightlyBinsNeverCollide() {
        let recycling = Schedule(
            frequency: .weekly, interval: 2,
            anchorDate: date(2026, 9, 1, 19, 0, in: brisbane)
        )
        let greenWaste = Schedule(
            frequency: .weekly, interval: 2,
            anchorDate: date(2026, 9, 8, 19, 0, in: brisbane)
        )

        let window = (from: date(2026, 9, 1, in: brisbane), to: date(2026, 10, 31, in: brisbane))
        let recyclingDates = ScheduleEngine.occurrences(recycling, from: window.from, to: window.to, calendar: brisbane)
        let greenDates = ScheduleEngine.occurrences(greenWaste, from: window.from, to: window.to, calendar: brisbane)

        XCTAssertEqual(recyclingDates, [
            date(2026, 9, 1, 19, 0, in: brisbane),
            date(2026, 9, 15, 19, 0, in: brisbane),
            date(2026, 9, 29, 19, 0, in: brisbane),
            date(2026, 10, 13, 19, 0, in: brisbane),
            date(2026, 10, 27, 19, 0, in: brisbane)
        ])
        XCTAssertEqual(greenDates, [
            date(2026, 9, 8, 19, 0, in: brisbane),
            date(2026, 9, 22, 19, 0, in: brisbane),
            date(2026, 10, 6, 19, 0, in: brisbane),
            date(2026, 10, 20, 19, 0, in: brisbane)
        ])
        XCTAssertTrue(Set(recyclingDates).isDisjoint(with: Set(greenDates)), "alternating bins must never share a night")
    }

    // MARK: - Monthly, including short months

    func testMonthlyOnThe31stClampsToShortMonthsWithoutDrifting() {
        // The drift trap: stepping month-by-month from the previous occurrence
        // would give Feb 28 -> Mar 28. Computing from the anchor gives Mar 31.
        let anchor = date(2026, 1, 31, 9, 0, in: brisbane)
        let schedule = Schedule(frequency: .monthly, anchorDate: anchor)

        let dates = ScheduleEngine.occurrences(schedule, from: anchor, limit: 6, calendar: brisbane)

        XCTAssertEqual(dates, [
            date(2026, 1, 31, 9, 0, in: brisbane),
            date(2026, 2, 28, 9, 0, in: brisbane), // clamped — 2026 is not a leap year
            date(2026, 3, 31, 9, 0, in: brisbane), // back to the 31st, no drift
            date(2026, 4, 30, 9, 0, in: brisbane), // clamped
            date(2026, 5, 31, 9, 0, in: brisbane),
            date(2026, 6, 30, 9, 0, in: brisbane)
        ])
    }

    func testMonthlyOnThe29thClampsInNonLeapFebruary() {
        let anchor = date(2026, 1, 29, 9, 0, in: brisbane)
        let schedule = Schedule(frequency: .monthly, anchorDate: anchor)

        XCTAssertEqual(
            ScheduleEngine.next(schedule, after: anchor, calendar: brisbane),
            date(2026, 2, 28, 9, 0, in: brisbane)
        )
    }

    func testQuarterlyIsMonthlyWithIntervalThree() {
        let anchor = date(2026, 1, 15, 9, 0, in: brisbane)
        let schedule = Schedule(frequency: .monthly, interval: 3, anchorDate: anchor)

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: anchor, limit: 4, calendar: brisbane),
            [
                date(2026, 1, 15, 9, 0, in: brisbane),
                date(2026, 4, 15, 9, 0, in: brisbane),
                date(2026, 7, 15, 9, 0, in: brisbane),
                date(2026, 10, 15, 9, 0, in: brisbane)
            ]
        )
    }

    // MARK: - Yearly

    func testYearly() {
        let anchor = date(2026, 3, 20, 9, 0, in: brisbane) // car rego
        let schedule = Schedule(frequency: .yearly, anchorDate: anchor)

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: anchor, limit: 3, calendar: brisbane),
            [
                date(2026, 3, 20, 9, 0, in: brisbane),
                date(2027, 3, 20, 9, 0, in: brisbane),
                date(2028, 3, 20, 9, 0, in: brisbane)
            ]
        )
    }

    func testYearlyOnFeb29ClampsInNonLeapYears() {
        let anchor = date(2028, 2, 29, 9, 0, in: brisbane) // 2028 is a leap year
        let schedule = Schedule(frequency: .yearly, anchorDate: anchor)

        XCTAssertEqual(
            ScheduleEngine.next(schedule, after: anchor, calendar: brisbane),
            date(2029, 2, 28, 9, 0, in: brisbane)
        )
    }

    // MARK: - Daily

    func testDailyWithInterval() {
        let anchor = date(2026, 9, 1, 7, 0, in: brisbane)
        let schedule = Schedule(frequency: .daily, interval: 3, anchorDate: anchor)

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: anchor, limit: 3, calendar: brisbane),
            [
                date(2026, 9, 1, 7, 0, in: brisbane),
                date(2026, 9, 4, 7, 0, in: brisbane),
                date(2026, 9, 7, 7, 0, in: brisbane)
            ]
        )
    }

    // MARK: - DST

    /// Sydney springs forward on 2026-10-04. A bin put out at 19:00 must stay at
    /// 19:00 wall-clock afterwards — the elapsed seconds between occurrences is
    /// *not* a constant week, which is exactly why the engine never adds seconds.
    func testWeeklySurvivesSpringForwardAtConstantWallClockTime() {
        let anchor = date(2026, 9, 30, 19, 0, in: sydney) // Wednesday, before the change
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor)

        let dates = ScheduleEngine.occurrences(schedule, from: anchor, limit: 4, calendar: sydney)

        XCTAssertEqual(dates.count, 4)
        for occurrence in dates {
            XCTAssertEqual(sydney.component(.hour, from: occurrence), 19, "wall-clock hour drifted across DST")
            XCTAssertEqual(sydney.component(.minute, from: occurrence), 0)
        }

        // Proof the naive implementation would have failed: the gap across the
        // transition is an hour short of seven days.
        let gap = dates[1].timeIntervalSince(dates[0])
        XCTAssertEqual(gap, 7 * 24 * 3600 - 3600, accuracy: 1)
    }

    func testWeeklyWithWeekdaysSurvivesFallBackAtConstantWallClockTime() {
        // Sydney falls back on 2026-04-05.
        let anchor = date(2026, 3, 25, 6, 30, in: sydney)
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor, weekdays: [3]) // Tuesdays

        let dates = ScheduleEngine.occurrences(schedule, from: anchor, limit: 4, calendar: sydney)

        XCTAssertEqual(dates.count, 4)
        for occurrence in dates {
            XCTAssertEqual(sydney.component(.hour, from: occurrence), 6, "wall-clock hour drifted across DST")
            XCTAssertEqual(sydney.component(.weekday, from: occurrence), 3, "landed on the wrong weekday")
        }
    }

    func testMonthlySurvivesDSTBoundary() {
        let anchor = date(2026, 9, 15, 19, 0, in: sydney)
        let schedule = Schedule(frequency: .monthly, anchorDate: anchor)

        let dates = ScheduleEngine.occurrences(schedule, from: anchor, limit: 3, calendar: sydney)

        for occurrence in dates {
            XCTAssertEqual(sydney.component(.hour, from: occurrence), 19)
            XCTAssertEqual(sydney.component(.day, from: occurrence), 15)
        }
    }

    // MARK: - End date

    func testEndDateIsInclusiveAndCutsTheSeriesOff() {
        let anchor = date(2026, 9, 1, 19, 0, in: brisbane)
        let schedule = Schedule(
            frequency: .weekly,
            anchorDate: anchor,
            endDate: date(2026, 9, 15, 19, 0, in: brisbane)
        )

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: anchor, to: date(2026, 12, 31, in: brisbane), calendar: brisbane),
            [
                date(2026, 9, 1, 19, 0, in: brisbane),
                date(2026, 9, 8, 19, 0, in: brisbane),
                date(2026, 9, 15, 19, 0, in: brisbane) // inclusive
            ]
        )
    }

    func testEndDateAlsoBoundsTheLimitVariant() {
        let anchor = date(2026, 9, 1, 19, 0, in: brisbane)
        let schedule = Schedule(
            frequency: .weekly,
            anchorDate: anchor,
            endDate: date(2026, 9, 10, in: brisbane)
        )

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: anchor, limit: 50, calendar: brisbane).count,
            2,
            "limit must not run past the end date"
        )
    }

    func testNextReturnsNilPastTheEndDate() {
        let anchor = date(2026, 9, 1, 19, 0, in: brisbane)
        let schedule = Schedule(
            frequency: .weekly,
            anchorDate: anchor,
            endDate: date(2026, 9, 8, 19, 0, in: brisbane)
        )

        XCTAssertEqual(
            ScheduleEngine.next(schedule, after: anchor, calendar: brisbane),
            date(2026, 9, 8, 19, 0, in: brisbane)
        )
        XCTAssertNil(
            ScheduleEngine.next(schedule, after: date(2026, 9, 8, 19, 0, in: brisbane), calendar: brisbane)
        )
    }

    func testNextReturnsNilPastEndDateForWeekdaySchedules() {
        let anchor = date(2026, 9, 7, 6, 30, in: brisbane)
        let schedule = Schedule(
            frequency: .weekly,
            anchorDate: anchor,
            weekdays: [3, 6],
            endDate: date(2026, 9, 12, in: brisbane)
        )

        XCTAssertNil(
            ScheduleEngine.next(schedule, after: date(2026, 9, 11, 7, 0, in: brisbane), calendar: brisbane)
        )
    }

    // MARK: - Far-anchored schedules

    /// A bin schedule set up years ago must not need thousands of iterations to
    /// answer "what's next" — the start-index estimate handles the skip.
    func testDistantAnchorStillResolvesCorrectly() {
        let anchor = date(2015, 1, 6, 19, 0, in: brisbane) // Tuesday
        let schedule = Schedule(frequency: .weekly, interval: 2, anchorDate: anchor)

        let next = ScheduleEngine.next(
            schedule,
            after: date(2026, 9, 2, 12, 0, in: brisbane),
            calendar: brisbane
        )

        XCTAssertNotNil(next)
        XCTAssertEqual(brisbane.component(.weekday, from: next!), 3, "must stay on the anchor's weekday")
        XCTAssertEqual(brisbane.component(.hour, from: next!), 19)
        // Every occurrence is an exact multiple of 14 days from the anchor.
        let days = brisbane.dateComponents([.day], from: anchor, to: next!).day!
        XCTAssertEqual(days % 14, 0, "drifted off the fortnightly cadence")
    }

    // MARK: - Degenerate input

    func testInvalidIntervalIsTreatedAsOne() {
        let anchor = date(2026, 9, 1, 19, 0, in: brisbane)
        var schedule = Schedule(frequency: .weekly, anchorDate: anchor)
        schedule.interval = 0 // bypasses init's clamp

        XCTAssertEqual(
            ScheduleEngine.next(schedule, after: anchor, calendar: brisbane),
            date(2026, 9, 8, 19, 0, in: brisbane)
        )
    }

    func testInvertedRangeYieldsNothing() {
        let anchor = date(2026, 9, 1, in: brisbane)
        let schedule = Schedule(frequency: .weekly, anchorDate: anchor)

        XCTAssertTrue(
            ScheduleEngine.occurrences(
                schedule,
                from: date(2026, 9, 30, in: brisbane),
                to: date(2026, 9, 1, in: brisbane),
                calendar: brisbane
            ).isEmpty
        )
    }

    func testZeroLimitYieldsNothing() {
        let schedule = Schedule(frequency: .weekly, anchorDate: date(2026, 9, 1, in: brisbane))
        XCTAssertTrue(ScheduleEngine.occurrences(schedule, from: date(2026, 9, 1, in: brisbane), limit: 0, calendar: brisbane).isEmpty)
    }

    // MARK: - Round-tripping

    func testScheduleSurvivesEncodingRoundTrip() throws {
        let schedule = Schedule(
            frequency: .weekly,
            interval: 2,
            anchorDate: date(2026, 9, 1, 19, 0, in: brisbane),
            weekdays: [3, 6],
            endDate: date(2027, 1, 1, in: brisbane)
        )

        XCTAssertEqual(try Schedule.decoded(from: try schedule.encoded()), schedule)
    }

    func testLenientDecodingOfGarbageReturnsNil() {
        XCTAssertNil(Schedule.lenientlyDecoded(from: Data("not a schedule".utf8)))
    }
}
