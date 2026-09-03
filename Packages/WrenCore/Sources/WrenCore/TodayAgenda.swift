import Foundation

/// A recurring task, decoupled from SwiftData.
public struct TaskSpec: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let schedule: Schedule
    public let completedDueDates: [Date]
    public let isActive: Bool

    public init(id: UUID, schedule: Schedule, completedDueDates: [Date] = [], isActive: Bool = true) {
        self.id = id
        self.schedule = schedule
        self.completedDueDates = completedDueDates
        self.isActive = isActive
    }
}

/// One thing on the agenda, from any of the three sources.
///
/// Deliberately carries no name or colour: those live on the SwiftData models,
/// and threading them through here would mean duplicating display state into the
/// engine. Callers resolve `sourceID` against their own store.
public struct TodayItem: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case bin, task, bill
    }

    public enum Status: Hashable, Sendable {
        /// Past its date and still not settled. `days` is whole days elapsed.
        case overdue(days: Int)
        case dueToday
        case dueTomorrow
        case upcoming
    }

    public let kind: Kind
    public let sourceID: UUID
    public let date: Date
    public let status: Status
    /// Whether this is something the user can act on from the agenda. Bins are
    /// informational — there is no "done" for a bin, you either put it out or
    /// you didn't — and an automatic bill has nothing to confirm.
    public let isActionable: Bool
    /// Expected amount, for bills only.
    public let amountCents: Int?

    public var isOverdue: Bool {
        if case .overdue = status { return true }
        return false
    }

    public var id: String { "\(kind.rawValue)-\(sourceID.uuidString)-\(date.timeIntervalSince1970)" }
}

/// The screen that makes the app worth opening: bins, tasks and bills unified
/// into one agenda.
///
/// Ordering within a bucket puts overdue first, then by date, then by kind — so
/// a bin night and a task due the same evening always appear in the same order
/// rather than shuffling as data changes.
public struct TodayAgenda: Hashable, Sendable {
    public let overdue: [TodayItem]
    public let today: [TodayItem]
    public let tomorrow: [TodayItem]
    public let laterThisWeek: [TodayItem]

    public var isEmpty: Bool {
        overdue.isEmpty && today.isEmpty && tomorrow.isEmpty && laterThisWeek.isEmpty
    }

    /// Things the user could actually clear right now.
    public var actionableCount: Int {
        (overdue + today).filter(\.isActionable).count
    }

    public var allItems: [TodayItem] { overdue + today + tomorrow + laterThisWeek }

    public init(overdue: [TodayItem], today: [TodayItem], tomorrow: [TodayItem], laterThisWeek: [TodayItem]) {
        self.overdue = overdue
        self.today = today
        self.tomorrow = tomorrow
        self.laterThisWeek = laterThisWeek
    }

    /// How far back to look for things left undone. Matches TaskEngine, so a
    /// task and a bill of the same age are treated alike.
    public static let lookbackDays = TaskEngine.defaultLookbackDays
    /// "Later this week" horizon, counted from today.
    public static let upcomingDays = 7

    public static func build(
        bins: [BinSchedule],
        tasks: [TaskSpec],
        bills: [BillSpec],
        payments: [BillPaymentRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayAgenda {
        let startOfToday = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: upcomingDays, to: startOfToday) ?? now
        let lookback = calendar.date(byAdding: .day, value: -lookbackDays, to: startOfToday) ?? now

        var items: [TodayItem] = []
        items += binItems(bins, from: startOfToday, to: horizon, now: now, calendar: calendar)
        items += taskItems(tasks, horizon: horizon, now: now, calendar: calendar)
        items += billItems(bills, payments: payments, lookback: lookback, horizon: horizon, now: now, calendar: calendar)

        return TodayAgenda(
            overdue: sorted(items.filter(\.isOverdue)),
            today: sorted(items.filter { $0.status == .dueToday }),
            tomorrow: sorted(items.filter { $0.status == .dueTomorrow }),
            laterThisWeek: sorted(items.filter { $0.status == .upcoming })
        )
    }

    // MARK: - Sources

    /// Bins are never overdue — the collection either happened or it didn't, and
    /// there is nothing to settle afterwards. So they only look forward.
    private static func binItems(
        _ bins: [BinSchedule],
        from: Date,
        to: Date,
        now: Date,
        calendar: Calendar
    ) -> [TodayItem] {
        bins.flatMap { bin in
            ScheduleEngine.occurrences(bin.schedule, from: from, to: to, calendar: calendar)
                .map { date in
                    TodayItem(
                        kind: .bin,
                        sourceID: bin.id,
                        date: date,
                        status: status(for: date, now: now, calendar: calendar) ?? .dueToday,
                        isActionable: false,
                        amountCents: nil
                    )
                }
        }
    }

    private static func taskItems(
        _ tasks: [TaskSpec],
        horizon: Date,
        now: Date,
        calendar: Calendar
    ) -> [TodayItem] {
        tasks.filter(\.isActive).flatMap { task -> [TodayItem] in
            let state = TaskEngine.state(
                schedule: task.schedule,
                completedDueDates: task.completedDueDates,
                now: now,
                lookbackDays: lookbackDays,
                calendar: calendar
            )

            var result = state.overdue.map { date in
                TodayItem(
                    kind: .task,
                    sourceID: task.id,
                    date: date,
                    status: .overdue(days: elapsedDays(from: date, to: now, calendar: calendar)),
                    isActionable: true,
                    amountCents: nil
                )
            }

            // Only the next outstanding occurrence is worth showing forward — a
            // weekly task would otherwise fill the week with itself — and one
            // ticked off early must drop out, or the tick looks like it did
            // nothing.
            let next = TaskEngine.outstanding(
                schedule: task.schedule,
                completedDueDates: task.completedDueDates,
                from: now,
                to: horizon,
                calendar: calendar
            ).first
            if let next, let status = status(for: next, now: now, calendar: calendar) {
                result.append(
                    TodayItem(kind: .task, sourceID: task.id, date: next, status: status, isActionable: true, amountCents: nil)
                )
            }
            return result
        }
    }

    private static func billItems(
        _ bills: [BillSpec],
        payments: [BillPaymentRecord],
        lookback: Date,
        horizon: Date,
        now: Date,
        calendar: Calendar
    ) -> [TodayItem] {
        BillReports.occurrences(
            bills: bills,
            payments: payments,
            from: lookback,
            to: horizon,
            now: now,
            calendar: calendar
        )
        .compactMap { occurrence -> TodayItem? in
            // Settled is settled, whether recorded or assumed — an automatic
            // debit must never resurface as something to chase.
            guard !occurrence.isSettled else { return nil }

            let itemStatus: TodayItem.Status
            if let ahead = status(for: occurrence.dueDate, now: now, calendar: calendar) {
                itemStatus = ahead
            } else {
                itemStatus = .overdue(days: elapsedDays(from: occurrence.dueDate, to: now, calendar: calendar))
            }

            return TodayItem(
                kind: .bill,
                sourceID: occurrence.billID,
                date: occurrence.dueDate,
                status: itemStatus,
                isActionable: true,
                amountCents: occurrence.expectedCents
            )
        }
    }

    // MARK: - Helpers

    /// Bucket for a date at or after today, or nil when it is in the past.
    private static func status(for date: Date, now: Date, calendar: Calendar) -> TodayItem.Status? {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)

        if day < today { return nil }
        if calendar.isDate(day, inSameDayAs: today) { return .dueToday }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return .dueTomorrow
        }
        return .upcoming
    }

    private static func elapsedDays(from date: Date, to now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
    }

    /// Stable order: date, then kind, then id — so equal-dated items never
    /// shuffle between renders.
    private static func sorted(_ items: [TodayItem]) -> [TodayItem] {
        items.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.kind != $1.kind { return kindOrder($0.kind) < kindOrder($1.kind) }
            return $0.sourceID.uuidString < $1.sourceID.uuidString
        }
    }

    /// Bins first on a shared evening: a bin night has a hard deadline, a task
    /// usually doesn't.
    private static func kindOrder(_ kind: TodayItem.Kind) -> Int {
        switch kind {
        case .bin: return 0
        case .task: return 1
        case .bill: return 2
        }
    }
}
