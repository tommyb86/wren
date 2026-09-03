import Foundation

/// An Australian financial year: 1 July to 30 June.
///
/// Receipts are grouped and filtered by this rather than by calendar year,
/// because that is the only grouping that matters at tax time.
public struct FinancialYear: Hashable, Sendable, Identifiable, Comparable {
    /// The calendar year the FY starts in. 2026 means 1 Jul 2026 – 30 Jun 2027.
    public let startYear: Int

    public var id: Int { startYear }

    public init(startYear: Int) {
        self.startYear = startYear
    }

    /// "2026–27", the form the ATO and everyone else uses.
    public var label: String {
        "\(startYear)–\(String(format: "%02d", (startYear + 1) % 100))"
    }

    /// "FY2026–27", for headings where the context isn't obvious.
    public var prefixedLabel: String { "FY\(label)" }

    public func start(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: startYear, month: 7, day: 1)) ?? Date()
    }

    /// The last moment of 30 June, so range checks can be inclusive.
    public func end(calendar: Calendar = .current) -> Date {
        guard let julyFirst = calendar.date(from: DateComponents(year: startYear + 1, month: 7, day: 1)) else {
            return Date()
        }
        return julyFirst.addingTimeInterval(-1)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        date >= start(calendar: calendar) && date <= end(calendar: calendar)
    }

    public static func containing(_ date: Date, calendar: Calendar = .current) -> FinancialYear {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return FinancialYear(startYear: 0) }
        // July onwards belongs to the FY starting this year; anything earlier
        // belongs to the one that started last year.
        return FinancialYear(startYear: month >= 7 ? year : year - 1)
    }

    public static func current(now: Date = Date(), calendar: Calendar = .current) -> FinancialYear {
        containing(now, calendar: calendar)
    }

    public var previous: FinancialYear { FinancialYear(startYear: startYear - 1) }
    public var next: FinancialYear { FinancialYear(startYear: startYear + 1) }

    public static func < (lhs: FinancialYear, rhs: FinancialYear) -> Bool {
        lhs.startYear < rhs.startYear
    }

    /// Every financial year covered by a set of dates, newest first — what the
    /// receipts list uses for its section headers and its year picker.
    public static func spanning(_ dates: [Date], calendar: Calendar = .current) -> [FinancialYear] {
        Set(dates.map { containing($0, calendar: calendar) })
            .sorted(by: >)
    }
}
