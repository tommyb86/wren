import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BinCollection.sortOrder) private var bins: [BinCollection]
    @Query(sort: \RecurringTask.sortOrder) private var tasks: [RecurringTask]
    @StateObject private var scheduler = NotificationScheduler.shared

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header

                    NavigationLink {
                        BinsListView()
                    } label: {
                        BinWeekCard(bins: bins, calendar: calendar)
                    }
                    .buttonStyle(.plain)

                    if scheduler.authorizationStatus == .denied && !(bins.isEmpty && tasks.isEmpty) {
                        permissionWarning
                    }

                    tasksSection

                    upcoming

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        WrenCard {
                            HStack {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("Diagnostics")
                                        .font(.headline)
                                        .foregroundStyle(Color.wren.textPrimary)
                                    Text("\(scheduler.pending.count) reminder\(scheduler.pending.count == 1 ? "" : "s") scheduled")
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(Color.wren.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.wren.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(Space.l)
            }
            .background(Color.wren.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await scheduler.refreshAuthorizationStatus()
            await ReminderCoordinator.rebuild(context: context, calendar: calendar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            WrenTitle(text: "Wren")
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.footnote)
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(.top, Space.s)
    }

    /// Terracotta earns its keep here: without permission the app silently does
    /// nothing useful, which is worth shouting about.
    private var permissionWarning: some View {
        WrenCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Reminders are switched off")
                    .font(.headline)
                    .foregroundStyle(Color.wren.alert)
                Text("Wren can't notify you about bin nights until notifications are allowed in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
    }

    /// Overdue first, then what's due in the next couple of days. Anything
    /// further out belongs on the Tasks screen, not here.
    private var tasksSection: some View {
        // State is computed once per task: it walks the schedule, so calling it
        // three times per row in a filter chain was both wasteful and how the
        // "nothing due soon" case ended up unhandled.
        let live = tasks.filter(\.isActive).map { (task: $0, state: $0.state(calendar: calendar)) }
        let horizon = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()

        let overdue = live.filter { $0.state?.isOverdue ?? false }
        let soon = live.filter { entry in
            guard !(entry.state?.isOverdue ?? false), let next = entry.state?.nextDue else { return false }
            return next <= horizon
        }
        let shown = (overdue + soon).map(\.task)

        // The next thing due at all, however far out — so the section always has
        // something to say rather than disappearing.
        let nextDueAnywhere = live.compactMap { $0.state?.nextDue }.min()

        return Group {
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack {
                        Text(overdue.isEmpty ? "Tasks" : "Needs doing")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(overdue.isEmpty ? Color.wren.textSecondary : Color.wren.alert)
                        Spacer()
                        NavigationLink("All tasks") { TasksListView() }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.wren.accent)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.taskID) { index, task in
                            TaskRow(task: task, calendar: calendar) {
                                TaskStore.complete(task, context: context, calendar: calendar)
                            }
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.s)
                            if index < shown.count - 1 {
                                Divider().overlay(Color.wren.divider)
                            }
                        }
                    }
                    .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(Color.wren.divider, lineWidth: 1)
                    )
                }
            } else {
                // Two remaining cases, and both must still offer a way through
                // to Tasks: nothing set up yet, and everything set up but
                // nothing due for a while.
                tasksEntryCard(nextDue: nextDueAnywhere, pausedCount: tasks.count - tasks.filter(\.isActive).count)
            }
        }
    }

    private func tasksEntryCard(nextDue: Date?, pausedCount: Int) -> some View {
        NavigationLink {
            TasksListView()
        } label: {
            WrenCard {
                HStack {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Tasks")
                            .font(.headline)
                            .foregroundStyle(Color.wren.textPrimary)
                        Text(tasksEntrySubtitle(nextDue: nextDue, pausedCount: pausedCount))
                            .font(.subheadline)
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.wren.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func tasksEntrySubtitle(nextDue: Date?, pausedCount: Int) -> String {
        if tasks.isEmpty {
            return "Filters, smoke alarms, the car service — anything that comes round again."
        }
        if let nextDue {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: Date()),
                to: calendar.startOfDay(for: nextDue)
            ).day ?? 0
            let when = nextDue.formatted(.dateTime.weekday(.wide).day().month())
            return days <= 7
                ? "Nothing due yet — next is \(when)."
                : "Nothing due for \(days) days — next is \(when)."
        }
        if pausedCount == tasks.count {
            return "\(tasks.count) task\(tasks.count == 1 ? "" : "s"), all paused."
        }
        return "\(tasks.count) task\(tasks.count == 1 ? "" : "s"), nothing scheduled."
    }

    /// The next fortnight, so "is it recycling next week?" is answerable without
    /// opening anything.
    private var upcoming: some View {
        let horizon = calendar.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        let window = BinCycle.window(
            schedules: bins.filter(\.isActive).compactMap(\.binSchedule),
            from: Date(),
            to: horizon,
            calendar: calendar
        )

        return Group {
            if !window.nights.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Next fortnight")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.wren.textSecondary)

                    VStack(spacing: 0) {
                        ForEach(Array(window.nights.enumerated()), id: \.element) { index, night in
                            nightRow(night, dues: window.due.filter { $0.date == night })
                            if index < window.nights.count - 1 {
                                Divider().overlay(Color.wren.divider)
                            }
                        }
                    }
                    .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(Color.wren.divider, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func nightRow(_ night: Date, dues: [BinDue]) -> some View {
        HStack(spacing: Space.m) {
            HStack(spacing: Space.xs) {
                ForEach(dues) { due in
                    if let bin = bins.first(where: { $0.binID == due.binID }) {
                        Circle()
                            .fill(Color(binHex: bin.colorHex))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .frame(width: 44, alignment: .leading)

            Text(night.formatted(.dateTime.weekday(.abbreviated).day().month()))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.wren.textPrimary)

            Spacer()

            Text(dues.compactMap { due in bins.first { $0.binID == due.binID }?.name }.joined(separator: " + "))
                .font(.caption)
                .foregroundStyle(Color.wren.textSecondary)
                .lineLimit(1)
        }
        .padding(Space.m)
    }
}
