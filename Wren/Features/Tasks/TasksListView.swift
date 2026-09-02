import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct TasksListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringTask.sortOrder) private var tasks: [RecurringTask]

    @State private var editing: RecurringTask?
    @State private var isAdding = false
    @State private var lastSettled: (title: String, due: Date)?

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
                Button { isAdding = true } label: { Image(systemName: "plus") }
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
                undoBanner(lastSettled)
            }
        }
    }

    private var list: some View {
        List {
            if !overdueTasks.isEmpty {
                Section("Overdue") {
                    ForEach(overdueTasks) { task in row(task) }
                }
            }

            Section(overdueTasks.isEmpty ? "Tasks" : "Upcoming") {
                ForEach(upcomingTasks) { task in row(task) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ task: RecurringTask) -> some View {
        TaskRow(task: task, calendar: calendar) { complete(task) }
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    TaskStore.delete(task, context: context, calendar: calendar)
                }
                Button("Edit") { editing = task }
                    .tint(Color.wren.accent)
            }
            .onTapGesture { editing = task }
    }

    private var overdueTasks: [RecurringTask] {
        tasks.filter { $0.isActive && ($0.state(calendar: calendar)?.isOverdue ?? false) }
    }

    private var upcomingTasks: [RecurringTask] {
        let overdueIDs = Set(overdueTasks.map(\.taskID))
        return tasks.filter { !overdueIDs.contains($0.taskID) }
    }

    private func complete(_ task: RecurringTask) {
        guard let due = TaskStore.complete(task, context: context, calendar: calendar) else { return }
        withAnimation(.snappy) { lastSettled = (task.title, due) }

        // Undo is worth offering: the tick settles a specific occurrence, and
        // getting the wrong one silently would corrupt the history.
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.snappy) { lastSettled = nil }
        }
    }

    private func undoBanner(_ settled: (title: String, due: Date)) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Done — \(settled.title)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Text("Settled \(settled.due.formatted(.dateTime.weekday(.abbreviated).day().month()))")
                    .font(.caption2)
                    .foregroundStyle(Color.wren.textSecondary)
            }
            Spacer()
            Button("Undo") {
                if let task = tasks.first(where: { $0.title == settled.title }) {
                    TaskStore.undoLastCompletion(task, context: context, calendar: calendar)
                }
                withAnimation(.snappy) { lastSettled = nil }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.wren.accent)
        }
        .padding(Space.m)
        .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.wren.divider, lineWidth: 1)
        )
        .padding(Space.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text("No tasks yet")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color.wren.textPrimary)
            Text("Anything that comes round again — filters, smoke alarms, the car service.")
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
