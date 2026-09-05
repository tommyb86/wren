import Foundation

/// Settings for the daily brief, shared by the Settings screen and the
/// scheduler. Stored in `UserDefaults` rather than SwiftData because the
/// scheduler needs them outside any model context.
enum MorningBrief {
    static let enabledKey = "morningBriefEnabled"
    static let timeKey = "morningBriefMinutes"

    /// 7:30am.
    static let defaultMinutes = 7 * 60 + 30

    /// How many mornings are written ahead.
    ///
    /// Each brief names what that specific day holds, so it cannot repeat — it
    /// has to be written per day and rewritten on every rebuild. A week is
    /// enough that ignoring the app for a few days doesn't silence it, and
    /// cheap enough against the request budget.
    static let horizonDays = 7

    static var isEnabled: Bool {
        // `object(forKey:)` rather than `bool(forKey:)`: an unset key has to
        // mean on, and `bool` cannot tell unset from a deliberate false.
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Minutes from midnight. Stored as an Int so the picker and the scheduler
    /// agree without a date round trip.
    static var minutesFromMidnight: Int {
        guard let stored = UserDefaults.standard.object(forKey: timeKey) as? Int else {
            return defaultMinutes
        }
        return min(max(stored, 0), 24 * 60 - 1)
    }

    static func identifier(for day: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return "brief-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    // MARK: - Time conversion

    /// The stored time as a Date today, for a DatePicker to bind to.
    static func time(on day: Date = Date(), calendar: Calendar = .current) -> Date {
        let minutes = minutesFromMidnight
        return calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: day
        ) ?? day
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
