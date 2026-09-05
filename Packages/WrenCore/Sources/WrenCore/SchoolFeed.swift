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
    /// Flattened plain text — for ranking and one-line previews.
    public let bodyText: String
    /// The original body HTML, kept so the detail view can render paragraphs and
    /// bullets rather than one wall of text.
    public let bodyHTML: String
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
        bodyHTML: String = "",
        published: Date?,
        category: String = "",
        position: Int = 0,
        imageHash: String = "",
        labels: [String] = []
    ) {
        self.guid = guid
        self.title = title
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.published = published
        self.category = category
        self.position = position
        self.imageHash = imageHash
        self.labels = labels
    }
}

// MARK: - Structured body

/// One block of a notice body. Enough structure to read the article as
/// paragraphs and bullet lists instead of a single run-on line.
public enum SchoolBodyBlock: Hashable, Sendable {
    case paragraph(String)
    case bullet(String)

    public var text: String {
        switch self {
        case .paragraph(let text), .bullet(let text): return text
        }
    }

    public var isBullet: Bool {
        if case .bullet = self { return true }
        return false
    }
}

public enum SchoolBody {
    private static let bulletMarker = "\u{2022} "

    /// Turns feed-body HTML into readable blocks: `<li>` becomes a bullet, and
    /// paragraph/line/heading boundaries become separate paragraphs. Not a full
    /// HTML renderer — just the structure that stops it reading as a wall.
    public static func blocks(fromHTML html: String) -> [SchoolBodyBlock] {
        var s = html
        // List items become bullet lines.
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "\n" + bulletMarker, options: [.regularExpression, .caseInsensitive])
        // Block boundaries become newlines.
        s = s.replacingOccurrences(
            of: "</p>|<br\\s*/?>|</div>|</h[1-6]>|</li>|</ul>|</ol>|</tr>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Drop remaining tags and decode entities.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = SchoolText.decodeEntities(s)

        var blocks: [SchoolBodyBlock] = []
        for rawLine in s.components(separatedBy: "\n") {
            var line = rawLine.replacingOccurrences(of: "[ \\t\u{00A0}]+", with: " ", options: .regularExpression)
            line = line.replacingOccurrences(of: "\\s+([.,;:!?])", with: "$1", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("\u{2022}") {
                let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.bullet(text)) }
            } else {
                blocks.append(.paragraph(line))
            }
        }

        // A body with no block markup at all still gets one readable paragraph.
        if blocks.isEmpty {
            let plain = SchoolText.plain(fromHTML: html)
            if !plain.isEmpty { blocks.append(.paragraph(plain)) }
        }
        return blocks
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
