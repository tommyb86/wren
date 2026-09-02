import Foundation

/// A thing that recurs. Bins, tasks and bills are all the same problem, so they
/// all describe themselves with this and consume `ScheduleEngine`.
///
/// `anchorDate` is itself an occurrence — the one everything else counts from.
/// Occurrences are always computed as `anchor + n × interval` rather than by
/// stepping from the previous occurrence, so nothing drifts: a monthly schedule
/// anchored on the 31st yields Feb 28 and then Mar 31, not Mar 28.
public struct Schedule: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency

    /// Every N periods. Fortnightly is `.weekly` with an interval of 2.
    public var interval: Int

    /// The occurrence everything counts from. Its time of day is the time of day
    /// of every occurrence.
    public var anchorDate: Date

    /// Weekly only. `Calendar` numbering: 1 = Sunday … 7 = Saturday.
    /// Empty means "use the anchor's own weekday".
    public var weekdays: Set<Int>

    /// Inclusive. No occurrence falls after it.
    public var endDate: Date?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        anchorDate: Date,
        weekdays: Set<Int> = [],
        endDate: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.anchorDate = anchorDate
        self.weekdays = weekdays
        self.endDate = endDate
    }

    /// Interval sanitised for use, since decoding bypasses `init`.
    public var effectiveInterval: Int { max(1, interval) }
}

// MARK: - Persistence

extension Schedule {
    /// SwiftData models store the schedule as `Data`, so encoding lives with the
    /// type rather than being re-invented at each call site.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> Schedule {
        try JSONDecoder().decode(Schedule.self, from: data)
    }

    /// Non-throwing form for view code, where a corrupt blob should degrade to
    /// "no schedule" rather than take the screen down.
    public static func lenientlyDecoded(from data: Data) -> Schedule? {
        try? decoded(from: data)
    }
}

// MARK: - Description

extension Schedule {
    /// Plain-language summary, e.g. "Fortnightly on Tuesday". Weekday names come
    /// from the calendar's locale so this stays correct outside en_AU.
    public func summary(calendar: Calendar = .current) -> String {
        let cadence: String
        switch (frequency, effectiveInterval) {
        case (.daily, 1): cadence = "Daily"
        case (.weekly, 1): cadence = "Weekly"
        case (.weekly, 2): cadence = "Fortnightly"
        case (.monthly, 1): cadence = "Monthly"
        case (.yearly, 1): cadence = "Yearly"
        case (.daily, let n): cadence = "Every \(n) days"
        case (.weekly, let n): cadence = "Every \(n) weeks"
        case (.monthly, let n): cadence = "Every \(n) months"
        case (.yearly, let n): cadence = "Every \(n) years"
        }

        guard frequency == .weekly else { return cadence }

        let days = weekdays.isEmpty
            ? [calendar.component(.weekday, from: anchorDate)]
            : weekdays.sorted()
        let names = days.compactMap { Self.weekdayName($0, calendar: calendar) }
        guard !names.isEmpty else { return cadence }
        return "\(cadence) on \(names.joined(separator: ", "))"
    }

    static func weekdayName(_ weekday: Int, calendar: Calendar) -> String? {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return nil }
        return symbols[index]
    }
}
