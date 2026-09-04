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
            WrenMenuRow(
                label: "Repeats",
                selection: $draft.frequency,
                options: [
                    WrenOption(Schedule.Frequency.once, labels.once),
                    WrenOption(Schedule.Frequency.daily, "Daily"),
                    WrenOption(Schedule.Frequency.weekly, "Weekly"),
                    WrenOption(Schedule.Frequency.monthly, "Monthly"),
                    WrenOption(Schedule.Frequency.yearly, "Yearly")
                ]
            )
            .wrenRow(first: true)

            // A one-off has no interval and no weekday pattern, so those
            // controls would be answering questions nobody asked.
            if !isOnce {
                WrenStepperRow(
                    label: "Every",
                    value: "\(draft.interval) \(intervalLabel)",
                    amount: $draft.interval,
                    range: 1...12
                )
                .wrenRow()
            }

            // With explicit weekdays the anchor's own date is irrelevant — only
            // its time of day is used — so the picker narrows to match.
            WrenDateRow(
                label: anchorLabel,
                date: $draft.anchorDate,
                components: usesWeekdays ? .hourAndMinute : [.date, .hourAndMinute]
            )
            .wrenRow(last: draft.frequency != .weekly)

            if draft.frequency == .weekly {
                weekdayPicker
                    .wrenRow(last: true)
            }
        } header: {
            WrenListHeader(text: "Schedule")
        } footer: {
            WrenListFooter(text: draft.schedule.summary(calendar: calendar))
        }

        // An end date is meaningless on something that happens once.
        if !isOnce {
            Section {
                WrenToggleRow(label: labels.endToggle, isOn: $draft.hasEndDate)
                    .wrenRow(first: true, last: !draft.hasEndDate)
                if draft.hasEndDate {
                    WrenDateRow(label: labels.endDate, date: $draft.endDate, components: .date)
                        .wrenRow(last: true)
                }
            }
        }
    }

    private var isOnce: Bool { draft.frequency == .once }

    private var anchorLabel: String {
        if isOnce { return labels.onceDate }
        return usesWeekdays ? labels.timeOfDay : labels.firstOccurrence
    }

    /// Seven across, lime when the day is on. Selecting none means "use the
    /// anchor's own weekday", which the hint below spells out.
    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            WrenFieldLabel(text: labels.daysHeader)

            HStack(spacing: 5) {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    let isOn = draft.weekdays.contains(weekday)
                    Button {
                        withAnimation(.snappy(duration: 0.12)) {
                            if isOn {
                                draft.weekdays.remove(weekday)
                            } else {
                                draft.weekdays.insert(weekday)
                            }
                        }
                    } label: {
                        Text(shortName(weekday))
                            .font(WrenFont.caption)
                            .foregroundStyle(isOn ? Color.wren.onHighlight : Color.wren.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .wrenBox(radius: Radius.chip, fill: isOn ? .wren.highlight : .wren.surface)
                            .wrenHardShadow(radius: Radius.chip, isLifted: isOn)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(fullName(weekday))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }

            Text(draft.weekdays.isEmpty
                 ? "None selected — the \(labels.firstOccurrenceInline)'s own weekday is used."
                 : "Overrides the \(labels.firstOccurrenceInline)'s weekday.")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(.vertical, Space.s)
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

    private func fullName(_ weekday: Int) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : "Day"
    }
}
