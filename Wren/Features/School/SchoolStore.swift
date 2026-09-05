import Foundation
import SwiftData
import WrenCore

/// Fetches every configured source and reconciles the results into the store:
/// the `all` feeds are the corpus, the `topic` feeds only union labels. Nothing
/// is deleted for dropping out of a feed.
@MainActor
enum SchoolStore {
    @discardableResult
    static func refresh(context: ModelContext) async -> Int {
        let sources = SchoolConfig.sources
        guard !sources.isEmpty else { return 0 }

        var corpus: [SchoolFeedItem] = []
        var labelsByGuid: [String: [String]] = [:]
        var events: [SchoolCalendarEvent] = []

        for source in sources {
            switch source.kind {
            case .all:
                corpus.append(contentsOf: await SchoolFeedClient.fetch(source))
            case .topic:
                for item in await SchoolFeedClient.fetch(source) {
                    labelsByGuid[item.guid, default: []].append(source.name)
                }
            case .calendar:
                events.append(contentsOf: await SchoolFeedClient.fetchICal(source))
            }
        }

        upsertEvents(events, context: context)
        return upsert(corpus: corpus, labelsByGuid: labelsByGuid, context: context)
    }

    /// Upsert calendar events by `uid`, then drop the ones that have finished.
    /// The week ahead is a forward-looking view, so keeping the past would only
    /// grow the store and slow the query.
    @discardableResult
    static func upsertEvents(
        _ events: [SchoolCalendarEvent],
        context: ModelContext,
        calendar: Calendar = .current
    ) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<SchoolEvent>())) ?? []
        guard !events.isEmpty || !existing.isEmpty else { return 0 }

        var byUID: [String: SchoolEvent] = [:]
        for event in existing { byUID[event.uid] = event }

        var added = 0
        for event in events where !event.uid.isEmpty {
            if let stored = byUID[event.uid] {
                stored.merge(event)
            } else {
                let stored = SchoolEvent(from: event)
                context.insert(stored)
                byUID[event.uid] = stored
                added += 1
            }
        }

        // Yesterday, not today: an event that finished this morning is still
        // worth seeing for the rest of the day.
        let floor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? .distantPast
        for stored in byUID.values where stored.finish < floor {
            context.delete(stored)
        }

        do {
            try context.save()
            Logger.shared.info("school", "reconciled calendar — \(added) new, \(events.count) in feed")
        } catch {
            Logger.shared.error("school", "calendar save failed: \(error.localizedDescription)")
        }
        return added
    }

    /// Upsert by `guid`, enriching each corpus item with any topic labels, then
    /// union labels onto notices already stored but absent from this fetch.
    @discardableResult
    static func upsert(
        corpus: [SchoolFeedItem],
        labelsByGuid: [String: [String]],
        context: ModelContext
    ) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<SchoolNotice>())) ?? []
        var byGuid: [String: SchoolNotice] = [:]
        for notice in existing { byGuid[notice.guid] = notice }

        var added = 0
        for item in corpus where !item.guid.isEmpty {
            var enriched = item
            if let labels = labelsByGuid[item.guid] { enriched.labels = labels }

            if let notice = byGuid[item.guid] {
                notice.merge(enriched)
            } else {
                let notice = SchoolNotice(from: enriched)
                context.insert(notice)
                byGuid[item.guid] = notice
                added += 1
            }
        }

        // Labels for notices that were already stored but not re-fetched now.
        for (guid, labels) in labelsByGuid {
            guard let notice = byGuid[guid] else { continue }
            for label in labels where !notice.labels.contains(label) {
                notice.labels.append(label)
            }
        }

        do {
            try context.save()
            Logger.shared.info("school", "reconciled feed — \(added) new, \(byGuid.count) total")
        } catch {
            Logger.shared.error("school", "save failed: \(error.localizedDescription)")
        }
        return added
    }

    static func markRead(_ notice: SchoolNotice, context: ModelContext) {
        guard !notice.isRead else { return }
        notice.isRead = true
        try? context.save()
    }
}
