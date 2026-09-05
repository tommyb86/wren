import XCTest
@testable import WrenCore

final class SchoolCalendarTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        brisbane.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let sample = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Sabre//Sabre VObject 4.5.7//EN
    BEGIN:VEVENT
    DTSTAMP:20260905T074049Z
    UID:124313/1
    SUMMARY:Mathematics
    LOCATION:Room 12
    DTSTART;TZID=Australia/Brisbane:20260907T090000
    DTEND;TZID=Australia/Brisbane:20260907T100000
    END:VEVENT
    BEGIN:VEVENT
    UID:635304-1792108800@www.bbc.qld.edu.au
    SUMMARY:College Art Show
    DTSTART;VALUE=DATE:20261016
    DTEND;VALUE=DATE:20261018
    END:VEVENT
    END:VCALENDAR
    """

    func testParsesTimedEvent() {
        let events = SchoolICal.parse(sample, calendar: brisbane)
        XCTAssertEqual(events.count, 2)
        let maths = events[0]
        XCTAssertEqual(maths.uid, "124313/1")
        XCTAssertEqual(maths.title, "Mathematics")
        XCTAssertEqual(maths.location, "Room 12")
        XCTAssertFalse(maths.allDay)
        XCTAssertEqual(maths.start, day(2026, 9, 7, 9, 0))
        XCTAssertEqual(maths.end, day(2026, 9, 7, 10, 0))
    }

    func testParsesAllDayEvent() {
        let events = SchoolICal.parse(sample, calendar: brisbane)
        let show = events[1]
        XCTAssertEqual(show.title, "College Art Show")
        XCTAssertTrue(show.allDay)
        XCTAssertEqual(brisbane.startOfDay(for: show.start), brisbane.startOfDay(for: day(2026, 10, 16)))
    }

    func testUnfoldsFoldedLines() {
        let folded = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:x1
        SUMMARY:A very long title that has been
          folded across two lines
        DTSTART;VALUE=DATE:20260907
        END:VEVENT
        END:VCALENDAR
        """
        let events = SchoolICal.parse(folded, calendar: brisbane)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].title, "A very long title that has been folded across two lines")
    }

    func testEventWithoutDateIsSkipped() {
        let noDate = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:x\nSUMMARY:No date\nEND:VEVENT\nEND:VCALENDAR"
        XCTAssertTrue(SchoolICal.parse(noDate, calendar: brisbane).isEmpty)
    }

    // MARK: - Correlation

    private func notice(_ title: String, _ body: String = "") -> SchoolFeedItem {
        SchoolFeedItem(guid: UUID().uuidString, title: title, bodyText: body, published: nil)
    }

    func testCorrelationMergesOnTwoSignals() {
        let event = SchoolCalendarEvent(
            uid: "e1", title: "Father's Day Assembly", location: "College Hall",
            start: day(2026, 9, 7, 13, 30)
        )
        let notice = self.notice(
            "Junior School Father's Day Special Assembly",
            "Assembly in College Hall. Parking on the oval from 1.00pm on Monday 7 September."
        )
        let result = SchoolCorrelation.correlate(event: event, notices: [notice], calendar: brisbane)
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.signals, 2)
    }

    func testUnrelatedEventDoesNotCorrelate() {
        let event = SchoolCalendarEvent(uid: "e2", title: "Water Polo vs Churchie", start: day(2026, 9, 12, 8, 0))
        let notice = self.notice("Library book returns", "Please return overdue books.")
        XCTAssertNil(SchoolCorrelation.correlate(event: event, notices: [notice], calendar: brisbane))
    }
}
