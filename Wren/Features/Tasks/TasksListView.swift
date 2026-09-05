import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct TasksListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringTask.sortOrder) private var tasks: [RecurringTask]

    @State private var editing: RecurringTask?
    @State private var isAdding = false
    @State private var lastSettled: SettledTask?

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if tasks.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color.wren.background)
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: { WrenToolbarIcon(systemName: "plus") }
                    .accessibilityLabel("Add task")
            }
        }
        .sheet(isPresented: $isAdding) {
            TaskEditorView(task: nil, existingTaskCount: tasks.count)
        }
        .sheet(item: $editing) { task in
            TaskEditorView(task: task, existingTaskCount: tasks.count)
        }
        .overlay(alignment: .bottom) {
            if let lastSettled {
                WrenUndoBanner(title: "Done · \(lastSettled.title)", detail: lastSettled.detail) {
                    undo(lastSettled)
                }
            }
        }
        // Reminders are cleared here rather than on a timer: this is the only
        // screen they are visible on, so it is the only place it matters.
        .task {
            TaskStore.purgeSettledReminders(tasks, context: context, calendar: calendar)
        }
    }

    /// Reminders and recurring tasks are kept apart because they behave
    /// differently: a reminder is done once and then gone, a recurring task
    /// only ever cycles. Anything overdue floats above both, since at that
    /// point what kind of thing it is matters less than the fact it is late.
    private var list: some View {
        List {
            summary

            if !needsDoing.isEmpty {
                section("Needs doing", tasks: needsDoing, color: .wren.alert, showsKind: true)
            }

            if !reminders.isEmpty {
                section(
                    "Reminders",
                    tasks: reminders,
                    footer: "One-offs. A ticked one is removed a week later."
                )
            }

            if !recurring.isEmpty {
                section(
                    "Recurring",
                    tasks: recurring,
                    footer: "Sorted by what is next. Paused ones sink to the bottom."
                )
            }
        }
        .wrenListStyle()
    }

    private var summary: some View {
        Text(summaryText)
            .font(WrenFont.detail)
            .monospacedDigit()
            .foregroundStyle(Color.wren.textSecondary)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.wren.background)
            .listRowSeparator(.hidden)
    }

    private var summaryText: String {
        let recurringCount = tasks.filter { !$0.isOneOff }.count
        let reminderCount = tasks.filter(\.isOneOff).count
        var parts = ["\(recurringCount) recurring", "\(reminderCount) reminder\(reminderCount == 1 ? "" : "s")"]
        parts.append(needsDoing.isEmpty ? "nothing overdue" : "\(needsDoing.count) overdue")
        return parts.joined(separator: " · ")
    }

    private func section(
        _ title: String,
        tasks: [RecurringTask],
        color: Color = .wren.textPrimary,
        footer: String? = nil,
        showsKind: Bool = false
    ) -> some View {
        Section {
            ForEach(Array(tasks.enumerated()), id: \.element.taskID) { index, task in
                row(task, showsKind: showsKind)
                    .wrenRow(first: index == 0, last: index == tasks.count - 1)
            }
        } header: {
            WrenListHeader(text: title, color: color)
        } footer: {
            if let footer {
                WrenListFooter(text: footer)
            }
        }
    }

    private func row(_ task: RecurringTask, showsKind: Bool = false) -> some View {
        TaskRow(
            task: task,
            calendar: calendar,
            showsKind: showsKind,
            onComplete: { complete(task) },
            onUndo: { undoLast(task) }
        )
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    TaskStore.delete(task, context: context, calendar: calendar)
                }
                .tint(Color.wren.alert)
                Button("Edit") { editing = task }
                    .tint(Color.wren.textPrimary)
            }
            .onTapGesture { editing = task }
    }

    // MARK: - Grouping

    /// Late, whatever kind it is. Oldest miss first, so the thing that has been
    /// waiting longest is the thing at the top.
    private var needsDoing: [RecurringTask] {
        tasks
            .filter { $0.isActive && ($0.state(calendar: calendar)?.isOverdue ?? false) }
            .sorted { oldestMiss($0) < oldestMiss($1) }
    }

    /// One-offs that are not late. Pending first by when they are due, then the
    /// ticked ones waiting out their week.
    private var reminders: [RecurringTask] {
        tasks
            .filter { $0.isOneOff && !isLate($0) }
            .sorted { a, b in
                let (doneA, doneB) = (a.isFinished ? 1 : 0, b.isFinished ? 1 : 0)
                if doneA != doneB { return doneA < doneB }
                return nextDue(a) < nextDue(b)
            }
    }

    /// Standing commitments that are not late, by what is next. Paused ones
    /// have no next occurrence to speak of, so they are pushed to the bottom
    /// explicitly rather than relying on where a nil date happens to sort.
    private var recurring: [RecurringTask] {
        tasks
            .filter { !$0.isOneOff && !isLate($0) }
            .sorted { a, b in
                let (pausedA, pausedB) = (a.isActive ? 0 : 1, b.isActive ? 0 : 1)
                if pausedA != pausedB { return pausedA < pausedB }
                return nextDue(a) < nextDue(b)
            }
    }

    private func isLate(_ task: RecurringTask) -> Bool {
        task.isActive && (task.state(calendar: calendar)?.isOverdue ?? false)
    }

    private func nextDue(_ task: RecurringTask) -> Date {
        task.state(calendar: calendar)?.nextDue ?? .distantFuture
    }

    private func oldestMiss(_ task: RecurringTask) -> Date {
        task.state(calendar: calendar)?.overdue.first ?? .distantFuture
    }

    private func complete(_ task: RecurringTask) {
        guard let due = TaskStore.complete(task, context: context, calendar: calendar) else { return }
        let settled = SettledTask(taskID: task.taskID, title: task.title, due: due)
        withAnimation(.snappy) { lastSettled = settled }

        // Undo is worth offering: the tick settles a specific occurrence, and
        // getting the wrong one silently would corrupt the history.
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.snappy) {
                if lastSettled == settled { lastSettled = nil }
            }
        }
    }

    private func undo(_ settled: SettledTask) {
        if let task = tasks.first(where: { $0.taskID == settled.taskID }) {
            TaskStore.undoLastCompletion(task, context: context, calendar: calendar)
        }
        withAnimation(.snappy) { lastSettled = nil }
    }

    /// The ticked box tapped again: take back the most recent completion.
    private func undoLast(_ task: RecurringTask) {
        TaskStore.undoLastCompletion(task, context: context, calendar: calendar)
        withAnimation(.snappy) {
            if lastSettled?.taskID == task.taskID { lastSettled = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text("No tasks yet")
                .font(WrenFont.title3)
                .foregroundStyle(Color.wren.textPrimary)
            Text("Anything that comes round again — filters, smoke alarms, the car service — or a one-off reminder.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.wren.textSecondary)
            Button("Add your first task") { isAdding = true }
                .buttonStyle(WrenPrimaryButtonStyle())
                .padding(.top, Space.s)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
