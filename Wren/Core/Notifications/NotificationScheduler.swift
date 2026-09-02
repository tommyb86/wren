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
    /// Headroom under the cap for tasks and bills in later phases.
    static let binRequestBudget = 40
    /// How far ahead to schedule. Rebuilt on every foreground.
    static let horizonDays = 30

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pending: [UNNotificationRequest] = []
    @Published private(set) var lastRebuild: Date?
    /// Occurrences inside the horizon that did not fit under the budget.
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

    /// Requested on first meaningful use — adding the first bin — not at launch.
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

    // MARK: - Bin reminders

    /// Cancels every pending request and re-adds the next `horizonDays` of bin
    /// reminders. Safe to call on every foreground.
    func rebuild(
        bins: [BinCollection],
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

        var planned: [(id: String, fireDate: Date, bin: BinCollection, collection: Date)] = []

        for bin in bins where bin.isActive {
            guard let schedule = bin.schedule else {
                log.warn("notif", "bin '\(bin.name)' has no usable schedule — skipped")
                continue
            }

            for collection in ScheduleEngine.occurrences(schedule, from: now, to: horizon, calendar: calendar) {
                guard let fireDate = calendar.date(
                    byAdding: .hour,
                    value: -bin.reminderHoursBefore,
                    to: collection
                ) else { continue }

                // A reminder whose moment has passed is not worth scheduling,
                // even though the collection itself is still ahead.
                guard fireDate > now else { continue }

                planned.append((
                    id: Self.identifier(binID: bin.binID, collection: collection),
                    fireDate: fireDate,
                    bin: bin,
                    collection: collection
                ))
            }
        }

        planned.sort { $0.fireDate < $1.fireDate }

        // Soonest wins if we are over budget — a reminder four weeks out matters
        // far less than tomorrow's, and the next rebuild will pick it up.
        let kept = planned.prefix(Self.binRequestBudget)
        droppedAtCap = planned.count - kept.count

        center.removeAllPendingNotificationRequests()

        var added = 0
        for item in kept {
            let content = UNMutableNotificationContent()
            content.title = item.bin.name.isEmpty ? "Bin night" : item.bin.name
            content.body = Self.body(for: item.collection, calendar: calendar)
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let request = UNNotificationRequest(
                identifier: item.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            do {
                try await center.add(request)
                added += 1
            } catch {
                log.error("notif", "failed to schedule \(item.id): \(error.localizedDescription)")
            }
        }

        lastRebuild = Date()
        log.info("notif", "rebuilt \(added) bin reminder(s) over \(Self.horizonDays)d from \(bins.count) bin(s)")
        if droppedAtCap > 0 {
            log.warn("notif", "\(droppedAtCap) reminder(s) beyond the \(Self.binRequestBudget)-request budget were not scheduled")
        }
        await refreshPending()
    }

    /// Stable and idempotent: the same bin and collection always produce the
    /// same identifier, so rebuilding cannot duplicate a reminder.
    static func identifier(binID: UUID, collection: Date) -> String {
        "bin-\(binID.uuidString)-\(ISO8601DateFormatter().string(from: collection))"
    }

    private static func body(for collection: Date, calendar: Calendar) -> String {
        let time = collection.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInTomorrow(collection) {
            return "Out tonight — collected tomorrow at \(time)."
        }
        if calendar.isDateInToday(collection) {
            return "Collected today at \(time)."
        }
        let day = collection.formatted(.dateTime.weekday(.wide))
        return "Out before \(day), collected at \(time)."
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
