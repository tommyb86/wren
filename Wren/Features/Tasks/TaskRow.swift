import SwiftUI
import WrenCore

/// A task and its state, with the tick that settles the right occurrence.
/// Shared by the Tasks list and the Home summary.
@MainActor
struct TaskRow: View {
    let task: RecurringTask
    var now: Date = Date()
    var calendar: Calendar = .current
    let onComplete: () -> Void

    private var state: RecurringTaskState? { task.state(now: now, calendar: calendar) }

    var body: some View {
        HStack(spacing: Space.m) {
            Button(action: onComplete) {
                Image(systemName: isSettled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSettled ? Color.wren.accent : Color.wren.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(task.schedule == nil)
            .accessibilityLabel(isSettled ? "Completed" : "Mark done")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled task" : task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Color.wren.alert : Color.wren.textSecondary)
            }

            Spacer()

            if !task.isActive {
                Text("Paused")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.wren.textSecondary)
            } else if isOverdue, let count = state?.overdue.count, count > 1 {
                // A backlog is worth naming — one tap only drains one occurrence.
                Text("\(count) missed")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.alert)
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(.rect)
    }

    private var isOverdue: Bool {
        task.isActive && (state?.isOverdue ?? false)
    }

    /// True once the most recent occurrence has been settled and nothing is
    /// outstanding — the tick is a state readout, not a toggle.
    private var isSettled: Bool {
        guard let state else { return false }
        return !state.isOverdue && state.lastCompletedDue != nil
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

        guard let next = state.nextDue else { return "Finished" }

        if calendar.isDateInToday(next) {
            return "Due today at \(next.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(next) {
            return "Due tomorrow at \(next.formatted(date: .omitted, time: .shortened))"
        }
        return "Next \(next.formatted(.dateTime.weekday(.abbreviated).day().month()))"
    }
}
