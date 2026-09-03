import SwiftUI
import WrenCore

/// The dashboard's answer to "what bin week is it?", reduced to a headline and
/// a line of detail so it can sit in a tile rather than own a card.
struct BinWeekSummary {
    let headline: String
    let detail: String
    /// Lid colour of the bin that makes the week distinctive, for the swatch.
    let swatch: Color?

    init(bins: [BinCollection], now: Date = Date(), calendar: Calendar = .current) {
        let active = bins.filter(\.isActive)
        guard !active.isEmpty else {
            self.init(headline: bins.isEmpty ? "No bins yet" : "All paused", detail: bins.isEmpty ? "Add one" : "Nothing scheduled", swatch: nil)
            return
        }

        let cycle = BinCycle.current(schedules: active.compactMap(\.binSchedule), now: now, calendar: calendar)
        let futureNights = cycle.due.filter { $0.date >= now }.map(\.date)
        // The cycle ends on Saturday, so late in the week look past it.
        let night = futureNights.min()
            ?? active.compactMap { $0.nextCollection(after: now, calendar: calendar) }.min()

        guard let night else {
            self.init(headline: "No collections", detail: "Nothing scheduled", swatch: nil)
            return
        }

        let nightBins = active.filter { bin in
            guard let schedule = bin.schedule else { return false }
            return ScheduleEngine.occurrences(schedule, from: night.addingTimeInterval(-60), to: night, calendar: calendar).first == night
        }

        // "Recycling week" reads better than "Bin week", so the headline names
        // the bin that makes this week distinctive — the one that isn't out
        // every week.
        let distinctive = nightBins.first { ($0.schedule?.effectiveInterval ?? 1) > 1 } ?? nightBins.first
        let name = distinctive.map { $0.name.isEmpty ? "Bin" : $0.name } ?? "Bin"

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: night)
        ).day ?? 0
        let detail: String
        switch days {
        case ..<1: detail = "collected today"
        case 1: detail = "out tonight"
        default: detail = "from \(night.formatted(.dateTime.weekday(.wide).day()))"
        }

        self.init(headline: "\(name) week", detail: detail, swatch: distinctive.map { Color(binHex: $0.colorHex) })
    }

    private init(headline: String, detail: String, swatch: Color?) {
        self.headline = headline
        self.detail = detail
        self.swatch = swatch
    }
}
