import Foundation

/// What a recurring task looks like right now: what was missed, what is next.
public struct RecurringTaskState: Hashable, Sendable {
    /// Past occurrences with no completion recorded, oldest first.
    public let overdue: [Date]
    /// The next occurrence still to come, whether or not anything is overdue.
    public let nextDue: Date?
    /// The most recent occurrence at or before now, if it has been completed.
    public let lastCompletedDue: Date?

    public var isOverdue: Bool { !overdue.isEmpty }

    public init(overdue: [Date], nextDue: Date?, lastCompletedDue: Date?) {
        self.overdue = overdue
        self.nextDue = nextDue
        self.lastCompletedDue = lastCompletedDue
    }
}

/// Completion tracking for recurring tasks.
///
/// The load-bearing decision: a completion is recorded against **the due date it
/// settles**, not against "now". Ticking Monday's bin-clean on Wednesday must
/// satisfy Monday's occurrence — otherwise Monday stays overdue forever and the
/// history is a record of when you happened to open the app rather than of what
/// actually got done.
public struct TaskEngine {
    /// How far back to look for misses. A task ignored for longer than this
    /// stops accumulating overdue entries, which keeps the UI honest instead of
    /// showing a wall of shame from six months ago.
    public static let defaultLookbackDays = 60

    public static func state(
        schedule: Schedule,
        completedDueDates: [Date],
        now: Date = Date(),
        lookbackDays: Int = defaultLookbackDays,
        calendar: Calendar = .current
    ) -> RecurringTaskState {
        let completedDays = Set(completedDueDates.map { calendar.startOfDay(for: $0) })

        let windowStart = calendar.date(byAdding: .day, value: -max(0, lookbackDays), to: now) ?? now
        let past = ScheduleEngine.occurrences(schedule, from: windowStart, to: now, calendar: calendar)

        let overdue = past.filter { !completedDays.contains(calendar.startOfDay(for: $0)) }

        let lastCompletedDue = past.last { completedDays.contains(calendar.startOfDay(for: $0)) }

        return RecurringTaskState(
            overdue: overdue,
            nextDue: ScheduleEngine.next(schedule, after: now, calendar: calendar),
            lastCompletedDue: lastCompletedDue
        )
    }

    /// The occurrence a "done" tap should settle: the oldest thing outstanding,
    /// falling back to the next one due if nothing is.
    ///
    /// Completing the oldest first is what makes repeated taps drain a backlog
    /// rather than repeatedly satisfying the same occurrence.
    public static func occurrenceToComplete(
        schedule: Schedule,
        completedDueDates: [Date],
        now: Date = Date(),
        lookbackDays: Int = defaultLookbackDays,
        calendar: Calendar = .current
    ) -> Date? {
        let current = state(
            schedule: schedule,
            completedDueDates: completedDueDates,
            now: now,
            lookbackDays: lookbackDays,
            calendar: calendar
        )
        return current.overdue.first ?? current.nextDue
    }

    /// Whether a specific occurrence has been completed. Matched at day
    /// granularity so an edited schedule time doesn't orphan existing history.
    public static func isComplete(
        occurrence: Date,
        completedDueDates: [Date],
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: occurrence)
        return completedDueDates.contains { calendar.startOfDay(for: $0) == day }
    }

    /// Occurrences still outstanding inside a window — what the Today screen and
    /// the notification rebuild both need. Completed occurrences are excluded, so
    /// a task you have already done stops nagging.
    public static func outstanding(
        schedule: Schedule,
        completedDueDates: [Date],
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let completedDays = Set(completedDueDates.map { calendar.startOfDay(for: $0) })
        return ScheduleEngine.occurrences(schedule, from: from, to: to, calendar: calendar)
            .filter { !completedDays.contains(calendar.startOfDay(for: $0)) }
    }
}
