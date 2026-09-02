import Foundation

/// Bills arrive at different frequencies, so nothing is comparable until
/// everything is converted to a common period. A $120 quarterly bill is $40 a
/// month; a $50 fortnightly one is not $100 a month, because there are 26.09
/// fortnights in a year rather than 24.
///
/// Every report in the app depends on this conversion, which is why it lives in
/// WrenCore with tests rather than being inlined in a view.
public enum BillingPeriod {
    /// Mean Gregorian year. Using 365 would understate annual totals by a
    /// quarter of a day's worth of every daily bill, and using 52 weeks would
    /// lose two days a year on fortnightly ones.
    public static let daysPerYear = 365.2425
    public static let weeksPerYear = daysPerYear / 7 // 52.1775
    public static let monthsPerYear = 12.0

    /// How many times a schedule bills in a year.
    ///
    /// Deliberately ignores `endDate`: this is a *rate*, used to compare a
    /// quarterly bill against a fortnightly one. Anything that needs real dated
    /// occurrences — the forecast, this month's total — asks `ScheduleEngine`
    /// instead, which does respect the end date.
    public static func occurrencesPerYear(_ schedule: Schedule) -> Double {
        let interval = Double(schedule.effectiveInterval)

        switch schedule.frequency {
        case .daily:
            return daysPerYear / interval
        case .weekly:
            // Explicit weekdays bill once per listed day, per cycle.
            let perCycle = schedule.weekdays.isEmpty ? 1.0 : Double(schedule.weekdays.count)
            return (weeksPerYear / interval) * perCycle
        case .monthly:
            return monthsPerYear / interval
        case .yearly:
            return 1 / interval
        }
    }

    /// What this bill costs over a year.
    public static func annualCents(amountCents: Int, schedule: Schedule) -> Int {
        let annual = Double(amountCents) * occurrencesPerYear(schedule)
        return Int(annual.rounded())
    }

    /// The monthly-equivalent figure — the number that makes bills comparable.
    ///
    /// Derived from the annual total rather than by scaling the raw amount, so a
    /// quarterly bill lands on an exact twelfth and doesn't accumulate rounding.
    public static func monthlyEquivalentCents(amountCents: Int, schedule: Schedule) -> Int {
        let annual = Double(amountCents) * occurrencesPerYear(schedule)
        return Int((annual / monthsPerYear).rounded())
    }

    /// Weekly equivalent, for the "what does the household cost a week" framing.
    public static func weeklyEquivalentCents(amountCents: Int, schedule: Schedule) -> Int {
        let annual = Double(amountCents) * occurrencesPerYear(schedule)
        return Int((annual / weeksPerYear).rounded())
    }

    /// Human-readable cadence for report rows, e.g. "$120.00 quarterly".
    public static func cadenceDescription(_ schedule: Schedule) -> String {
        switch (schedule.frequency, schedule.effectiveInterval) {
        case (.daily, 1): return "daily"
        case (.weekly, 1): return "weekly"
        case (.weekly, 2): return "fortnightly"
        case (.monthly, 1): return "monthly"
        case (.monthly, 3): return "quarterly"
        case (.monthly, 6): return "twice a year"
        case (.yearly, 1): return "yearly"
        case (.daily, let n): return "every \(n) days"
        case (.weekly, let n): return "every \(n) weeks"
        case (.monthly, let n): return "every \(n) months"
        case (.yearly, let n): return "every \(n) years"
        }
    }
}
