import Foundation
import UserNotifications
import WrenCore

/// Local notifications only — remote push needs an entitlement the free tier
/// does not grant.
///
/// iOS silently drops pending local requests past 64 per app, so the whole set
/// is rebuilt on foreground rather than scheduled far ahead: cancel everything,
/// re-add the next 30 days. The set is small, so diffing is not worth it, and
/// identifiers are stable which makes rebuilds idempotent anyway.
@MainActor
final class NotificationScheduler: ObservableObject {
    static let shared = NotificationScheduler()

    /// iOS silently drops requests beyond this. Surfaced in Diagnostics.
    static let pendingLimit = 64
    /// Reminders actually scheduled, leaving headroom under the cap for ad-hoc
    /// requests like the test notification.
    static let requestBudget = 56
    /// How far ahead to schedule. Rebuilt on every foreground.
    static let horizonDays = 30

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pending: [UNNotificationRequest] = []
    @Published private(set) var lastRebuild: Date?
    /// Reminders inside the horizon that did not fit under the budget.
    @Published private(set) var droppedAtCap = 0

    private let center = UNUserNotificationCenter.current()
    private let log = Logger.shared

    private init() {}

    // MARK: - Permission

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        log.debug("notif", "authorization status: \(settings.authorizationStatus.wrenLabel)")
    }

    /// Requested on first meaningful use — adding the first bin or task — not at launch.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            log.info("notif", "authorization request granted=\(granted)")
            await refreshAuthorizationStatus()
            return granted
        } catch {
            log.error("notif", "authorization request failed: \(error.localizedDescription)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    private var canSchedule: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Planning

    /// One reminder, ready to schedule. Sources are planned into a single list so
    /// the budget is shared soonest-first rather than carved into per-type
    /// buckets that starve each other.
    private struct PlannedReminder {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
        /// Set only on the morning brief, which is the one reminder that knows
        /// what the whole day holds and so can correct the badge overnight.
        var badge: Int?
    }

    /// Cancels every pending request and re-adds the next `horizonDays` of
    /// reminders across every source. Safe to call on every foreground.
    func rebuild(
        bins: [BinCollection],
        tasks: [RecurringTask],
        bills: [Bill] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        await refreshAuthorizationStatus()
        guard canSchedule else {
            log.warn("notif", "rebuild skipped — status \(authorizationStatus.wrenLabel)")
            await refreshPending()
            return
        }

        guard let horizon = calendar.date(byAdding: .day, value: Self.horizonDays, to: now) else { return }

        var planned = plannedBinReminders(bins, now: now, horizon: horizon, calendar: calendar)
        planned += plannedTaskReminders(tasks, now: now, horizon: horizon, calendar: calendar)
        planned += plannedMorningBriefs(bins: bins, tasks: tasks, bills: bills, now: now, calendar: calendar)
        planned.sort { $0.fireDate < $1.fireDate }

        // Soonest wins if we are over budget — a reminder four weeks out matters
        // far less than tomorrow's, and the next rebuild will pick it up.
        let kept = planned.prefix(Self.requestBudget)
        droppedAtCap = planned.count - kept.count

        center.removeAllPendingNotificationRequests()

        var added = 0
        for reminder in kept {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            if let badge = reminder.badge {
                content.badge = NSNumber(value: badge)
            }

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            do {
                try await center.add(request)
                added += 1
            } catch {
                log.error("notif", "failed to schedule \(reminder.identifier): \(error.localizedDescription)")
            }
        }

        await setBadge(to: agenda(bins: bins, tasks: tasks, bills: bills, at: now, calendar: calendar).actionableCount)

        lastRebuild = Date()
        log.info(
            "notif",
            "rebuilt \(added) reminder(s) over \(Self.horizonDays)d — \(bins.count) bin(s), \(tasks.count) task(s), \(bills.count) bill(s)"
        )
        if droppedAtCap > 0 {
            log.warn("notif", "\(droppedAtCap) reminder(s) beyond the \(Self.requestBudget)-request budget were not scheduled")
        }
        await refreshPending()
    }

    private func plannedBinReminders(
        _ bins: [BinCollection],
        now: Date,
        horizon: Date,
        calendar: Calendar
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []

        for bin in bins where bin.isActive {
            guard let schedule = bin.schedule else {
                log.warn("notif", "bin '\(bin.name)' has no usable schedule — skipped")
                continue
            }

            for collection in ScheduleEngine.occurrences(schedule, from: now, to: horizon, calendar: calendar) {
                guard let fireDate = calendar.date(byAdding: .hour, value: -bin.reminderHoursBefore, to: collection),
                      // A reminder whose moment has passed is not worth
                      // scheduling, even though the collection is still ahead.
                      fireDate > now
                else { continue }

                planned.append(PlannedReminder(
                    identifier: Self.binIdentifier(binID: bin.binID, collection: collection),
                    fireDate: fireDate,
                    title: bin.name.isEmpty ? "Bin night" : bin.name,
                    body: Self.binBody(for: collection, calendar: calendar)
                ))
            }
        }
        return planned
    }

    private func plannedTaskReminders(
        _ tasks: [RecurringTask],
        now: Date,
        horizon: Date,
        calendar: Calendar
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []

        for task in tasks where task.isActive {
            guard let schedule = task.schedule else {
                log.warn("notif", "task '\(task.title)' has no usable schedule — skipped")
                continue
            }

            // Already-completed occurrences are excluded, so a task you have
            // done ahead of time does not nag.
            let outstanding = TaskEngine.outstanding(
                schedule: schedule,
                completedDueDates: task.completedDueDates,
                from: now,
                to: horizon,
                calendar: calendar
            )

            for due in outstanding {
                guard let fireDate = calendar.date(byAdding: .minute, value: -task.reminderMinutesBefore, to: due),
                      fireDate > now
                else { continue }

                planned.append(PlannedReminder(
                    identifier: Self.taskIdentifier(taskID: task.taskID, due: due),
                    fireDate: fireDate,
                    title: task.title.isEmpty ? "Task" : task.title,
                    body: Self.taskBody(for: due, notes: task.notes, calendar: calendar)
                ))
            }
        }
        return planned
    }

    // MARK: - Identifiers

    /// Stable and idempotent: the same source and occurrence always produce the
    /// same identifier, so rebuilding cannot duplicate a reminder.
    // MARK: - Morning brief

    /// One notification per morning, each naming what that particular day
    /// holds. Three reminders at six in the evening are three things to swipe
    /// away; one sentence at breakfast is a thing you read.
    ///
    /// A day with nothing on it is skipped rather than sent as "nothing on".
    /// A brief that is sometimes absent stays worth reading; one that arrives
    /// empty teaches you to ignore it.
    private func plannedMorningBriefs(
        bins: [BinCollection],
        tasks: [RecurringTask],
        bills: [Bill],
        now: Date,
        calendar: Calendar
    ) -> [PlannedReminder] {
        guard MorningBrief.isEnabled else { return [] }

        let minutes = MorningBrief.minutesFromMidnight
        let hasAnythingSetUp = !(bins.isEmpty && tasks.isEmpty && bills.isEmpty)
        guard hasAnythingSetUp else { return [] }

        return (0..<MorningBrief.horizonDays).compactMap { offset -> PlannedReminder? in
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: now),
                let fireDate = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                fireDate > now
            else { return nil }

            // Built as of that morning, so the sentence describes the day the
            // reader is actually waking up to.
            let dayAgenda = agenda(bins: bins, tasks: tasks, bills: bills, at: fireDate, calendar: calendar)
            guard !dayAgenda.isEmpty else { return nil }

            let summary = TodaySummary.make(for: dayAgenda, hasAnythingSetUp: true)
            return PlannedReminder(
                identifier: MorningBrief.identifier(for: fireDate, calendar: calendar),
                fireDate: fireDate,
                title: fireDate.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                body: summary.text,
                badge: dayAgenda.actionableCount
            )
        }
    }

    private func agenda(
        bins: [BinCollection],
        tasks: [RecurringTask],
        bills: [Bill],
        at date: Date,
        calendar: Calendar
    ) -> TodayAgenda {
        TodayAgenda.build(
            bins: bins.filter(\.isActive).compactMap(\.binSchedule),
            tasks: tasks.compactMap { task in
                task.schedule.map {
                    TaskSpec(
                        id: task.taskID,
                        schedule: $0,
                        completedDueDates: task.completedDueDates,
                        isActive: task.isActive
                    )
                }
            },
            bills: bills.compactMap(\.spec),
            payments: bills.flatMap(\.paymentRecords),
            now: date,
            calendar: calendar
        )
    }

    // MARK: - Badge

    /// The count of things that can actually be cleared right now. Bins are
    /// excluded by `actionableCount` — there is no "done" for a bin, so
    /// badging one would be a number you cannot make go away.
    private func setBadge(to count: Int) async {
        do {
            try await center.setBadgeCount(count)
        } catch {
            log.error("notif", "badge update failed: \(error.localizedDescription)")
        }
    }

    static func binIdentifier(binID: UUID, collection: Date) -> String {
        "bin-\(binID.uuidString)-\(ISO8601DateFormatter().string(from: collection))"
    }

    static func taskIdentifier(taskID: UUID, due: Date) -> String {
        "task-\(taskID.uuidString)-\(ISO8601DateFormatter().string(from: due))"
    }

    // MARK: - Copy

    private static func binBody(for collection: Date, calendar: Calendar) -> String {
        let time = collection.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(collection) {
            return "Goes out today — collected at \(time)."
        }
        if calendar.isDateInTomorrow(collection) {
            return "Out tonight — collected tomorrow at \(time)."
        }
        let day = collection.formatted(.dateTime.weekday(.wide))
        return "Out before \(day), collected at \(time)."
    }

    private static func taskBody(for due: Date, notes: String, calendar: Calendar) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }

        if calendar.isDateInToday(due) {
            return "Due today at \(due.formatted(date: .omitted, time: .shortened))."
        }
        if calendar.isDateInTomorrow(due) {
            return "Due tomorrow at \(due.formatted(date: .omitted, time: .shortened))."
        }
        return "Due \(due.formatted(.dateTime.weekday(.wide).day().month()))."
    }

    // MARK: - Inspection

    func refreshPending() async {
        pending = await center.pendingNotificationRequests()
        log.debug("notif", "pending requests: \(pending.count)")
        if pending.count >= Self.pendingLimit {
            log.warn("notif", "pending at or over the \(Self.pendingLimit)-request cap — iOS will drop new requests")
        }
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        droppedAtCap = 0
        log.info("notif", "cancelled all pending requests")
        await refreshPending()
    }

    /// Kept from Phase 0. Still the fastest way to prove notifications work on a
    /// freshly re-signed build, which happens every seven days.
    func scheduleTestNotification(after seconds: TimeInterval = 60) async {
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        guard canSchedule else {
            log.warn("notif", "test notification skipped — status \(authorizationStatus.wrenLabel)")
            return
        }

        let fireDate = Date().addingTimeInterval(seconds)
        let content = UNMutableNotificationContent()
        content.title = "Wren"
        content.body = "Pipeline test — this fired \(Int(seconds))s after you tapped."
        content.sound = .default

        let id = "test-\(ISO8601DateFormatter().string(from: fireDate))"
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: id,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
                )
            )
            log.info("notif", "scheduled \(id)")
        } catch {
            log.error("notif", "failed to schedule \(id): \(error.localizedDescription)")
        }
        await refreshPending()
    }
}

extension UNAuthorizationStatus {
    var wrenLabel: String {
        switch self {
        case .notDetermined: return "not determined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
}

extension UNNotificationRequest {
    /// Best-effort fire date for the Diagnostics list.
    var wrenFireDate: Date? {
        switch trigger {
        case let interval as UNTimeIntervalNotificationTrigger:
            return interval.nextTriggerDate()
        case let calendarTrigger as UNCalendarNotificationTrigger:
            return calendarTrigger.nextTriggerDate()
        default:
            return nil
        }
    }
}
