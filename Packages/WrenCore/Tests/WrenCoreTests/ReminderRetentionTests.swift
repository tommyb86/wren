import XCTest
@testable import WrenCore

/// A ticked reminder is deleted a week later. These pin the boundary, because
/// the rule destroys data and an off-by-one would take something a day early.
final class ReminderRetentionTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func expired(completed: Date, now: Date) -> Bool {
        TaskEngine.settledReminderHasExpired(completedAt: completed, now: now, calendar: brisbane)
    }

    func testRetentionIsSevenDays() {
        XCTAssertEqual(TaskEngine.settledReminderRetentionDays, 7)
    }

    func testKeptForTheFirstWeek() {
        let ticked = date(2026, 9, 1)
        XCTAssertFalse(expired(completed: ticked, now: date(2026, 9, 1)))
        XCTAssertFalse(expired(completed: ticked, now: date(2026, 9, 5)))
        XCTAssertFalse(expired(completed: ticked, now: date(2026, 9, 7, 23, 59)), "six whole days later is still inside the week")
    }

    func testGoesOnTheSeventhDay() {
        XCTAssertTrue(expired(completed: date(2026, 9, 1), now: date(2026, 9, 8)))
        XCTAssertTrue(expired(completed: date(2026, 9, 1), now: date(2026, 9, 30)))
    }

    /// Whole days, so ticking at 11pm and checking at 1am the next day is one
    /// day apart — not a fraction that rounds unpredictably.
    func testCountsWholeDaysNotElapsedTime() {
        let lateTick = date(2026, 9, 1, 23, 30)
        XCTAssertFalse(expired(completed: lateTick, now: date(2026, 9, 8, 0, 30)) == false,
                       "seven calendar days have passed even though it is barely 7 x 24 hours")
        XCTAssertFalse(expired(completed: lateTick, now: date(2026, 9, 7, 0, 30)))
    }

    /// A clock that has gone backwards must never delete anything.
    func testFutureCompletionIsNeverExpired() {
        XCTAssertFalse(expired(completed: date(2026, 9, 20), now: date(2026, 9, 1)))
    }
}
