import XCTest
@testable import WrenCore

final class WrenCoreTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        return c
    }()

    func testVersionIsSet() {
        XCTAssertFalse(WrenCore.version.isEmpty)
    }

    func testFinancialYearStartsInJuly() throws {
        let july = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        XCTAssertEqual(WrenCore.financialYear(of: july, calendar: calendar), 2026)
    }

    func testFinancialYearBeforeJulyBelongsToPreviousYear() throws {
        let june = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30)))
        XCTAssertEqual(WrenCore.financialYear(of: june, calendar: calendar), 2025)
    }
}
