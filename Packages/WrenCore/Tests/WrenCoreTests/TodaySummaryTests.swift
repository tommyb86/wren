import XCTest
@testable import WrenCore

final class TodaySummaryTests: XCTestCase {

    private func item(_ kind: TodayItem.Kind, _ status: TodayItem.Status, cents: Int? = nil) -> TodayItem {
        TodayItem(
            kind: kind,
            sourceID: UUID(),
            date: Date(),
            status: status,
            isActionable: kind != .bin,
            amountCents: cents
        )
    }

    private func summary(_ agenda: TodayAgenda, setUp: Bool = true) -> TodaySummary {
        TodaySummary.make(for: agenda, hasAnythingSetUp: setUp) { Money.plainFormat(cents: $0) }
    }

    func testFullWeekReadsAsOneParagraph() {
        let agenda = TodayAgenda(
            overdue: [],
            today: [item(.bin, .dueToday), item(.bin, .dueToday)],
            tomorrow: [item(.bin, .dueTomorrow), item(.bin, .dueTomorrow), item(.task, .dueTomorrow), item(.bill, .dueTomorrow, cents: 16_199)],
            laterThisWeek: [item(.bill, .upcoming, cents: 15_000), item(.bill, .upcoming, cents: 19_873), item(.task, .upcoming)]
        )
        let result = summary(agenda)
        XCTAssertEqual(result.text, "Two bins go out tonight. One thing to do tomorrow, and $510.72 in bills due this week.")
        XCTAssertEqual(result.highlight, "$510.72")
    }

    func testOverdueLeads() {
        let agenda = TodayAgenda(
            overdue: [item(.task, .overdue(days: 2)), item(.bill, .overdue(days: 1), cents: 5_000)],
            today: [item(.task, .dueToday)],
            tomorrow: [],
            laterThisWeek: []
        )
        XCTAssertEqual(summary(agenda).text, "Two things need doing. One thing to do today.")
    }

    func testBinsCollectedTodayWhenNoneTonight() {
        let agenda = TodayAgenda(overdue: [], today: [item(.bin, .dueToday)], tomorrow: [], laterThisWeek: [])
        XCTAssertEqual(summary(agenda).text, "One bin collected today.")
        XCTAssertNil(summary(agenda).highlight)
    }

    func testTasksBothDays() {
        let agenda = TodayAgenda(
            overdue: [],
            today: [item(.task, .dueToday), item(.task, .dueToday)],
            tomorrow: [item(.task, .dueTomorrow)],
            laterThisWeek: []
        )
        XCTAssertEqual(summary(agenda).text, "Two things to do today and one tomorrow.")
    }

    func testBillsAloneStartTheSentence() {
        let agenda = TodayAgenda(overdue: [], today: [], tomorrow: [], laterThisWeek: [item(.bill, .upcoming, cents: 12_000)])
        XCTAssertEqual(summary(agenda).text, "$120.00 in bills due this week.")
    }

    func testEmptyStates() {
        let empty = TodayAgenda(overdue: [], today: [], tomorrow: [], laterThisWeek: [])
        XCTAssertEqual(summary(empty).text, "Nothing on for the next week.")
        XCTAssertEqual(summary(empty, setUp: false).text, "Nothing set up yet.")
    }

    func testLargeCountsFallBackToDigits() {
        let agenda = TodayAgenda(
            overdue: Array(repeating: item(.task, .overdue(days: 3)), count: 12),
            today: [], tomorrow: [], laterThisWeek: []
        )
        XCTAssertEqual(summary(agenda).text, "12 things need doing.")
    }
}
