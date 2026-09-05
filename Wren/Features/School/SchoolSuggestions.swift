import Foundation
import SwiftData
import WrenCore

/// Turns dated notices into proposed reminders. Runs after a feed refresh:
/// scans recent, relevant notices, extracts future deadlines, and files any it
/// has not seen as a pending `SuggestedDate`. Accepting one creates an ordinary
/// one-off task — so it flows onto Today and into the notification scheduler
/// with no new machinery.
@MainActor
enum SchoolSuggestions {
    /// Rebuilds the pending set from the stored notices. Idempotent: a date
    /// already suggested (in any state) is never re-proposed, so a dismissal
    /// sticks and an accepted one is not duplicated.
    static func rebuild(context: ModelContext, calendar: Calendar = .current) {
        let profile = SchoolConfig.profile
        let notices = (try? context.fetch(FetchDescriptor<SchoolNotice>())) ?? []
        let existing = (try? context.fetch(FetchDescriptor<SuggestedDate>())) ?? []
        var seen = Set(existing.map { key($0.noticeGUID, $0.date, calendar) })

        let cutoff = calendar.date(byAdding: .day, value: -SchoolConfig.maxAgeDays, to: Date()) ?? .distantPast
        let today = calendar.startOfDay(for: Date())
        var added = 0

        for notice in notices where notice.isPinned || notice.published >= cutoff {
            // Only notices that concern him or the whole school — not the noise.
            let match = SchoolRelevance.match(notice.feedItem, profile: profile)
            guard match.bucket != .everythingElse else { continue }

            let published = notice.published == .distantPast ? nil : notice.published
            let deadlines = SchoolDeadlines.extract(fromHTML: notice.bodyHTML, published: published, calendar: calendar)

            for deadline in deadlines {
                guard deadline.date >= today else { continue }   // past dates are not reminders
                let k = key(notice.guid, deadline.date, calendar)
                guard !seen.contains(k) else { continue }
                seen.insert(k)
                context.insert(
                    SuggestedDate(
                        noticeGUID: notice.guid,
                        proposedTitle: cleanedTitle(notice.title),
                        date: deadline.date,
                        evidence: deadline.evidence,
                        confidence: deadline.confidence.rawValue
                    )
                )
                added += 1
            }
        }

        if added > 0 {
            save(context, action: "file \(added) suggested date(s)")
            Logger.shared.info("school", "suggested \(added) new date(s) from notices")
        }
    }

    /// Accepts a suggestion: creates a one-off task at 9am on the day and links
    /// it back, so undo/accounting stays possible.
    @discardableResult
    static func accept(_ suggestion: SuggestedDate, context: ModelContext, calendar: Calendar = .current) -> RecurringTask? {
        let anchor = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: suggestion.date) ?? suggestion.date
        let firstSource = ReminderCoordinator.hasNoSources(context: context)
        let count = (try? context.fetchCount(FetchDescriptor<RecurringTask>())) ?? 0
        let task = RecurringTask(
            title: suggestion.proposedTitle.isEmpty ? "School reminder" : suggestion.proposedTitle,
            notes: suggestion.evidence,
            schedule: Schedule(frequency: .once, anchorDate: anchor),
            reminderMinutesBefore: 0,
            isActive: true,
            sortOrder: count
        )
        context.insert(task)
        suggestion.state = SuggestedDate.State.accepted.rawValue
        suggestion.linkedTaskID = task.taskID
        save(context, action: "accept suggested date")
        Logger.shared.info("school", "accepted '\(task.title)' for \(anchor.formatted(date: .abbreviated, time: .omitted))")

        Task {
            if firstSource { await NotificationScheduler.shared.requestAuthorization() }
            await ReminderCoordinator.rebuild(context: context, calendar: calendar)
        }
        return task
    }

    static func dismiss(_ suggestion: SuggestedDate, context: ModelContext) {
        suggestion.state = SuggestedDate.State.dismissed.rawValue
        save(context, action: "dismiss suggested date")
    }

    // MARK: - Helpers

    private static func key(_ guid: String, _ date: Date, _ calendar: Calendar) -> String {
        "\(guid)@\(Int(calendar.startOfDay(for: date).timeIntervalSince1970))"
    }

    /// Drops a leading "Reminder:" the school often prefixes, so the task title
    /// reads as a thing to do rather than a notice headline.
    private static func cleanedTitle(_ title: String) -> String {
        var t = title
        for prefix in ["Reminder: ", "REMINDER: ", "Reminder - "] {
            if t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func save(_ context: ModelContext, action: String) {
        do {
            try context.save()
        } catch {
            Logger.shared.error("school", "\(action) failed: \(error.localizedDescription)")
        }
    }
}
