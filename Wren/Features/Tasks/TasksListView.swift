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
    }

    private var list: some View {
        List {
            if !overdueTasks.isEmpty {
                section("Overdue", tasks: overdueTasks, color: .wren.alert)
            }

            section(overdueTasks.isEmpty ? "Tasks" : "Upcoming", tasks: upcomingTasks)

            // A settled one-off has nothing left to do, so it drops out of the
            // main list rather than sitting there looking pending forever.
            if !finishedTasks.isEmpty {
                section("Done", tasks: finishedTasks, color: .wren.textSecondary)
            }
        }
        .wrenListStyle()
    }

    private func section(_ title: String, tasks: [RecurringTask], color: Color = .wren.textPrimary) -> some View {
        Section {
            ForEach(Array(tasks.enumerated()), id: \.element.taskID) { index, task in
                row(task)
                    .wrenRow(first: index == 0, last: index == tasks.count - 1)
            }
        } header: {
            WrenListHeader(text: title, color: color)
        }
    }

    private func row(_ task: RecurringTask) -> some View {
        TaskRow(task: task, calendar: calendar, onComplete: { complete(task) }, onUndo: { undoLast(task) })
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

    private var overdueTasks: [RecurringTask] {
        tasks.filter { $0.isActive && ($0.state(calendar: calendar)?.isOverdue ?? false) }
    }

    private var finishedTasks: [RecurringTask] {
        tasks.filter(\.isFinished)
    }

    private var upcomingTasks: [RecurringTask] {
        let handled = Set(overdueTasks.map(\.taskID)).union(finishedTasks.map(\.taskID))
        return tasks.filter { !handled.contains($0.taskID) }
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
