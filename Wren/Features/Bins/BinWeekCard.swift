import SwiftUI
import WrenCore

/// The dashboard's answer to "what bin week is it?" — the question this app
/// exists to answer at a glance.
@MainActor
struct BinWeekCard: View {
    let bins: [BinCollection]
    var now: Date = Date()
    var calendar: Calendar = .current

    private var activeBins: [BinCollection] { bins.filter(\.isActive) }

    private var cycle: BinCycle {
        BinCycle.current(
            schedules: activeBins.compactMap(\.binSchedule),
            now: now,
            calendar: calendar
        )
    }

    /// Next collection at or after now, across all bins.
    private var upcoming: (date: Date, bins: [BinCollection])? {
        let futureNights = cycle.due.filter { $0.date >= now }.map(\.date)
        // The cycle ends on Saturday, so late in the week look past it.
        let night: Date? = futureNights.min() ?? activeBins.compactMap { $0.nextCollection(after: now, calendar: calendar) }.min()
        guard let night else { return nil }
        return (night, bins(on: night))
    }

    private func bins(on night: Date) -> [BinCollection] {
        activeBins.filter { bin in
            guard let next = bin.schedule.flatMap({
                ScheduleEngine.occurrences($0, from: night.addingTimeInterval(-60), to: night, calendar: calendar).first
            }) else { return false }
            return next == night
        }
    }

    /// "Recycling week" reads better than "Bin week", so the headline names the
    /// bin that makes this week distinctive — the one that isn't out every week.
    private var headline: String {
        guard let upcoming else { return "No collections scheduled" }
        let distinctive = upcoming.bins.first { ($0.schedule?.effectiveInterval ?? 1) > 1 }
        if let distinctive, !distinctive.name.isEmpty {
            return "\(distinctive.name) week"
        }
        if let first = upcoming.bins.first, !first.name.isEmpty {
            return "\(first.name) week"
        }
        return "Bin week"
    }

    private var accent: Color {
        guard let bin = upcoming?.bins.first(where: { ($0.schedule?.effectiveInterval ?? 1) > 1 }) ?? upcoming?.bins.first
        else { return .wren.accent }
        return Color(binHex: bin.colorHex)
    }

    var body: some View {
        WrenCard {
            if activeBins.isEmpty {
                emptyState
            } else if let upcoming {
                content(night: upcoming.date, bins: upcoming.bins)
            } else {
                Text("No collections scheduled")
                    .font(.headline)
                    .foregroundStyle(Color.wren.textPrimary)
            }
        }
        .overlay(alignment: .leading) {
            // Lid colour as the card accent.
            if !activeBins.isEmpty {
                Rectangle()
                    .fill(accent)
                    .frame(width: 4)
                    .clipShape(.rect(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("No bins yet")
                .font(.headline)
                .foregroundStyle(Color.wren.textPrimary)
            Text("Add your council's collection days and Wren will remind you the evening before.")
                .font(.subheadline)
                .foregroundStyle(Color.wren.textSecondary)
        }
    }

    private func content(night: Date, bins nightBins: [BinCollection]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(headline)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color.wren.textPrimary)

            HStack(spacing: Space.s) {
                ForEach(nightBins) { bin in
                    HStack(spacing: Space.xs) {
                        Circle()
                            .fill(Color(binHex: bin.colorHex))
                            .frame(width: 10, height: 10)
                        Text(bin.name.isEmpty ? "Bin" : bin.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.wren.textPrimary)
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(Color.wren.accentSoft, in: RoundedRectangle(cornerRadius: Radius.chip))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(night.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Text(countdown(to: night))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(isOverdueSoon(night) ? Color.wren.alert : Color.wren.textSecondary)
            }
        }
    }

    private func countdown(to night: Date) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfNight = calendar.startOfDay(for: night)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfNight).day ?? 0

        switch days {
        case ..<0: return "Was \(-days) day\(-days == 1 ? "" : "s") ago"
        case 0: return "Tonight, \(night.formatted(date: .omitted, time: .shortened))"
        case 1: return "Tomorrow, \(night.formatted(date: .omitted, time: .shortened))"
        default: return "In \(days) days"
        }
    }

    /// Terracotta means something, so it only appears when the bin goes out today.
    private func isOverdueSoon(_ night: Date) -> Bool {
        calendar.isDateInToday(night)
    }
}
