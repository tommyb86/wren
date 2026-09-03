import XCTest
@testable import WrenCore

/// A `.once` schedule turns a recurring task into a plain reminder. It runs
/// through every existing consumer rather than being special-cased, so these
/// tests walk the whole chain: engine, task state, agenda, normalisation.
final class OneOffScheduleTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func onceOn(_ date: Date) -> Schedule {
        Schedule(frequency: .once, anchorDate: date)
    }

    // MARK: - Engine

    func testOneOffYieldsExactlyOneOccurrence() {
        let fires = date(2026, 9, 10, 17, 30)
        let schedule = onceOn(fires)

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: date(2026, 1, 1), to: date(2027, 12, 31), calendar: brisbane),
            [fires]
        )
    }

    func testOneOffIgnoresALargeLimit() {
        let fires = date(2026, 9, 10, 17, 30)

        XCTAssertEqual(
            ScheduleEngine.occurrences(onceOn(fires), from: date(2026, 1, 1), limit: 50, calendar: brisbane),
            [fires]
        )
    }

    func testNextFindsTheOccurrenceThenNothing() {
        let fires = date(2026, 9, 10, 17, 30)
        let schedule = onceOn(fires)

        XCTAssertEqual(ScheduleEngine.next(schedule, after: date(2026, 9, 1), calendar: brisbane), fires)
        XCTAssertNil(
            ScheduleEngine.next(schedule, after: fires, calendar: brisbane),
            "a reminder does not come round again"
        )
    }

    func testOneOffOutsideTheWindowIsNotEmitted() {
        let fires = date(2026, 9, 10, 17, 30)

        XCTAssertTrue(
            ScheduleEngine.occurrences(onceOn(fires), from: date(2026, 10, 1), to: date(2026, 12, 31), calendar: brisbane).isEmpty
        )
    }

    /// The interval field is meaningless here, and a stale value must not
    /// multiply the occurrence.
    func testIntervalIsIgnored() {
        var schedule = onceOn(date(2026, 9, 10, 17, 30))
        schedule.interval = 3

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: date(2026, 1, 1), to: date(2027, 12, 31), calendar: brisbane).count,
            1
        )
    }

    func testWeekdaysAreIgnored() {
        var schedule = onceOn(date(2026, 9, 10, 17, 30))
        schedule.weekdays = [2, 4, 6]

        XCTAssertEqual(
            ScheduleEngine.occurrences(schedule, from: date(2026, 1, 1), to: date(2027, 12, 31), calendar: brisbane),
            [date(2026, 9, 10, 17, 30)]
        )
    }

    func testAnEndDateBeforeTheOccurrenceSuppressesIt() {
        var schedule = onceOn(date(2026, 9, 10, 17, 30))
        schedule.endDate = date(2026, 9, 1)

        XCTAssertTrue(
            ScheduleEngine.occurrences(schedule, from: date(2026, 1, 1), to: date(2027, 12, 31), calendar: brisbane).isEmpty
        )
    }

    // MARK: - Description

    func testSummaryAndCadenceReadAsOneOff() {
        let schedule = onceOn(date(2026, 9, 10, 17, 30))

        XCTAssertEqual(schedule.summary(calendar: brisbane), "Once")
        XCTAssertEqual(BillingPeriod.cadenceDescription(schedule), "one-off")
    }

    func testSummaryDoesNotAppendWeekdays() {
        var schedule = onceOn(date(2026, 9, 10, 17, 30))
        schedule.weekdays = [3]

        XCTAssertEqual(schedule.summary(calendar: brisbane), "Once", "there is no weekly pattern to describe")
    }

    // MARK: - Normalisation

    /// A one-off is not a rate, so it must not inflate the monthly commitment —
    /// that figure answers "what does the household cost per month, ongoing".
    func testAOneOffContributesNothingToTheMonthlyCommitment() {
        let schedule = onceOn(date(2026, 9, 10))

        XCTAssertEqual(BillingPeriod.occurrencesPerYear(schedule), 0, accuracy: 0.0001)
        XCTAssertEqual(BillingPeriod.monthlyEquivalentCents(amountCents: 50_000, schedule: schedule), 0)
        XCTAssertEqual(BillingPeriod.annualCents(amountCents: 50_000, schedule: schedule), 0)
    }

    /// But it still lands in the forecast, because that asks the engine for real
    /// dated occurrences rather than using the rate.
    func testAOneOffStillAppearsInTheForecastMonthItFallsIn() {
        let bill = BillSpec(
            id: UUID(),
            name: "Council excess rubbish collection",
            amountCents: 50_000,
            schedule: onceOn(date(2026, 10, 15))
        )

        let forecast = BillReports.forecast(bills: [bill], from: date(2026, 9, 1), months: 12, calendar: brisbane)
        let october = forecast.first { brisbane.component(.month, from: $0.monthStart) == 10 }
        let november = forecast.first { brisbane.component(.month, from: $0.monthStart) == 11 }

        XCTAssertEqual(october?.totalCents, 50_000)
        XCTAssertEqual(november?.totalCents, 0)
        XCTAssertEqual(BillReports.monthlyCommitmentCents([bill]), 0, "still not an ongoing commitment")
    }

    // MARK: - As a task reminder

    func testAPendingReminderIsNextDueAndNotOverdue() {
        let state = TaskEngine.state(
            schedule: onceOn(date(2026, 9, 10, 17, 30)),
            completedDueDates: [],
            now: date(2026, 9, 3, 10, 0),
            calendar: brisbane
        )

        XCTAssertEqual(state.nextDue, date(2026, 9, 10, 17, 30))
        XCTAssertTrue(state.overdue.isEmpty)
    }

    func testAMissedReminderGoesOverdueOnce() {
        let state = TaskEngine.state(
            schedule: onceOn(date(2026, 9, 10, 17, 30)),
            completedDueDates: [],
            now: date(2026, 9, 15, 10, 0),
            calendar: brisbane
        )

        XCTAssertEqual(state.overdue, [date(2026, 9, 10, 17, 30)])
        XCTAssertNil(state.nextDue, "nothing further to come")
    }

    /// The whole point: once done, a reminder is finished — no overdue entries,
    /// nothing next, and it stops asking.
    func testACompletedReminderGoesQuietForever() {
        let fires = date(2026, 9, 10, 17, 30)
        let state = TaskEngine.state(
            schedule: onceOn(fires),
            completedDueDates: [fires],
            now: date(2026, 12, 25, 10, 0),
            calendar: brisbane
        )

        XCTAssertTrue(state.overdue.isEmpty)
        XCTAssertNil(state.nextDue)
        XCTAssertEqual(state.lastCompletedDue, fires)
    }

    func testTickingAReminderSettlesItsOnlyOccurrence() {
        let fires = date(2026, 9, 10, 17, 30)

        XCTAssertEqual(
            TaskEngine.occurrenceToComplete(
                schedule: onceOn(fires),
                completedDueDates: [],
                now: date(2026, 9, 3, 10, 0),
                calendar: brisbane
            ),
            fires
        )
    }

    // MARK: - On the agenda

    func testAReminderDueTodayAppearsOnTheAgenda() {
        let taskID = UUID()
        let agenda = TodayAgenda.build(
            bins: [],
            tasks: [TaskSpec(id: taskID, schedule: onceOn(date(2026, 9, 3, 17, 30)))],
            bills: [],
            payments: [],
            now: date(2026, 9, 3, 10, 0),
            calendar: brisbane
        )

        XCTAssertEqual(agenda.today.map(\.sourceID), [taskID])
        XCTAssertEqual(agenda.actionableCount, 1)
    }

    func testACompletedReminderLeavesTheAgenda() {
        let fires = date(2026, 9, 3, 17, 30)
        let agenda = TodayAgenda.build(
            bins: [],
            tasks: [TaskSpec(id: UUID(), schedule: onceOn(fires), completedDueDates: [fires])],
            bills: [],
            payments: [],
            now: date(2026, 9, 3, 18, 0),
            calendar: brisbane
        )

        XCTAssertTrue(agenda.isEmpty)
    }

    func testAMissedReminderShowsAsOverdueOnTheAgenda() {
        let agenda = TodayAgenda.build(
            bins: [],
            tasks: [TaskSpec(id: UUID(), schedule: onceOn(date(2026, 8, 30, 17, 30)))],
            bills: [],
            payments: [],
            now: date(2026, 9, 3, 10, 0),
            calendar: brisbane
        )

        XCTAssertEqual(agenda.overdue.count, 1)
        XCTAssertEqual(agenda.overdue.first?.status, .overdue(days: 4))
    }

    // MARK: - Round-tripping

    func testOnceSurvivesEncoding() throws {
        let schedule = onceOn(date(2026, 9, 10, 17, 30))

        XCTAssertEqual(try Schedule.decoded(from: try schedule.encoded()), schedule)
    }
}
