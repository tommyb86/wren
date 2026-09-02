import Foundation
import UserNotifications

/// Local notifications only — remote push needs an entitlement the free tier
/// does not grant. iOS caps pending local requests at 64 per app, so from
/// Phase 1 onwards the whole set is rebuilt on foreground rather than
/// scheduled far ahead.
@MainActor
final class NotificationScheduler: ObservableObject {
    static let shared = NotificationScheduler()

    /// iOS silently drops requests beyond this. Surfaced in Diagnostics.
    static let pendingLimit = 64

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pending: [UNNotificationRequest] = []

    private let center = UNUserNotificationCenter.current()
    private let log = Logger.shared

    private init() {}

    // MARK: - Permission

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        log.debug("notif", "authorization status: \(settings.authorizationStatus.wrenLabel)")
    }

    /// Requested on first meaningful use, not at launch.
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

    // MARK: - Scheduling

    /// Phase 0's whole reason for existing: prove a local notification fires on
    /// a free-tier signed build.
    func scheduleTestNotification(after seconds: TimeInterval = 60) async {
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            log.warn("notif", "test notification skipped — status \(authorizationStatus.wrenLabel)")
            return
        }

        let fireDate = Date().addingTimeInterval(seconds)
        let content = UNMutableNotificationContent()
        content.title = "Wren"
        content.body = "Pipeline test — this fired \(Int(seconds))s after you tapped."
        content.sound = .default

        let id = "test-\(ISO8601DateFormatter().string(from: fireDate))"
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        do {
            try await center.add(request)
            log.info("notif", "scheduled \(id) for \(Entry.stamp(fireDate))")
        } catch {
            log.error("notif", "failed to schedule \(id): \(error.localizedDescription)")
        }
        await refreshPending()
    }

    func refreshPending() async {
        pending = await center.pendingNotificationRequests()
        log.debug("notif", "pending requests: \(pending.count)")
        if pending.count >= Self.pendingLimit {
            log.warn("notif", "pending at or over the 64-request cap — iOS will drop new requests")
        }
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        log.info("notif", "cancelled all pending requests")
        await refreshPending()
    }

    private enum Entry {
        static func stamp(_ date: Date) -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: date)
        }
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
