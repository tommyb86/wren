import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct BinEditorView: View {
    /// nil when adding.
    let bin: BinCollection?
    let existingBinCount: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var lidHex: String = BinLid.red.rawValue
    @State private var reminderHoursBefore: Int = 14
    @State private var isActive: Bool = true
    @State private var draft = ScheduleDraft()
    @State private var didLoad = false

    private let calendar = Calendar.current
    private let log = Logger.shared

    private var isEditing: Bool { bin != nil }

    private var reminderOptions: [Int] { [1, 2, 3, 12, 14, 16, 24] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bin") {
                    TextField("Name", text: $name)
                    lidPicker
                }

                ScheduleEditor(draft: $draft, calendar: calendar)

                Section {
                    Picker("Remind me", selection: $reminderHoursBefore) {
                        ForEach(reminderOptions, id: \.self) { hours in
                            Text(reminderLabel(hours)).tag(hours)
                        }
                    }
                    Toggle("Active", isOn: $isActive)
                } footer: {
                    Text(previewFooter)
                }

                if isEditing {
                    Section {
                        Button("Delete bin", role: .destructive, action: delete)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.wren.background)
            .navigationTitle(isEditing ? "Edit bin" : "Add bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { load() }
        }
    }

    private var lidPicker: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Lid colour")
                .font(.subheadline)
                .foregroundStyle(Color.wren.textSecondary)

            HStack(spacing: Space.m) {
                ForEach(BinLid.allCases) { lid in
                    Button {
                        lidHex = lid.rawValue
                        if name.isEmpty { name = lid.suggestedName }
                    } label: {
                        Circle()
                            .fill(lid.color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().strokeBorder(
                                    lidHex == lid.rawValue ? Color.wren.textPrimary : Color.wren.divider,
                                    lineWidth: lidHex == lid.rawValue ? 2 : 1
                                )
                            )
                            .accessibilityLabel(lid.label)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var previewFooter: String {
        guard let next = ScheduleEngine.next(draft.schedule, after: Date(), calendar: calendar) else {
            return "No upcoming collections — check the schedule."
        }
        guard let reminder = calendar.date(byAdding: .hour, value: -reminderHoursBefore, to: next) else {
            return "Next collection \(next.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Next collection \(next.formatted(.dateTime.weekday(.wide).day().month()))"
            + " at \(next.formatted(date: .omitted, time: .shortened)). "
            + "Reminder \(reminder.formatted(.dateTime.weekday(.abbreviated))) "
            + "at \(reminder.formatted(date: .omitted, time: .shortened))."
    }

    private func reminderLabel(_ hours: Int) -> String {
        switch hours {
        case 1: return "1 hour before"
        case 24: return "A day before"
        default: return "\(hours) hours before"
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let bin else {
            // Sensible default: out at 6pm this evening, weekly.
            var draftValue = ScheduleDraft()
            draftValue.frequency = .weekly
            draftValue.anchorDate = calendar.date(
                bySettingHour: 18, minute: 0, second: 0, of: Date()
            ) ?? Date()
            draft = draftValue
            name = BinLid.red.suggestedName
            return
        }

        name = bin.name
        lidHex = bin.colorHex
        reminderHoursBefore = bin.reminderHoursBefore
        isActive = bin.isActive
        if let schedule = bin.schedule {
            draft = ScheduleDraft(schedule)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let isFirstSource = !isEditing && ReminderCoordinator.hasNoSources(context: context)

        if let bin {
            bin.name = trimmed
            bin.colorHex = lidHex
            bin.reminderHoursBefore = reminderHoursBefore
            bin.isActive = isActive
            bin.apply(draft.schedule)
            log.info("bins", "updated '\(trimmed)' — \(draft.schedule.summary(calendar: calendar))")
        } else {
            let created = BinCollection(
                name: trimmed,
                colorHex: lidHex,
                schedule: draft.schedule,
                reminderHoursBefore: reminderHoursBefore,
                isActive: isActive,
                sortOrder: existingBinCount
            )
            context.insert(created)
            log.info("bins", "added '\(trimmed)' — \(draft.schedule.summary(calendar: calendar))")
        }

        do {
            try context.save()
        } catch {
            log.error("bins", "save failed: \(error.localizedDescription)")
        }

        // Permission is requested on first meaningful use — adding the first bin
        // — rather than at launch, so the prompt arrives with context.
        Task {
            if isFirstSource {
                await NotificationScheduler.shared.requestAuthorization()
            }
            await rebuildReminders()
        }
        dismiss()
    }

    private func delete() {
        guard let bin else { return }
        log.info("bins", "deleted '\(bin.name)'")
        context.delete(bin)
        do {
            try context.save()
        } catch {
            log.error("bins", "delete failed: \(error.localizedDescription)")
        }
        Task { await rebuildReminders() }
        dismiss()
    }

    private func rebuildReminders() async {
        await ReminderCoordinator.rebuild(context: context, calendar: calendar)
    }
}
