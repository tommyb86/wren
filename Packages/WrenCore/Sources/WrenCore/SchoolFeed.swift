import Foundation

/// One item from a Schoolbox news feed, decoupled from XML and SwiftData.
///
/// The feed carries the whole article body inline as HTML, so nothing ever
/// needs the article page (which is behind SSO anyway). `bodyText` is that HTML
/// flattened to plain text for ranking and preview.
public struct SchoolFeedItem: Hashable, Sendable, Identifiable {
    /// The numeric article id, e.g. "31326". Stable across fetches; the dedupe
    /// key everywhere.
    public let guid: String
    public let title: String
    public let bodyText: String
    public let published: Date?
    public let category: String
    /// Position in the feed as delivered. The first four items are pinned by
    /// the school out of date order, so `position <= 3` is treated as pinned.
    public let position: Int
    /// First `/storage/image.php?hash=…` hash in the body, if any.
    public let imageHash: String
    /// Topic-feed labels the school has attached, e.g. "Year 4 Community".
    /// Unioned on from the topic feeds; never revoked. `var` so the store can
    /// enrich a parsed item before ranking.
    public var labels: [String]

    public var id: String { guid }

    public var isPinned: Bool { position <= 3 }

    public init(
        guid: String,
        title: String,
        bodyText: String,
        published: Date?,
        category: String = "",
        position: Int = 0,
        imageHash: String = "",
        labels: [String] = []
    ) {
        self.guid = guid
        self.title = title
        self.bodyText = bodyText
        self.published = published
        self.category = category
        self.position = position
        self.imageHash = imageHash
        self.labels = labels
    }
}

// MARK: - HTML flattening

public enum SchoolText {
    /// Flattens feed-body HTML to readable plain text: tags dropped, a handful
    /// of common entities decoded, whitespace collapsed. Not a general HTML
    /// parser — just enough to rank and preview a notice.
    public static func plain(fromHTML html: String) -> String {
        var s = html
        // Block-level tags become spaces so words either side don't fuse.
        s = s.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        s = decodeEntities(s)
        // Collapse all runs of whitespace to single spaces.
        s = s.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        // A dropped tag before punctuation leaves "word ." — close that gap so
        // the flattened text reads naturally.
        s = s.replacingOccurrences(
            of: "\\s+([.,;:!?])",
            with: "$1",
            options: .regularExpression
        )
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First storage-image hash referenced in the body, for the thumbnail.
    public static func firstImageHash(inHTML html: String) -> String {
        guard let range = html.range(
            of: "image\\.php\\?hash=([0-9a-fA-F]+)",
            options: .regularExpression
        ) else { return "" }
        let match = String(html[range])
        return match.replacingOccurrences(of: "image.php?hash=", with: "")
    }

    private static let entities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&apos;": "'", "&#39;": "'", "&#039;": "'", "&nbsp;": " ",
        "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
        "&rdquo;": "\u{201D}", "&ldquo;": "\u{201C}",
        "&ndash;": "\u{2013}", "&mdash;": "\u{2014}",
        "&#8217;": "\u{2019}", "&#8216;": "\u{2018}",
        "&#8220;": "\u{201C}", "&#8221;": "\u{201D}",
        "&#8211;": "\u{2013}", "&#8212;": "\u{2014}",
        "&hellip;": "\u{2026}", "&#8230;": "\u{2026}"
    ]

    static func decodeEntities(_ input: String) -> String {
        var s = input
        for (entity, value) in entities {
            s = s.replacingOccurrences(of: entity, with: value)
        }
        guard s.contains("&#") else { return s }
        return decodeNumericEntities(s)
    }

    /// Replaces `&#NNN;` decimal character references with their scalar.
    private static func decodeNumericEntities(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#([0-9]{1,6});") else { return input }
        let ns = input as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let code = ns.substring(with: match.range(at: 1))
            if let value = UInt32(code), let scalar = Unicode.Scalar(value) {
                result.append(Character(scalar))
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
