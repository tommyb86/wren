import XCTest
@testable import WrenCore

final class TodayAgendaTests: XCTestCase {

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

    private let binID = UUID()
    private let taskID = UUID()
    private let billID = UUID()

    /// General waste out Wednesday evening.
    private func bins() -> [BinSchedule] {
        [BinSchedule(id: binID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 2, 19, 0)))]
    }

    private func tasks(completed: [Date] = []) -> [TaskSpec] {
        [TaskSpec(
            id: taskID,
            schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 8, 19, 9, 0)),
            completedDueDates: completed
        )]
    }

    private func bills(paysAutomatically: Bool = false) -> [BillSpec] {
        [BillSpec(
            id: billID,
            name: "Internet",
            amountCents: 8_900,
            schedule: Schedule(frequency: .monthly, anchorDate: date(2026, 8, 28, 9, 0)),
            paysAutomatically: paysAutomatically
        )]
    }

    // MARK: - Unification

    func testAllThreeSourcesLandOnOneAgenda() {
        let agenda = TodayAgenda.build(
            bins: bins(),
            tasks: tasks(),
            bills: bills(),
            payments: [],
            now: now,
            calendar: brisbane
        )

        XCTAssertFalse(agenda.isEmpty)
        XCTAssertEqual(Set(agenda.allItems.map(\.kind)), [.bin, .task, .bill])
    }

    func testEmptyInputGivesAnEmptyAgenda() {
        let agenda = TodayAgenda.build(bins: [], tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertTrue(agenda.isEmpty)
        XCTAssertEqual(agenda.actionableCount, 0)
    }

    // MARK: - Buckets

    func testTonightsBinIsDueToday() {
        let agenda = TodayAgenda.build(bins: bins(), tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertEqual(agenda.today.map(\.kind), [.bin])
        XCTAssertEqual(agenda.today.first?.date, date(2026, 9, 2, 19, 0))
        XCTAssertTrue(agenda.overdue.isEmpty)
    }

    func testNextWeeksBinIsLaterThisWeekNotTomorrow() {
        let agenda = TodayAgenda.build(bins: bins(), tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        // Sep 9 is a week out, past the 7-day horizon counted from today.
        XCTAssertTrue(agenda.tomorrow.isEmpty)
        XCTAssertTrue(agenda.laterThisWeek.isEmpty, "a week and a day out is beyond the horizon")
    }

    func testItemDueTomorrowLandsInTomorrow() {
        let bin = [BinSchedule(id: binID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 3, 19, 0)))]

        let agenda = TodayAgenda.build(bins: bin, tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertEqual(agenda.tomorrow.map(\.kind), [.bin])
        XCTAssertTrue(agenda.today.isEmpty)
    }

    func testItemLaterInTheWeekIsUpcoming() {
        let bin = [BinSchedule(id: binID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 5, 19, 0)))]

        let agenda = TodayAgenda.build(bins: bin, tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertEqual(agenda.laterThisWeek.map(\.kind), [.bin])
    }

    // MARK: - Bins never go overdue

    /// A collection earlier today still shows today rather than becoming a
    /// reproach — there is nothing to settle on a bin.
    func testACollectionEarlierTodayStaysInToday() {
        let morningBin = [BinSchedule(id: binID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 2, 6, 30)))]

        let agenda = TodayAgenda.build(bins: morningBin, tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertEqual(agenda.today.count, 1)
        XCTAssertTrue(agenda.overdue.isEmpty)
    }

    func testLastWeeksBinIsNotShownAtAll() {
        let agenda = TodayAgenda.build(bins: bins(), tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertFalse(
            agenda.allItems.contains { $0.kind == .bin && $0.date < self.date(2026, 9, 2) },
            "a missed bin is history, not a task"
        )
    }

    func testBinsAreNotActionable() {
        let agenda = TodayAgenda.build(bins: bins(), tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertFalse(agenda.today.first { $0.kind == .bin }?.isActionable ?? true)
    }

    // MARK: - Tasks

    func testMissedTasksAppearAsOverdueWithTheirAge() {
        let agenda = TodayAgenda.build(bins: [], tasks: tasks(), bills: [], payments: [], now: now, calendar: brisbane)

        // Anchored Aug 19, weekly: Aug 19 and Aug 26 are missed, Sep 2 is today.
        let overdueTasks = agenda.overdue.filter { $0.kind == .task }
        XCTAssertEqual(overdueTasks.count, 3, "including this morning's, which is already past")
        XCTAssertEqual(overdueTasks.first?.status, .overdue(days: 14))
        XCTAssertEqual(overdueTasks.last?.status, .overdue(days: 0))
    }

    func testCompletedTasksDropOffTheAgenda() {
        let completed = [date(2026, 8, 19), date(2026, 8, 26), date(2026, 9, 2)]

        let agenda = TodayAgenda.build(bins: [], tasks: tasks(completed: completed), bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertTrue(agenda.overdue.filter { $0.kind == .task }.isEmpty, "settled occurrences stop nagging")
        // The weekly task's next occurrence is Sep 9, exactly seven days out and
        // so past the horizon — nothing of it remains on the agenda.
        XCTAssertTrue(agenda.isEmpty)
    }

    /// A daily task inside the window is the real test of this: without the
    /// next-only rule it would contribute an item for every remaining day.
    func testOnlyTheNextTaskOccurrenceIsShownForward() {
        let daily = [TaskSpec(
            id: taskID,
            schedule: Schedule(frequency: .daily, anchorDate: date(2026, 9, 2, 9, 0)),
            completedDueDates: [date(2026, 9, 2)]
        )]

        let agenda = TodayAgenda.build(bins: [], tasks: daily, bills: [], payments: [], now: now, calendar: brisbane)

        let taskItems = agenda.allItems.filter { $0.kind == .task }
        XCTAssertEqual(taskItems.count, 1, "six more days are in range but must not be listed")
        XCTAssertEqual(taskItems.first?.date, date(2026, 9, 3, 9, 0))
        XCTAssertEqual(taskItems.first?.status, .dueTomorrow)
    }

    /// The horizon is seven days from the start of today, so an occurrence a
    /// full week out sits just outside it.
    func testTheWindowIsSevenDaysFromTheStartOfToday() {
        let sixDays = [BinSchedule(id: binID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 8, 19, 0)))]
        let sevenDays = [BinSchedule(id: binID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 9, 19, 0)))]

        XCTAssertEqual(
            TodayAgenda.build(bins: sixDays, tasks: [], bills: [], payments: [], now: now, calendar: brisbane)
                .laterThisWeek.count,
            1
        )
        XCTAssertTrue(
            TodayAgenda.build(bins: sevenDays, tasks: [], bills: [], payments: [], now: now, calendar: brisbane)
                .isEmpty
        )
    }

    func testTasksAreActionable() {
        let agenda = TodayAgenda.build(bins: [], tasks: tasks(), bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertTrue(agenda.overdue.filter { $0.kind == .task }.allSatisfy(\.isActionable))
    }

    // MARK: - Bills

    func testAnUnpaidBillFromLastWeekIsOverdue() {
        let agenda = TodayAgenda.build(bins: [], tasks: [], bills: bills(), payments: [], now: now, calendar: brisbane)

        let overdueBills = agenda.overdue.filter { $0.kind == .bill }
        XCTAssertEqual(overdueBills.count, 1)
        XCTAssertEqual(overdueBills.first?.status, .overdue(days: 5)) // due Aug 28
        XCTAssertEqual(overdueBills.first?.amountCents, 8_900)
    }

    func testAPaidBillLeavesTheAgenda() {
        let payments = [
            BillPaymentRecord(billID: billID, amountCents: 8_900, dueDate: date(2026, 8, 28), paidAt: date(2026, 8, 28))
        ]

        let agenda = TodayAgenda.build(bins: [], tasks: [], bills: bills(), payments: payments, now: now, calendar: brisbane)

        XCTAssertTrue(agenda.allItems.filter { $0.kind == .bill }.isEmpty)
    }

    /// The point of the automatic-settlement work: a direct debit must never
    /// resurface on the agenda as something to chase.
    func testAnAutomaticBillNeverAppearsAsOverdue() {
        let agenda = TodayAgenda.build(
            bins: [],
            tasks: [],
            bills: bills(paysAutomatically: true),
            payments: [],
            now: now,
            calendar: brisbane
        )

        XCTAssertTrue(
            agenda.allItems.filter { $0.kind == .bill }.isEmpty,
            "an assumed-settled debit is not outstanding"
        )
    }

    func testAnAutomaticBillStillDueLaterThisWeekIsShown() {
        let upcoming = [BillSpec(
            id: billID,
            name: "Telstra",
            amountCents: 8_900,
            schedule: Schedule(frequency: .monthly, anchorDate: date(2026, 9, 4, 9, 0)),
            paysAutomatically: true
        )]

        let agenda = TodayAgenda.build(bins: [], tasks: [], bills: upcoming, payments: [], now: now, calendar: brisbane)

        XCTAssertEqual(agenda.laterThisWeek.filter { $0.kind == .bill }.count, 1, "not yet due, so not yet assumed")
    }

    // MARK: - Ordering

    func testBinsComeBeforeTasksOnASharedEvening() {
        let eveningBin = [BinSchedule(id: binID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 2, 19, 0)))]
        let eveningTask = [TaskSpec(id: taskID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 2, 19, 0)))]

        let agenda = TodayAgenda.build(
            bins: eveningBin,
            tasks: eveningTask,
            bills: [],
            payments: [],
            now: now,
            calendar: brisbane
        )

        XCTAssertEqual(agenda.today.map(\.kind), [.bin, .task], "a bin night has the harder deadline")
    }

    func testBucketsAreDateOrdered() {
        let manyBins = [
            BinSchedule(id: UUID(), schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 2, 19, 0))),
            BinSchedule(id: UUID(), schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 2, 6, 30)))
        ]

        let agenda = TodayAgenda.build(bins: manyBins, tasks: [], bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertEqual(agenda.today.map(\.date), agenda.today.map(\.date).sorted())
    }

    func testOverdueIsOldestFirst() {
        let agenda = TodayAgenda.build(bins: [], tasks: tasks(), bills: bills(), payments: [], now: now, calendar: brisbane)

        XCTAssertEqual(agenda.overdue.map(\.date), agenda.overdue.map(\.date).sorted())
    }

    // MARK: - Counts

    func testActionableCountExcludesBinsAndFutureItems() {
        let agenda = TodayAgenda.build(
            bins: bins(),
            tasks: tasks(),
            bills: bills(),
            payments: [],
            now: now,
            calendar: brisbane
        )

        // 3 overdue tasks + 1 overdue bill; the bin tonight is not actionable.
        XCTAssertEqual(agenda.actionableCount, 4)
    }

    func testInactiveTasksAreExcluded() {
        let paused = [TaskSpec(
            id: taskID,
            schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 8, 19, 9, 0)),
            isActive: false
        )]

        let agenda = TodayAgenda.build(bins: [], tasks: paused, bills: [], payments: [], now: now, calendar: brisbane)

        XCTAssertTrue(agenda.isEmpty)
    }

    func testInactiveBillsAreExcluded() {
        let paused = [BillSpec(
            id: billID,
            name: "Internet",
            amountCents: 8_900,
            schedule: Schedule(frequency: .monthly, anchorDate: date(2026, 8, 28, 9, 0)),
            isActive: false
        )]

        let agenda = TodayAgenda.build(bins: [], tasks: [], bills: paused, payments: [], now: now, calendar: brisbane)

        XCTAssertTrue(agenda.isEmpty)
    }

    // MARK: - Identity

    func testItemIDsAreUniqueAcrossSources() {
        let agenda = TodayAgenda.build(
            bins: bins(),
            tasks: tasks(),
            bills: bills(),
            payments: [],
            now: now,
            calendar: brisbane
        )

        let ids = agenda.allItems.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids must be stable and unique for SwiftUI lists")
    }
}
