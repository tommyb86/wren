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
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var reminderOptions: [WrenOption<Int>] {
        [1, 2, 3, 12, 14, 16, 24].map { WrenOption($0, reminderLabel($0)) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WrenTextRow(label: "Name", text: $name, placeholder: "General waste")
                        .wrenRow(first: true)
                    lidPicker
                        .wrenRow(last: true)
                } header: {
                    WrenListHeader(text: "Bin")
                }

                ScheduleEditor(draft: $draft, calendar: calendar)

                Section {
                    WrenMenuRow(label: "Remind me", selection: $reminderHoursBefore, options: reminderOptions)
                        .wrenRow(first: true)
                    WrenToggleRow(label: "Active", isOn: $isActive)
                        .wrenRow(last: true)
                } header: {
                    WrenListHeader(text: "Reminder")
                } footer: {
                    WrenListFooter(text: previewFooter)
                }

                if isEditing {
                    Section {
                        Button("Delete bin", action: delete)
                            .buttonStyle(WrenDestructiveButtonStyle())
                            .listRowInsets(EdgeInsets(top: Space.l, leading: Space.l, bottom: Space.s, trailing: Space.l))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .wrenListStyle()
            .navigationTitle(isEditing ? "Edit bin" : "Add bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(WrenFont.value)
                        .foregroundStyle(Color.wren.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        WrenToolbarButton(title: "Save", isEnabled: canSave)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .task { load() }
        }
    }

    /// Lids are squares here like everywhere else in the app, so a colour reads
    /// as the physical object rather than as a status dot.
    private var lidPicker: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            WrenFieldLabel(text: "Lid colour")

            HStack(spacing: Space.s) {
                ForEach(BinLid.allCases) { lid in
                    let isOn = lidHex == lid.rawValue
                    Button {
                        withAnimation(.snappy(duration: 0.12)) {
                            lidHex = lid.rawValue
                            if name.isEmpty { name = lid.suggestedName }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(lid.color)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                    .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
                            )
                            .wrenHardShadow(radius: Radius.chip, isLifted: isOn)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lid.label)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, Space.s)
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
