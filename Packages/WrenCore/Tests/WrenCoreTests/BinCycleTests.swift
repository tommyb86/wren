import XCTest
@testable import WrenCore

final class BinCycleTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1 // Sunday
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let generalID = UUID()
    private let recyclingID = UUID()

    /// General waste weekly, recycling fortnightly, both out Tuesday evening —
    /// the standard QLD council setup.
    private func householdBins() -> [BinSchedule] {
        [
            BinSchedule(
                id: generalID,
                schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 1, 19, 0))
            ),
            BinSchedule(
                id: recyclingID,
                schedule: Schedule(frequency: .weekly, interval: 2, anchorDate: date(2026, 9, 1, 19, 0))
            )
        ]
    }

    func testCycleCoversTheWeekContainingNow() {
        // Wednesday 2026-09-02; the week runs Sun 30 Aug – Sat 5 Sep.
        let cycle = BinCycle.current(schedules: [], now: date(2026, 9, 2, 12, 0), calendar: brisbane)

        XCTAssertEqual(cycle.start, date(2026, 8, 30))
        XCTAssertEqual(brisbane.component(.weekday, from: cycle.start), 1, "cycle must start on the calendar's first weekday")
        XCTAssertTrue(cycle.end > date(2026, 9, 5, 23, 59))
        XCTAssertTrue(cycle.end < date(2026, 9, 6))
        XCTAssertTrue(cycle.isEmpty)
    }

    func testRecyclingWeekShowsBothBinsOnTheSameNight() {
        // Week of the fortnightly anchor: both bins go out.
        let cycle = BinCycle.current(schedules: householdBins(), now: date(2026, 9, 2, 12, 0), calendar: brisbane)

        XCTAssertEqual(cycle.due.count, 2)
        XCTAssertEqual(Set(cycle.due.map(\.binID)), [generalID, recyclingID])
        XCTAssertEqual(cycle.nights, [date(2026, 9, 1, 19, 0)], "two bins on one night is a single collection night")
    }

    func testNonRecyclingWeekShowsGeneralWasteOnly() {
        // The following week — recycling is fortnightly, so it sits out.
        let cycle = BinCycle.current(schedules: householdBins(), now: date(2026, 9, 9, 12, 0), calendar: brisbane)

        XCTAssertEqual(cycle.due.map(\.binID), [generalID])
        XCTAssertEqual(cycle.nights, [date(2026, 9, 8, 19, 0)])
    }

    func testDueIsSortedByDate() {
        let bins = [
            BinSchedule(id: recyclingID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 4, 19, 0))),
            BinSchedule(id: generalID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 9, 1, 19, 0)))
        ]

        let cycle = BinCycle.current(schedules: bins, now: date(2026, 9, 2, 12, 0), calendar: brisbane)

        XCTAssertEqual(cycle.due.map(\.binID), [generalID, recyclingID])
        XCTAssertEqual(cycle.due.map(\.date), cycle.due.map(\.date).sorted())
    }

    func testCollectionOnTheCycleBoundaryIsIncluded() {
        // Sunday 19:00 — the very first evening of the cycle.
        let bins = [BinSchedule(id: generalID, schedule: Schedule(frequency: .weekly, anchorDate: date(2026, 8, 30, 19, 0)))]

        let cycle = BinCycle.current(schedules: bins, now: date(2026, 9, 2, 12, 0), calendar: brisbane)

        XCTAssertEqual(cycle.due.count, 1)
        XCTAssertEqual(cycle.due.first?.date, date(2026, 8, 30, 19, 0))
    }

    func testWindowSpansMultipleWeeks() {
        let cycle = BinCycle.window(
            schedules: householdBins(),
            from: date(2026, 9, 1),
            to: date(2026, 9, 30),
            calendar: brisbane
        )

        // General waste: Sep 1, 8, 15, 22, 29. Recycling: Sep 1, 15, 29.
        XCTAssertEqual(cycle.due.filter { $0.binID == generalID }.count, 5)
        XCTAssertEqual(cycle.due.filter { $0.binID == recyclingID }.count, 3)
        XCTAssertEqual(cycle.nights.count, 5, "shared nights collapse")
    }

    func testDueIDsAreUniquePerBinAndNight() {
        let cycle = BinCycle.window(
            schedules: householdBins(),
            from: date(2026, 9, 1),
            to: date(2026, 9, 30),
            calendar: brisbane
        )

        XCTAssertEqual(Set(cycle.due.map(\.id)).count, cycle.due.count, "ids must be stable and unique for SwiftUI lists")
    }
}
