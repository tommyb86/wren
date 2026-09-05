import Foundation

/// Joins a calendar event to the news notice about the same real-world thing,
/// so the assembly's time (from the calendar) and its parking note (from the
/// news) end up on one row instead of two half-empty ones.
///
/// Fuzzy, so it fails one way: two signals to merge, one is a weaker cross-link,
/// zero is nothing. When unsure the caller shows both — a duplicate is a shrug,
/// a dropped item is what the feature exists to prevent.
public enum SchoolCorrelation {
    public struct Match: Hashable, Sendable {
        public let noticeGUID: String
        /// How many of {same day, title overlap, shared location} agreed.
        public let signals: Int

        public init(noticeGUID: String, signals: Int) {
            self.noticeGUID = noticeGUID
            self.signals = signals
        }

        /// Two or more signals: confident enough to show as one merged item.
        public var isMerge: Bool { signals >= 2 }
    }

    /// The best-matching notice for an event, or `nil` if none shares a signal.
    public static func correlate(
        event: SchoolCalendarEvent,
        notices: [SchoolFeedItem],
        calendar: Calendar = .current
    ) -> Match? {
        var best: Match?
        for notice in notices {
            let n = signals(event: event, notice: notice, calendar: calendar)
            guard n >= 1 else { continue }
            if best == nil || n > best!.signals {
                best = Match(noticeGUID: notice.guid, signals: n)
            }
        }
        return best
    }

    static func signals(event: SchoolCalendarEvent, notice: SchoolFeedItem, calendar: Calendar) -> Int {
        var count = 0

        // 1. Same day — the notice refers to the event's date. Resolved with the
        //    event's date as the reference, so a bare "7 September" in the notice
        //    ties to this event rather than guessing a year.
        let blocks = notice.bodyHTML.isEmpty
            ? [notice.title, notice.bodyText]
            : SchoolBody.blocks(fromHTML: notice.bodyHTML).map(\.text) + [notice.title]
        let dates = SchoolDeadlines.extract(fromBlocks: blocks, published: event.start, calendar: calendar)
        if dates.contains(where: { calendar.isDate($0.date, inSameDayAs: event.start) }) {
            count += 1
        }

        // 2. Title overlap — at least two significant words in common.
        let eventTokens = significantTokens(event.title)
        let noticeTokens = significantTokens(notice.title)
        if eventTokens.intersection(noticeTokens).count >= 2 {
            count += 1
        }

        // 3. Shared location — the event's venue named in the notice text.
        let location = event.location.lowercased().trimmingCharacters(in: .whitespaces)
        if !location.isEmpty {
            let haystack = (notice.title + " " + notice.bodyText).lowercased()
            if haystack.contains(location) { count += 1 }
        }

        return count
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "our", "all", "your", "with", "this", "that", "from",
        "will", "are", "was", "has", "have", "you", "not", "but",
        "junior", "school", "college", "senior", "secondary", "special", "reminder",
        "gps", "bbc", "students", "student", "family", "families", "notice"
    ]

    static func significantTokens(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let parts = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count >= 3 && !stopwords.contains($0) })
    }
}
