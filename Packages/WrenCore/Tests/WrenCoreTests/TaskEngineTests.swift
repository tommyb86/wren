import XCTest
@testable import WrenCore

final class TaskEngineTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Weekly on Tuesdays at 09:00, starting 2026-09-01.
    private func weekly() -> Schedule {
        Schedule(frequency: .weekly, anchorDate: date(2026, 9, 1))
    }

    // MARK: - Overdue

    func testNothingIsOverdueBeforeTheFirstOccurrence() {
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 8, 25),
            calendar: brisbane
        )

        XCTAssertTrue(state.overdue.isEmpty)
        XCTAssertEqual(state.nextDue, date(2026, 9, 1))
    }

    func testMissedOccurrencesAccumulateOldestFirst() {
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 9, 20, 12, 0),
            calendar: brisbane
        )

        XCTAssertEqual(state.overdue, [
            date(2026, 9, 1),
            date(2026, 9, 8),
            date(2026, 9, 15)
        ])
        XCTAssertEqual(state.nextDue, date(2026, 9, 22))
    }

    func testAnOccurrenceEarlierTodayIsAlreadyOverdue() {
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 9, 1, 10, 0), // an hour after the 09:00 due time
            calendar: brisbane
        )

        XCTAssertEqual(state.overdue, [date(2026, 9, 1)])
    }

    func testAnOccurrenceLaterTodayIsNotYetOverdue() {
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 9, 1, 7, 0), // two hours before it is due
            calendar: brisbane
        )

        XCTAssertTrue(state.overdue.isEmpty)
        XCTAssertEqual(state.nextDue, date(2026, 9, 1))
    }

    // MARK: - Completion is recorded against the due date

    /// The whole point of the design: ticking Monday's task on Wednesday must
    /// satisfy *Monday*, not Wednesday.
    func testCompletingLateStillSatisfiesTheOccurrenceItSettles() {
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [date(2026, 9, 1)], // recorded against the due date
            now: date(2026, 9, 3, 18, 0),          // ticked two days late
            calendar: brisbane
        )

        XCTAssertTrue(state.overdue.isEmpty, "the settled occurrence must not stay overdue")
        XCTAssertEqual(state.lastCompletedDue, date(2026, 9, 1))
    }

    func testCompletingOneOccurrenceLeavesTheOthersOverdue() {
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [date(2026, 9, 8)],
            now: date(2026, 9, 20, 12, 0),
            calendar: brisbane
        )

        XCTAssertEqual(state.overdue, [date(2026, 9, 1), date(2026, 9, 15)])
    }

    /// Recording against "now" instead of the due date would have made this fail:
    /// a completion stamped Wednesday matches no Tuesday occurrence.
    func testCompletionMatchesAtDayGranularity() {
        // Same day as the occurrence, different clock time — e.g. the schedule's
        // time was edited after the completion was recorded.
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [date(2026, 9, 1, 21, 30)],
            now: date(2026, 9, 2, 12, 0),
            calendar: brisbane
        )

        XCTAssertTrue(state.overdue.isEmpty, "history must survive a schedule time edit")
    }

    func testIsCompleteChecksASpecificOccurrence() {
        let completions = [date(2026, 9, 8, 20, 0)]

        XCTAssertTrue(TaskEngine.isComplete(occurrence: date(2026, 9, 8), completedDueDates: completions, calendar: brisbane))
        XCTAssertFalse(TaskEngine.isComplete(occurrence: date(2026, 9, 1), completedDueDates: completions, calendar: brisbane))
    }

    // MARK: - Which occurrence a tap settles

    func testDoneTapSettlesTheOldestOutstandingOccurrence() {
        let target = TaskEngine.occurrenceToComplete(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 9, 20, 12, 0),
            calendar: brisbane
        )

        XCTAssertEqual(target, date(2026, 9, 1), "a backlog drains oldest-first")
    }

    func testRepeatedDoneTapsDrainTheBacklog() {
        var completions: [Date] = []
        let now = date(2026, 9, 20, 12, 0)

        for _ in 0..<3 {
            guard let target = TaskEngine.occurrenceToComplete(
                schedule: weekly(),
                completedDueDates: completions,
                now: now,
                calendar: brisbane
            ) else { break }
            completions.append(target)
        }

        XCTAssertEqual(completions, [date(2026, 9, 1), date(2026, 9, 8), date(2026, 9, 15)])

        let state = TaskEngine.state(schedule: weekly(), completedDueDates: completions, now: now, calendar: brisbane)
        XCTAssertTrue(state.overdue.isEmpty)
    }

    func testDoneTapWithNothingOutstandingSettlesTheNextOccurrence() {
        // Ticking a task ahead of time — done early, before it is due.
        let target = TaskEngine.occurrenceToComplete(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 8, 30, 12, 0),
            calendar: brisbane
        )

        XCTAssertEqual(target, date(2026, 9, 1))
    }

    // MARK: - Lookback

    func testLookbackBoundsHowFarBackMissesAreCounted() {
        let unbounded = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 12, 1),
            lookbackDays: 60,
            calendar: brisbane
        )
        let tight = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 12, 1),
            lookbackDays: 14,
            calendar: brisbane
        )

        // Both ends of the window are inclusive, and 2026-12-01 is itself a
        // Tuesday due at 09:00 — so a 14-day lookback catches Nov 17, Nov 24
        // and Dec 1.
        XCTAssertEqual(tight.overdue, [
            date(2026, 11, 17),
            date(2026, 11, 24),
            date(2026, 12, 1)
        ])
        XCTAssertTrue(unbounded.overdue.count > tight.overdue.count)
        XCTAssertEqual(unbounded.nextDue, tight.nextDue, "lookback must not affect what is next")
    }

    func testZeroLookbackReportsNoHistory() {
        let state = TaskEngine.state(
            schedule: weekly(),
            completedDueDates: [],
            now: date(2026, 9, 20),
            lookbackDays: 0,
            calendar: brisbane
        )

        XCTAssertTrue(state.overdue.isEmpty)
    }

    // MARK: - Outstanding window

    func testOutstandingExcludesCompletedOccurrences() {
        let outstanding = TaskEngine.outstanding(
            schedule: weekly(),
            completedDueDates: [date(2026, 9, 8)],
            from: date(2026, 9, 1),
            to: date(2026, 9, 30),
            calendar: brisbane
        )

        XCTAssertEqual(outstanding, [
            date(2026, 9, 1),
            date(2026, 9, 15),
            date(2026, 9, 22),
            date(2026, 9, 29)
        ])
    }

    func testOutstandingIsEmptyWhenEverythingIsDone() {
        let all = ScheduleEngine.occurrences(
            weekly(),
            from: date(2026, 9, 1),
            to: date(2026, 9, 30),
            calendar: brisbane
        )

        XCTAssertTrue(
            TaskEngine.outstanding(
                schedule: weekly(),
                completedDueDates: all,
                from: date(2026, 9, 1),
                to: date(2026, 9, 30),
                calendar: brisbane
            ).isEmpty
        )
    }

    // MARK: - Ended schedules

    func testAnEndedScheduleHasNoNextDueButKeepsItsMisses() {
        let schedule = Schedule(
            frequency: .weekly,
            anchorDate: date(2026, 9, 1),
            endDate: date(2026, 9, 15, 23, 59)
        )

        let state = TaskEngine.state(
            schedule: schedule,
            completedDueDates: [date(2026, 9, 1)],
            now: date(2026, 9, 20),
            calendar: brisbane
        )

        XCTAssertNil(state.nextDue)
        XCTAssertEqual(state.overdue, [date(2026, 9, 8), date(2026, 9, 15)])
    }

    func testFullyCompletedEndedScheduleIsQuiet() {
        let schedule = Schedule(
            frequency: .weekly,
            anchorDate: date(2026, 9, 1),
            endDate: date(2026, 9, 8, 23, 59)
        )

        let state = TaskEngine.state(
            schedule: schedule,
            completedDueDates: [date(2026, 9, 1), date(2026, 9, 8)],
            now: date(2026, 9, 20),
            calendar: brisbane
        )

        XCTAssertNil(state.nextDue)
        XCTAssertTrue(state.overdue.isEmpty)
        XCTAssertEqual(state.lastCompletedDue, date(2026, 9, 8))
    }
}
