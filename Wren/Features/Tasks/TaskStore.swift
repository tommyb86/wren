import Foundation
import SwiftData
import UIKit
import WrenCore

/// Completing a task is the one action in the app with real semantics, so it
/// lives here rather than being re-implemented in each view: it records against
/// the *due date* the tap settles, not against "now".
@MainActor
enum TaskStore {
    /// Ticks the oldest outstanding occurrence, falling back to the next one due.
    /// Returns the settled due date.
    @discardableResult
    static func complete(
        _ task: RecurringTask,
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let due = task.occurrenceToComplete(now: now, calendar: calendar) else {
            Logger.shared.warn("tasks", "'\(task.title)' has nothing to complete")
            return nil
        }

        // Guard against a double tap settling the same occurrence twice.
        guard !TaskEngine.isComplete(occurrence: due, completedDueDates: task.completedDueDates, calendar: calendar) else {
            Logger.shared.debug("tasks", "'\(task.title)' already complete for \(due)")
            return nil
        }

        let completion = TaskCompletion(dueDate: due, completedAt: now, task: task)
        context.insert(completion)
        if task.completions == nil {
            task.completions = [completion]
        } else {
            task.completions?.append(completion)
        }

        save(context, action: "complete '\(task.title)'")

        let lateness = completion.latenessInDays(calendar: calendar)
        Logger.shared.info(
            "tasks",
            "completed '\(task.title)' for due \(due.formatted(date: .abbreviated, time: .shortened))"
                + (lateness > 0 ? " (\(lateness)d late)" : "")
        )

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await ReminderCoordinator.rebuild(context: context, calendar: calendar) }
        return due
    }

    /// Undoes the most recently settled occurrence.
    static func undoLastCompletion(
        _ task: RecurringTask,
        context: ModelContext,
        calendar: Calendar = .current
    ) {
        guard let latest = (task.completions ?? []).max(by: { $0.completedAt < $1.completedAt }) else { return }

        Logger.shared.info("tasks", "undid completion of '\(task.title)' for due \(latest.dueDate)")
        task.completions?.removeAll { $0.persistentModelID == latest.persistentModelID }
        context.delete(latest)
        save(context, action: "undo completion")

        Task { await ReminderCoordinator.rebuild(context: context, calendar: calendar) }
    }

    /// Removes reminders that were ticked more than a week ago.
    ///
    /// Only one-offs: a recurring task is a standing commitment and is never
    /// deleted behind the user's back. Run when the Tasks screen appears,
    /// which is the only place a settled reminder is visible.
    static func purgeSettledReminders(
        _ tasks: [RecurringTask],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let expired = tasks.filter { task in
            guard task.isOneOff, task.isFinished, let ticked = task.lastCompletedAt else { return false }
            return TaskEngine.settledReminderHasExpired(completedAt: ticked, now: now, calendar: calendar)
        }
        guard !expired.isEmpty else { return }

        for task in expired {
            Logger.shared.info("tasks", "removed settled reminder '\(task.title)' — done over \(TaskEngine.settledReminderRetentionDays) days ago")
            context.delete(task)
        }
        save(context, action: "purge settled reminders")
    }

    static func delete(_ task: RecurringTask, context: ModelContext, calendar: Calendar = .current) {
        Logger.shared.info("tasks", "deleted '\(task.title)'")
        context.delete(task)
        save(context, action: "delete task")
        Task { await ReminderCoordinator.rebuild(context: context, calendar: calendar) }
    }

    private static func save(_ context: ModelContext, action: String) {
        do {
            try context.save()
        } catch {
            Logger.shared.error("tasks", "\(action) failed to save: \(error.localizedDescription)")
        }
    }
}
