import XCTest
@testable import WrenCore

final class FinancialYearTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Boundaries

    func testJulyFirstStartsANewFinancialYear() {
        XCTAssertEqual(FinancialYear.containing(date(2026, 7, 1), calendar: brisbane).startYear, 2026)
    }

    func testJuneThirtiethBelongsToThePreviousStartYear() {
        XCTAssertEqual(FinancialYear.containing(date(2026, 6, 30), calendar: brisbane).startYear, 2025)
    }

    /// The boundary is the whole day, not midday — a receipt from the evening of
    /// 30 June belongs to the year that is closing.
    func testTheLastMomentOfJuneIsStillTheClosingYear() {
        let fy = FinancialYear(startYear: 2025)

        XCTAssertTrue(fy.contains(date(2026, 6, 30, 23), calendar: brisbane))
        XCTAssertFalse(fy.contains(date(2026, 7, 1, 0), calendar: brisbane))
    }

    func testStartAndEndSpanExactlyTwelveMonths() {
        let fy = FinancialYear(startYear: 2026)

        XCTAssertEqual(fy.start(calendar: brisbane), date(2026, 7, 1, 0))
        XCTAssertTrue(fy.end(calendar: brisbane) > date(2027, 6, 30, 23))
        XCTAssertTrue(fy.end(calendar: brisbane) < date(2027, 7, 1, 0))
    }

    func testContainsCoversTheWholeYearAndNothingElse() {
        let fy = FinancialYear(startYear: 2026)

        XCTAssertTrue(fy.contains(date(2026, 7, 1), calendar: brisbane))
        XCTAssertTrue(fy.contains(date(2026, 12, 25), calendar: brisbane))
        XCTAssertTrue(fy.contains(date(2027, 6, 30), calendar: brisbane))
        XCTAssertFalse(fy.contains(date(2026, 6, 30), calendar: brisbane))
        XCTAssertFalse(fy.contains(date(2027, 7, 1), calendar: brisbane))
    }

    // MARK: - Labels

    func testLabelUsesTheTwoYearForm() {
        XCTAssertEqual(FinancialYear(startYear: 2026).label, "2026–27")
        XCTAssertEqual(FinancialYear(startYear: 2026).prefixedLabel, "FY2026–27")
    }

    /// The century rollover is where a naive "startYear + 1" string breaks.
    func testLabelAcrossTheCenturyBoundary() {
        XCTAssertEqual(FinancialYear(startYear: 2099).label, "2099–00")
        XCTAssertEqual(FinancialYear(startYear: 2009).label, "2009–10")
    }

    // MARK: - Navigation and ordering

    func testPreviousAndNext() {
        let fy = FinancialYear(startYear: 2026)

        XCTAssertEqual(fy.previous.startYear, 2025)
        XCTAssertEqual(fy.next.startYear, 2027)
    }

    func testOrderingIsChronological() {
        XCTAssertTrue(FinancialYear(startYear: 2025) < FinancialYear(startYear: 2026))
    }

    // MARK: - Spanning a set of receipts

    func testSpanningReturnsEachYearOnceNewestFirst() {
        let dates = [
            date(2026, 8, 1),  // FY2026
            date(2026, 9, 15), // FY2026
            date(2026, 3, 1),  // FY2025
            date(2025, 7, 2)   // FY2025
        ]

        XCTAssertEqual(
            FinancialYear.spanning(dates, calendar: brisbane).map(\.startYear),
            [2026, 2025]
        )
    }

    func testSpanningNothingIsEmpty() {
        XCTAssertTrue(FinancialYear.spanning([], calendar: brisbane).isEmpty)
    }

    // MARK: - Compatibility with the Phase 0 helper

    func testTheOriginalHelperAgreesWithTheType() {
        for probe in [date(2026, 7, 1), date(2026, 6, 30), date(2026, 12, 25)] {
            XCTAssertEqual(
                WrenCore.financialYear(of: probe, calendar: brisbane),
                FinancialYear.containing(probe, calendar: brisbane).startYear
            )
        }
    }
}
