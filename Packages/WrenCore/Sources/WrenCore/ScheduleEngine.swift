import Foundation

/// Turns a `Schedule` into dates. This is an *occurrence* engine, not a reminder
/// engine — notifications are only one consumer. The dashboard's bin-week card
/// and the bill forecast are others, which is why it answers date ranges rather
/// than just "when next".
///
/// All arithmetic goes through `Calendar` / `DateComponents`. Never manual
/// second-counting: that is what breaks across DST and month lengths.
public struct ScheduleEngine {
    /// Bound on cycles examined in one call, so a pathological schedule can
    /// never hang the app.
    public static let cycleCap = 5_000

    // MARK: - Public API

    /// The first occurrence strictly after `after`, or nil if the schedule has ended.
    public static func next(_ schedule: Schedule, after: Date, calendar: Calendar = .current) -> Date? {
        var index = startIndex(for: after, schedule: schedule, calendar: calendar)

        for _ in 0..<cycleCap {
            guard let base = cycleBase(index: index, schedule: schedule, calendar: calendar) else { return nil }

            // Cycles only move forward, so once the cycle itself is past the end
            // date nothing later can qualify.
            if let end = schedule.endDate, base > end, !spansMultipleDays(schedule) { return nil }

            for date in dates(cycleIndex: index, schedule: schedule, calendar: calendar) where date > after {
                if let end = schedule.endDate, date > end { return nil }
                return date
            }
            index += 1
        }
        return nil
    }

    /// Every occurrence in `from...to`, inclusive at both ends.
    public static func occurrences(
        _ schedule: Schedule,
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        guard from <= to else { return [] }
        let horizon = min(to, schedule.endDate ?? to)
        guard from <= horizon else { return [] }

        var result: [Date] = []
        var index = startIndex(for: from, schedule: schedule, calendar: calendar)

        for _ in 0..<cycleCap {
            guard let base = cycleBase(index: index, schedule: schedule, calendar: calendar) else { break }
            // A weekly-with-weekdays cycle's dates all land inside the week that
            // starts at `base`, so once `base` is past the horizon we are done.
            if base > horizon { break }

            for date in dates(cycleIndex: index, schedule: schedule, calendar: calendar) {
                guard date >= from, date <= horizon else { continue }
                result.append(date)
            }
            index += 1
        }
        return result.sorted()
    }

    /// The next `limit` occurrences at or after `from`. Used by the notification
    /// rebuild and the bill forecast, where the count matters more than the range.
    public static func occurrences(
        _ schedule: Schedule,
        from: Date,
        limit: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard limit > 0 else { return [] }

        var result: [Date] = []
        var index = startIndex(for: from, schedule: schedule, calendar: calendar)

        for _ in 0..<cycleCap {
            guard let base = cycleBase(index: index, schedule: schedule, calendar: calendar) else { break }
            if let end = schedule.endDate, base > end, !spansMultipleDays(schedule) { break }

            for date in dates(cycleIndex: index, schedule: schedule, calendar: calendar) {
                guard date >= from else { continue }
                if let end = schedule.endDate, date > end { return result.sorted() }
                result.append(date)
                if result.count >= limit { return result.sorted() }
            }
            index += 1
        }
        return result.sorted()
    }

    // MARK: - Cycles

    /// The date a cycle counts from. For most frequencies this *is* the
    /// occurrence; for weekly-with-weekdays it is the start of that week.
    private static func cycleBase(index: Int, schedule: Schedule, calendar: Calendar) -> Date? {
        let step = index * schedule.effectiveInterval

        switch schedule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: step, to: schedule.anchorDate)
        case .weekly:
            guard spansMultipleDays(schedule) else {
                return calendar.date(byAdding: .weekOfYear, value: step, to: schedule.anchorDate)
            }
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: schedule.anchorDate)?.start else {
                return nil
            }
            return calendar.date(byAdding: .weekOfYear, value: step, to: weekStart)
        case .monthly:
            return calendar.date(byAdding: .month, value: step, to: schedule.anchorDate)
        case .yearly:
            return calendar.date(byAdding: .year, value: step, to: schedule.anchorDate)
        }
    }

    /// Occurrences produced by one cycle, ascending. Only weekly-with-weekdays
    /// yields more than one.
    private static func dates(cycleIndex index: Int, schedule: Schedule, calendar: Calendar) -> [Date] {
        guard let base = cycleBase(index: index, schedule: schedule, calendar: calendar) else { return [] }

        guard spansMultipleDays(schedule) else {
            // The anchor is the first occurrence — never emit anything before it.
            return base >= schedule.anchorDate ? [base] : []
        }

        let firstWeekday = calendar.firstWeekday
        return schedule.weekdays
            .sorted()
            .compactMap { weekday -> Date? in
                let offset = ((weekday - firstWeekday) + 7) % 7
                guard let day = calendar.date(byAdding: .day, value: offset, to: base),
                      let stamped = applyingTime(of: schedule.anchorDate, to: day, calendar: calendar)
                else { return nil }
                // A weekday earlier in the anchor's own week predates the anchor.
                return stamped >= schedule.anchorDate ? stamped : nil
            }
            .sorted()
    }

    private static func spansMultipleDays(_ schedule: Schedule) -> Bool {
        schedule.frequency == .weekly && !schedule.weekdays.isEmpty
    }

    /// Carries the anchor's time of day onto another day. Built from components
    /// rather than by adding seconds, so the wall-clock time survives DST.
    private static func applyingTime(of source: Date, to day: Date, calendar: Calendar) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components)
    }

    /// Cheap estimate of which cycle contains `date`, so a schedule anchored
    /// years ago doesn't need thousands of iterations to reach today. Deliberately
    /// one cycle early — the callers scan forward and filter.
    private static func startIndex(for date: Date, schedule: Schedule, calendar: Calendar) -> Int {
        let component: Calendar.Component
        var reference = schedule.anchorDate

        switch schedule.frequency {
        case .daily:
            component = .day
        case .weekly:
            component = .weekOfYear
            if spansMultipleDays(schedule),
               let weekStart = calendar.dateInterval(of: .weekOfYear, for: schedule.anchorDate)?.start {
                reference = weekStart
            }
        case .monthly:
            component = .month
        case .yearly:
            component = .year
        }

        guard date > reference,
              let elapsed = calendar.dateComponents([component], from: reference, to: date).value(for: component)
        else { return 0 }

        return max(0, (elapsed / schedule.effectiveInterval) - 1)
    }
}
