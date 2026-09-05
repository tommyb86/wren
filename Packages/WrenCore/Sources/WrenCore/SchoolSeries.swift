import Foundation

/// Detects "Watoto - Day 1 … Day 19" style running series so a feed that is
/// nearly half one daily post can be collapsed to a single row instead of
/// burying everything else.
public enum SchoolSeries {
    /// The stem of a numbered-series title, or `nil` if the title is not part
    /// of one. "Birtles House Charity - Watoto - Day 12" → "Birtles House
    /// Charity - Watoto". Matches a trailing `Day/Part/Week/No. N`.
    public static func stem(of title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Character class carries the literal en/em dashes rather than ICU
        // escapes, which do not accept the \u{…} form.
        guard let regex = try? NSRegularExpression(
            pattern: "^(.*?)[\\s\u{2013}\u{2014}:-]+(?:Day|Part|Week|Session|No\\.?)\\s*#?\\s*\\d+\\s*$",
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let stem = ns.substring(with: match.range(at: 1))
            .trimmingCharacters(in: CharacterSet(charactersIn: " -\u{2013}\u{2014}:"))
        // A stem must have some substance; a bare number is not a series name.
        return stem.count >= 3 ? stem : nil
    }

    /// Groups items by series stem, preserving first-seen order. Items not in a
    /// series come back as singletons under their own title.
    public static func group(_ items: [SchoolFeedItem]) -> [Group] {
        var order: [String] = []
        var byKey: [String: [SchoolFeedItem]] = [:]
        for item in items {
            let key = stem(of: item.title).map { "series:\($0)" } ?? "one:\(item.guid)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        return order.map { key in
            let members = byKey[key] ?? []
            let isSeries = key.hasPrefix("series:")
            return Group(
                stem: isSeries ? String(key.dropFirst("series:".count)) : members.first?.title ?? "",
                items: members,
                isSeries: isSeries && members.count > 1
            )
        }
    }

    public struct Group: Hashable, Sendable {
        public let stem: String
        public let items: [SchoolFeedItem]
        public let isSeries: Bool

        public var count: Int { items.count }
        public var latest: SchoolFeedItem? {
            items.max { ($0.published ?? .distantPast) < ($1.published ?? .distantPast) }
        }
        public var earliest: SchoolFeedItem? {
            items.min { ($0.published ?? .distantPast) < ($1.published ?? .distantPast) }
        }
    }
}
