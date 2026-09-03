import SwiftUI
import WrenCore

/// A task and its state, with the tick that settles the right occurrence.
///
/// The box is a toggle: unticked, a tap completes the oldest outstanding
/// occurrence (or the next one, ahead of time); ticked, a tap undoes the
/// last completion. So there is always a way back.
@MainActor
struct TaskRow: View {
    let task: RecurringTask
    var now: Date = Date()
    var calendar: Calendar = .current
    let onComplete: () -> Void
    var onUndo: (() -> Void)? = nil

    private var state: RecurringTaskState? { task.state(now: now, calendar: calendar) }

    var body: some View {
        HStack(spacing: Space.m) {
            WrenCheckbox(isOn: isSettled) {
                if isSettled, let onUndo {
                    onUndo()
                } else {
                    onComplete()
                }
            }
            .disabled(task.schedule == nil)
            .accessibilityLabel(isSettled ? "Completed, tap to undo" : "Mark done")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled task" : task.title)
                    .font(WrenFont.heading)
                    .foregroundStyle(task.isActive && !task.isFinished ? Color.wren.textPrimary : Color.wren.textSecondary)
                Text(subtitle)
                    .font(WrenFont.detail)
                    .foregroundStyle(isOverdue ? Color.wren.alert : Color.wren.textSecondary)
            }

            Spacer()

            if !task.isActive {
                WrenChip(text: "Paused", tint: .wren.textSecondary, fill: .wren.surface)
            } else if isOverdue, let count = state?.overdue.count, count > 1 {
                // A backlog is worth naming — one tap only drains one occurrence.
                WrenChip(text: "\(count) missed", tint: .wren.alert, fill: .wren.surface)
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(.rect)
    }

    private var isOverdue: Bool {
        task.isActive && (state?.isOverdue ?? false)
    }

    /// The next occurrence has been ticked ahead of time.
    private var isDoneAhead: Bool {
        guard let next = state?.nextDue else { return false }
        return TaskEngine.isComplete(occurrence: next, completedDueDates: task.completedDueDates, calendar: calendar)
    }

    /// True once the most recent occurrence has been settled and nothing is
    /// outstanding — the tick is a state readout as much as a control.
    private var isSettled: Bool {
        guard let state else { return false }
        return !state.isOverdue && (state.lastCompletedDue != nil || isDoneAhead)
    }

    private var subtitle: String {
        guard task.schedule != nil else { return "No schedule" }
        guard let state else { return "No schedule" }

        if let oldest = state.overdue.first {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: oldest),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            switch days {
            case 0: return "Due earlier today"
            case 1: return "Overdue since yesterday"
            default: return "Overdue by \(days) days"
            }
        }

        guard let next = state.nextDue else {
            // A one-off is genuinely done; a repeating task with no next
            // occurrence has hit its end date.
            return task.isFinished ? "Done" : "Finished"
        }

        if isDoneAhead {
            return "Done for \(next.formatted(.dateTime.weekday(.abbreviated).day().month()))"
        }
        if calendar.isDateInToday(next) {
            return "Due today at \(next.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(next) {
            return "Due tomorrow at \(next.formatted(date: .omitted, time: .shortened))"
        }
        return "Next \(next.formatted(.dateTime.weekday(.abbreviated).day().month()))"
    }
}
