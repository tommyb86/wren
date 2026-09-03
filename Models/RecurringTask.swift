import Foundation
import SwiftData
import WrenCore

/// Named `RecurringTask` rather than `Task` so it never collides with Swift
/// concurrency's `Task` at the call sites that use both.
@Model
final class RecurringTask {
    /// Stable across edits, so notification identifiers stay idempotent.
    var taskID: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var scheduleData: Data = Data()
    /// Lead time on the reminder. 0 means "at the due time".
    var reminderMinutesBefore: Int = 0
    var isActive: Bool = true
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TaskCompletion.task)
    var completions: [TaskCompletion]? = []

    init(
        taskID: UUID = UUID(),
        title: String = "",
        notes: String = "",
        schedule: Schedule? = nil,
        reminderMinutesBefore: Int = 0,
        isActive: Bool = true,
        sortOrder: Int = 0
    ) {
        self.taskID = taskID
        self.title = title
        self.notes = notes
        self.scheduleData = (try? schedule?.encoded()) ?? Data()
        self.reminderMinutesBefore = reminderMinutesBefore
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.completions = []
    }
}

extension RecurringTask {
    var schedule: Schedule? {
        guard !scheduleData.isEmpty else { return nil }
        return Schedule.lenientlyDecoded(from: scheduleData)
    }

    func apply(_ schedule: Schedule) {
        scheduleData = (try? schedule.encoded()) ?? Data()
    }

    /// The due dates that have been settled — what the engine reasons over.
    var completedDueDates: [Date] {
        (completions ?? []).map(\.dueDate)
    }

    func state(now: Date = Date(), calendar: Calendar = .current) -> RecurringTaskState? {
        guard let schedule else { return nil }
        return TaskEngine.state(
            schedule: schedule,
            completedDueDates: completedDueDates,
            now: now,
            calendar: calendar
        )
    }

    /// True for a one-off reminder that has been settled: it has no further
    /// occurrences and nothing outstanding, so it is done rather than merely
    /// quiet. A repeating task is never finished — it comes round again.
    /// Checked against the completions directly rather than via
    /// `RecurringTaskState`, whose history is bounded by the lookback window —
    /// a reminder settled months ago would otherwise stop reading as done.
    var isFinished: Bool {
        guard let schedule, schedule.frequency == .once else { return false }
        return TaskEngine.isComplete(occurrence: schedule.anchorDate, completedDueDates: completedDueDates)
    }

    /// The occurrence a "done" tap should settle.
    func occurrenceToComplete(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let schedule else { return nil }
        return TaskEngine.occurrenceToComplete(
            schedule: schedule,
            completedDueDates: completedDueDates,
            now: now,
            calendar: calendar
        )
    }
}

/// One settled occurrence. `dueDate` is which occurrence this completes;
/// `completedAt` is when the tick actually happened. Recording both is what
/// makes the history honest — "done, four days late" is a different fact from
/// "done on time".
@Model
final class TaskCompletion {
    var dueDate: Date = Date()
    var completedAt: Date = Date()
    var task: RecurringTask?

    init(dueDate: Date, completedAt: Date = Date(), task: RecurringTask? = nil) {
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.task = task
    }

    /// Whole days between when it was due and when it was ticked.
    func latenessInDays(calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dueDate),
            to: calendar.startOfDay(for: completedAt)
        ).day ?? 0
    }
}
