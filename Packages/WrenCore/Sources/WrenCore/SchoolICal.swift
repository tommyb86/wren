import Foundation

/// One event from the personal calendar feed, decoupled from iCal and SwiftData.
public struct SchoolCalendarEvent: Hashable, Sendable, Identifiable {
    /// The iCal UID — stable across fetches, so a moved or cancelled event is
    /// detectable rather than just additive.
    public let uid: String
    public let title: String
    public let location: String
    public let start: Date
    public let end: Date?
    public let allDay: Bool

    public var id: String { uid }

    public init(uid: String, title: String, location: String = "", start: Date, end: Date? = nil, allDay: Bool = false) {
        self.uid = uid
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.allDay = allDay
    }
}

/// Parses an iCalendar (RFC 5545) feed into events. Pure Foundation, so it
/// tests on Windows CI. Handles line folding, `VALUE=DATE` all-day events,
/// `TZID=` local times and `Z` UTC times — the shapes a Schoolbox/Sabre export
/// actually emits.
public enum SchoolICal {
    public static func parse(_ data: Data, calendar: Calendar = .current) -> [SchoolCalendarEvent] {
        parse(String(decoding: data, as: UTF8.self), calendar: calendar)
    }

    public static func parse(_ text: String, calendar: Calendar = .current) -> [SchoolCalendarEvent] {
        let lines = unfold(text)
        var events: [SchoolCalendarEvent] = []

        var inEvent = false
        var props: [(name: String, params: [String: String], value: String)] = []

        for line in lines {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                props = []
                continue
            }
            if line == "END:VEVENT" {
                if let event = makeEvent(from: props, calendar: calendar) {
                    events.append(event)
                }
                inEvent = false
                continue
            }
            guard inEvent, let parsed = parseProperty(line) else { continue }
            props.append(parsed)
        }
        return events
    }

    // MARK: - Lines

    /// Joins folded continuation lines (a line beginning with a space or tab is
    /// a continuation of the previous one) and drops blank lines.
    private static func unfold(_ text: String) -> [String] {
        var result: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let first = raw.first, first == " " || first == "\t" {
                if !result.isEmpty {
                    result[result.count - 1] += raw.dropFirst()
                }
            } else if !raw.isEmpty {
                result.append(raw)
            }
        }
        return result
    }

    private static func parseProperty(_ line: String) -> (name: String, params: [String: String], value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let left = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...])

        let segments = left.components(separatedBy: ";")
        guard let name = segments.first?.uppercased() else { return nil }

        var params: [String: String] = [:]
        for segment in segments.dropFirst() {
            let pair = segment.components(separatedBy: "=")
            if pair.count == 2 { params[pair[0].uppercased()] = pair[1] }
        }
        return (name, params, value)
    }

    // MARK: - Events

    private static func makeEvent(
        from props: [(name: String, params: [String: String], value: String)],
        calendar: Calendar
    ) -> SchoolCalendarEvent? {
        func first(_ name: String) -> (params: [String: String], value: String)? {
            props.first { $0.name == name }.map { ($0.params, $0.value) }
        }

        guard let uidProp = first("UID"), let dtstart = first("DTSTART") else { return nil }
        guard let start = parseDate(dtstart.value, params: dtstart.params, calendar: calendar) else { return nil }

        let end = first("DTEND").flatMap { parseDate($0.value, params: $0.params, calendar: calendar)?.date }
        let allDay = start.allDay

        return SchoolCalendarEvent(
            uid: uidProp.value.trimmingCharacters(in: .whitespaces),
            title: unescape(first("SUMMARY")?.value ?? ""),
            location: unescape(first("LOCATION")?.value ?? ""),
            start: start.date,
            end: end,
            allDay: allDay
        )
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Dates

    private static func parseDate(
        _ value: String,
        params: [String: String],
        calendar: Calendar
    ) -> (date: Date, allDay: Bool)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let digits = v.filter { $0.isNumber }

        // All-day: VALUE=DATE, or a bare 8-digit date.
        if params["VALUE"]?.uppercased() == "DATE" || digits.count == 8 {
            guard digits.count >= 8 else { return nil }
            let (y, m, d) = (intAt(digits, 0, 4), intAt(digits, 4, 6), intAt(digits, 6, 8))
            var cal = calendar
            cal.timeZone = TimeZone(identifier: params["TZID"] ?? "") ?? calendar.timeZone
            guard let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 0, minute: 0)) else { return nil }
            return (date, true)
        }

        // Date-time: needs at least yyyymmddThhmmss worth of digits.
        guard digits.count >= 14 else { return nil }
        let (y, m, d) = (intAt(digits, 0, 4), intAt(digits, 4, 6), intAt(digits, 6, 8))
        let (h, min, s) = (intAt(digits, 8, 10), intAt(digits, 10, 12), intAt(digits, 12, 14))

        var cal = calendar
        if v.uppercased().hasSuffix("Z") {
            cal.timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) {
            cal.timeZone = tz
        }
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s)) else { return nil }
        return (date, false)
    }

    private static func intAt(_ s: String, _ from: Int, _ to: Int) -> Int {
        let chars = Array(s)
        guard to <= chars.count else { return 0 }
        return Int(String(chars[from..<to])) ?? 0
    }
}
