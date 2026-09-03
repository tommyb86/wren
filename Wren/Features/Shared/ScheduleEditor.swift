import SwiftUI
import WrenCore

/// Draft state for a schedule, so the editor can be cancelled without touching
/// the model.
struct ScheduleDraft {
    var frequency: Schedule.Frequency = .weekly
    var interval: Int = 1
    var anchorDate: Date = Date()
    var weekdays: Set<Int> = []
    var hasEndDate: Bool = false
    var endDate: Date = Date()

    init() {}

    init(_ schedule: Schedule) {
        frequency = schedule.frequency
        interval = schedule.effectiveInterval
        anchorDate = schedule.anchorDate
        weekdays = schedule.weekdays
        hasEndDate = schedule.endDate != nil
        endDate = schedule.endDate ?? schedule.anchorDate
    }

    var schedule: Schedule {
        Schedule(
            frequency: frequency,
            interval: interval,
            anchorDate: anchorDate,
            weekdays: frequency == .weekly ? weekdays : [],
            // A stale end date left over from another frequency would silently
            // suppress the one occurrence a reminder has.
            endDate: (frequency != .once && hasEndDate) ? endDate : nil
        )
    }
}

@MainActor
struct ScheduleEditor: View {
    /// The editor is shared by bins and tasks, which don't share vocabulary — a
    /// task has no "collection date". Each consumer supplies its own nouns.
    struct Labels {
        let firstOccurrence: String
        let timeOfDay: String
        let daysHeader: String
        let endToggle: String
        let endDate: String
        /// Lower-case form for mid-sentence use in the weekday hint.
        let firstOccurrenceInline: String
        /// Picker row for a schedule that fires once.
        let once: String
        /// Date picker label when it fires once.
        let onceDate: String

        static let bins = Labels(
            firstOccurrence: "First collection",
            timeOfDay: "Put out at",
            daysHeader: "Collection days",
            endToggle: "Stops on a date",
            endDate: "Last collection",
            firstOccurrenceInline: "first collection",
            once: "One collection only",
            onceDate: "Collection date"
        )

        static let bills = Labels(
            firstOccurrence: "First bill",
            timeOfDay: "Due at",
            daysHeader: "Billed on these days",
            endToggle: "Ends on a date",
            endDate: "Last bill",
            firstOccurrenceInline: "first bill",
            once: "One-off",
            onceDate: "Bill date"
        )

        static let tasks = Labels(
            firstOccurrence: "First due",
            timeOfDay: "Due at",
            daysHeader: "Due on these days",
            endToggle: "Stops on a date",
            endDate: "Last one due",
            firstOccurrenceInline: "first due date",
            once: "Once — a reminder",
            onceDate: "Remind me at"
        )
    }

    @Binding var draft: ScheduleDraft
    var labels: Labels = .bins
    var calendar: Calendar = .current

    private var usesWeekdays: Bool {
        draft.frequency == .weekly && !draft.weekdays.isEmpty
    }

    private var intervalLabel: String {
        switch draft.frequency {
        case .once: return ""
        case .daily: return draft.interval == 1 ? "day" : "days"
        case .weekly: return draft.interval == 1 ? "week" : "weeks"
        case .monthly: return draft.interval == 1 ? "month" : "months"
        case .yearly: return draft.interval == 1 ? "year" : "years"
        }
    }

    var body: some View {
        Section {
            Picker("Repeats", selection: $draft.frequency) {
                Text(labels.once).tag(Schedule.Frequency.once)
                Text("Daily").tag(Schedule.Frequency.daily)
                Text("Weekly").tag(Schedule.Frequency.weekly)
                Text("Monthly").tag(Schedule.Frequency.monthly)
                Text("Yearly").tag(Schedule.Frequency.yearly)
            }

            // A one-off has no interval and no weekday pattern, so those
            // controls would be answering questions nobody asked.
            if !isOnce {
                Stepper(value: $draft.interval, in: 1...12) {
                    HStack {
                        Text("Every")
                        Spacer()
                        Text("\(draft.interval) \(intervalLabel)")
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                }
            }

            // With explicit weekdays the anchor's own date is irrelevant — only
            // its time of day is used — so the picker narrows to match.
            DatePicker(
                anchorLabel,
                selection: $draft.anchorDate,
                displayedComponents: usesWeekdays ? .hourAndMinute : [.date, .hourAndMinute]
            )

            if draft.frequency == .weekly {
                weekdayPicker
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text(draft.schedule.summary(calendar: calendar))
        }

        // An end date is meaningless on something that happens once.
        if !isOnce {
            Section {
                Toggle(labels.endToggle, isOn: $draft.hasEndDate)
                if draft.hasEndDate {
                    DatePicker(labels.endDate, selection: $draft.endDate, displayedComponents: .date)
                }
            }
        }
    }

    private var isOnce: Bool { draft.frequency == .once }

    private var anchorLabel: String {
        if isOnce { return labels.onceDate }
        return usesWeekdays ? labels.timeOfDay : labels.firstOccurrence
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(labels.daysHeader)
                .font(.subheadline)
                .foregroundStyle(Color.wren.textSecondary)

            HStack(spacing: Space.xs) {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    let isOn = draft.weekdays.contains(weekday)
                    Button {
                        if isOn {
                            draft.weekdays.remove(weekday)
                        } else {
                            draft.weekdays.insert(weekday)
                        }
                    } label: {
                        Text(shortName(weekday))
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s)
                            .background(
                                isOn ? Color.wren.accent : Color.wren.accentSoft,
                                in: RoundedRectangle(cornerRadius: Radius.chip)
                            )
                            .foregroundStyle(isOn ? Color.wren.surface : Color.wren.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(draft.weekdays.isEmpty
                 ? "None selected — the \(labels.firstOccurrenceInline)'s own weekday is used."
                 : "Overrides the \(labels.firstOccurrenceInline)'s weekday.")
                .font(.caption)
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(.vertical, Space.xs)
    }

    /// Weekday numbers in the calendar's own display order.
    private var orderedWeekdays: [Int] {
        (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
    }

    private func shortName(_ weekday: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : "?"
    }
}
