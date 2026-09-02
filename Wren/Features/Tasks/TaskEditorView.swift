import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct TaskEditorView: View {
    /// nil when adding.
    let task: RecurringTask?
    let existingTaskCount: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var reminderMinutesBefore = 0
    @State private var isActive = true
    @State private var draft = ScheduleDraft()
    @State private var didLoad = false

    private let calendar = Calendar.current

    private var isEditing: Bool { task != nil }
    private var reminderOptions: [Int] { [0, 15, 60, 24 * 60] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                ScheduleEditor(draft: $draft, labels: .tasks, calendar: calendar)

                Section {
                    Picker("Remind me", selection: $reminderMinutesBefore) {
                        ForEach(reminderOptions, id: \.self) { minutes in
                            Text(reminderLabel(minutes)).tag(minutes)
                        }
                    }
                    Toggle("Active", isOn: $isActive)
                } footer: {
                    Text(previewFooter)
                }

                if let task, !(task.completions ?? []).isEmpty {
                    history(task)
                }

                if isEditing {
                    Section {
                        Button("Delete task", role: .destructive) {
                            if let task {
                                TaskStore.delete(task, context: context, calendar: calendar)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.wren.background)
            .navigationTitle(isEditing ? "Edit task" : "Add task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { load() }
        }
    }

    /// Recording both the due date and the tick makes "done, four days late" a
    /// visible fact rather than a lost one.
    private func history(_ task: RecurringTask) -> some View {
        Section("History") {
            ForEach(recentCompletions(task)) { completion in
                HStack {
                    Text(completion.dueDate.formatted(.dateTime.weekday(.abbreviated).day().month()))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    Spacer()
                    Text(latenessLabel(completion))
                        .font(.caption)
                        .foregroundStyle(completion.latenessInDays(calendar: calendar) > 0
                                         ? Color.wren.alert : Color.wren.textSecondary)
                }
            }
        }
    }

    private func recentCompletions(_ task: RecurringTask) -> [TaskCompletion] {
        (task.completions ?? [])
            .sorted { $0.dueDate > $1.dueDate }
            .prefix(10)
            .map { $0 }
    }

    private func latenessLabel(_ completion: TaskCompletion) -> String {
        let days = completion.latenessInDays(calendar: calendar)
        switch days {
        case ..<0: return "\(-days)d early"
        case 0: return "On time"
        case 1: return "1d late"
        default: return "\(days)d late"
        }
    }

    private var previewFooter: String {
        guard let next = ScheduleEngine.next(draft.schedule, after: Date(), calendar: calendar) else {
            return "No upcoming occurrences — check the schedule."
        }
        guard reminderMinutesBefore > 0,
              let reminder = calendar.date(byAdding: .minute, value: -reminderMinutesBefore, to: next)
        else {
            return "Next due \(next.formatted(.dateTime.weekday(.wide).day().month()))"
                + " at \(next.formatted(date: .omitted, time: .shortened))."
        }
        return "Next due \(next.formatted(.dateTime.weekday(.wide).day().month()))."
            + " Reminder \(reminder.formatted(.dateTime.weekday(.abbreviated)))"
            + " at \(reminder.formatted(date: .omitted, time: .shortened))."
    }

    private func reminderLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "At the due time"
        case 15: return "15 minutes before"
        case 60: return "An hour before"
        case 24 * 60: return "A day before"
        default: return "\(minutes) minutes before"
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let task else {
            var draftValue = ScheduleDraft()
            draftValue.frequency = .weekly
            draftValue.anchorDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            draft = draftValue
            return
        }

        title = task.title
        notes = task.notes
        reminderMinutesBefore = task.reminderMinutesBefore
        isActive = task.isActive
        if let schedule = task.schedule {
            draft = ScheduleDraft(schedule)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let isFirstSource = !isEditing && ReminderCoordinator.hasNoSources(context: context)

        if let task {
            task.title = trimmed
            task.notes = notes
            task.reminderMinutesBefore = reminderMinutesBefore
            task.isActive = isActive
            task.apply(draft.schedule)
            Logger.shared.info("tasks", "updated '\(trimmed)' — \(draft.schedule.summary(calendar: calendar))")
        } else {
            let created = RecurringTask(
                title: trimmed,
                notes: notes,
                schedule: draft.schedule,
                reminderMinutesBefore: reminderMinutesBefore,
                isActive: isActive,
                sortOrder: existingTaskCount
            )
            context.insert(created)
            Logger.shared.info("tasks", "added '\(trimmed)' — \(draft.schedule.summary(calendar: calendar))")
        }

        do {
            try context.save()
        } catch {
            Logger.shared.error("tasks", "save failed: \(error.localizedDescription)")
        }

        Task {
            if isFirstSource {
                await NotificationScheduler.shared.requestAuthorization()
            }
            await ReminderCoordinator.rebuild(context: context, calendar: calendar)
        }
        dismiss()
    }
}
