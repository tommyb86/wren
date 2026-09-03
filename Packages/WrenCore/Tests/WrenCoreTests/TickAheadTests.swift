import XCTest
@testable import WrenCore

/// Ticking a task before it is due is allowed. These pin down what that must
/// mean for the agenda and for the next tap, since the first build got it
/// wrong: the completion was recorded but the row stayed put.
final class TickAheadTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Wednesday 2026-09-02, mid-morning.
    private var now: Date { date(2026, 9, 2, 10, 0) }

    func testOccurrenceToCompleteSkipsAnOccurrenceAlreadyTickedAhead() {
        // Weekly on Tuesdays. The 1st is done, the 8th was ticked early.
        let schedule = Schedule(frequency: .weekly, anchorDate: date(2026, 9, 1))
        let next = TaskEngine.occurrenceToComplete(
            schedule: schedule,
            completedDueDates: [date(2026, 9, 1), date(2026, 9, 8)],
            now: now,
            calendar: brisbane
        )
        XCTAssertEqual(next, date(2026, 9, 15))
    }

    func testOverdueStillWinsOverTickingAhead() {
        let schedule = Schedule(frequency: .weekly, anchorDate: date(2026, 9, 1))
        let next = TaskEngine.occurrenceToComplete(
            schedule: schedule,
            completedDueDates: [date(2026, 9, 8)],
            now: now,
            calendar: brisbane
        )
        XCTAssertEqual(next, date(2026, 9, 1))
    }

    func testATaskTickedForTomorrowLeavesTheAgenda() {
        let task = TaskSpec(
            id: UUID(),
            schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 3, 11, 30)),
            completedDueDates: [date(2026, 9, 3, 11, 30)]
        )
        let agenda = TodayAgenda.build(bins: [], tasks: [task], bills: [], payments: [], now: now, calendar: brisbane)
        XCTAssertTrue(agenda.tomorrow.isEmpty)
        XCTAssertTrue(agenda.isEmpty, "the following week is past the horizon")
    }

    func testADailyTaskTickedForTomorrowShowsTheDayAfter() {
        let task = TaskSpec(
            id: UUID(),
            schedule: Schedule(frequency: .daily, anchorDate: date(2026, 9, 3, 7, 0)),
            completedDueDates: [date(2026, 9, 3, 7, 0)]
        )
        let agenda = TodayAgenda.build(bins: [], tasks: [task], bills: [], payments: [], now: now, calendar: brisbane)
        XCTAssertTrue(agenda.tomorrow.isEmpty)
        XCTAssertEqual(agenda.laterThisWeek.first?.date, date(2026, 9, 4, 7, 0))
        XCTAssertEqual(agenda.laterThisWeek.count, 1, "only the next outstanding occurrence is shown")
    }
}
