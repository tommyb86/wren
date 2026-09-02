import Foundation

/// One bin's collection in a cycle.
public struct BinDue: Hashable, Sendable, Identifiable {
    public let binID: UUID
    public let date: Date

    /// Composite, because one bin can legitimately appear twice in a cycle.
    public var id: String { "\(binID.uuidString)-\(date.timeIntervalSince1970)" }

    public init(binID: UUID, date: Date) {
        self.binID = binID
        self.date = date
    }
}

/// A bin and its schedule, decoupled from SwiftData so the read model below is
/// testable without a model container.
public struct BinSchedule: Hashable, Sendable {
    public let id: UUID
    public let schedule: Schedule

    public init(id: UUID, schedule: Schedule) {
        self.id = id
        self.schedule = schedule
    }
}

/// The dashboard has to answer **"what bin week is it?"** at a glance, so bins
/// are a read model derived from the engine, not just a notification trigger.
///
/// The cycle is the calendar week containing the reference date — which is what
/// "recycling week" means to a household.
public struct BinCycle: Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let due: [BinDue]

    public var isEmpty: Bool { due.isEmpty }

    /// Distinct collection nights in the cycle, ascending. Multiple bins on one
    /// night collapse to a single entry — that is what the card stacks chips for.
    public var nights: [Date] {
        var seen = Set<Date>()
        return due.map(\.date).filter { seen.insert($0).inserted }.sorted()
    }

    public init(start: Date, end: Date, due: [BinDue]) {
        self.start = start
        self.end = end
        self.due = due
    }

    /// Bins due in the week containing `now`.
    public static func current(
        schedules: [BinSchedule],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BinCycle {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return BinCycle(start: now, end: now, due: [])
        }
        // `dateInterval.end` is the exclusive start of the next week; step back so
        // range comparisons stay inclusive.
        let end = week.end.addingTimeInterval(-1)
        return BinCycle(start: week.start, end: end, due: dues(schedules, from: week.start, to: end, calendar: calendar))
    }

    /// Bins due in an arbitrary window — used by the Today screen later.
    public static func window(
        schedules: [BinSchedule],
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> BinCycle {
        BinCycle(start: from, end: to, due: dues(schedules, from: from, to: to, calendar: calendar))
    }

    private static func dues(
        _ schedules: [BinSchedule],
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> [BinDue] {
        schedules
            .flatMap { bin in
                ScheduleEngine.occurrences(bin.schedule, from: from, to: to, calendar: calendar)
                    .map { BinDue(binID: bin.id, date: $0) }
            }
            .sorted { $0.date < $1.date }
    }
}
