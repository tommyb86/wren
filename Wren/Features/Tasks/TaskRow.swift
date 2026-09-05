import SwiftUI
import WrenCore

private extension String {
    var capitalisedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

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
    /// Set where reminders and recurring tasks are mixed together, so a one-off
    /// can be told apart. Inside a section that is already one kind it would be
    /// noise.
    var showsKind: Bool = false
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
            } else if showsKind, task.isOneOff {
                WrenChip(text: "Once", tint: .wren.textSecondary, fill: .wren.surface)
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

    /// The cadence, for recurring tasks only. On the Recurring list it is the
    /// thing being scanned for — "how often does this come round" — and on a
    /// one-off it would just say "Once", which the chip already covers.
    private var cadence: String? {
        guard let schedule = task.schedule, schedule.frequency != .once else { return nil }
        return schedule.summary(calendar: calendar)
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
            let late: String
            switch days {
            case 0: late = "Due earlier today"
            case 1: late = "Overdue since yesterday"
            default: late = "Overdue by \(days) days"
            }
            // Lateness leads; the cadence explains what was missed.
            return [late, cadence].compactMap { $0 }.joined(separator: " · ")
        }

        guard let next = state.nextDue else {
            // A one-off is genuinely done; a repeating task with no next
            // occurrence has hit its end date.
            return task.isFinished ? "Done" : "Finished"
        }

        let when: String
        if isDoneAhead {
            when = "done for \(next.formatted(.dateTime.weekday(.abbreviated).day().month()))"
        } else if calendar.isDateInToday(next) {
            when = "today at \(next.formatted(date: .omitted, time: .shortened))"
        } else if calendar.isDateInTomorrow(next) {
            when = "tomorrow at \(next.formatted(date: .omitted, time: .shortened))"
        } else {
            when = "next \(next.formatted(.dateTime.weekday(.abbreviated).day().month()))"
        }

        guard let cadence else { return when.capitalisedFirst }
        return "\(cadence) · \(when)"
    }
}
