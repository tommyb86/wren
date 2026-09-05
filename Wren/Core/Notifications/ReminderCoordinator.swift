import Foundation
import SwiftData

/// Every place that changes a bin or a task has to rebuild the whole reminder
/// set. This is the one place that knows which sources feed it, so adding bills
/// in Phase 3 is a change here rather than at six call sites.
@MainActor
enum ReminderCoordinator {
    static func rebuild(context: ModelContext, now: Date = Date(), calendar: Calendar = .current) async {
        do {
            let bins = try context.fetch(FetchDescriptor<BinCollection>())
            let tasks = try context.fetch(FetchDescriptor<RecurringTask>())
            // Bills carry no reminders of their own, but the morning brief and
            // the badge both count them, so they are fetched here too.
            let bills = try context.fetch(FetchDescriptor<Bill>())
            await NotificationScheduler.shared.rebuild(
                bins: bins,
                tasks: tasks,
                bills: bills,
                now: now,
                calendar: calendar
            )
        } catch {
            Logger.shared.error("notif", "rebuild fetch failed: \(error.localizedDescription)")
        }
    }

    /// True when nothing has been set up yet, so permission is requested on
    /// first meaningful use rather than at launch.
    static func hasNoSources(context: ModelContext) -> Bool {
        do {
            let bins = try context.fetchCount(FetchDescriptor<BinCollection>())
            let tasks = try context.fetchCount(FetchDescriptor<RecurringTask>())
            return bins + tasks == 0
        } catch {
            return false
        }
    }
}
