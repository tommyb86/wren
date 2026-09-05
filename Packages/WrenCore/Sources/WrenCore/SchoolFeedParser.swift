import Foundation

/// Parses a Schoolbox RSS 2.0 feed into `SchoolFeedItem`s.
///
/// Pure Foundation (`XMLParser`), so it tests on Windows CI like the rest of
/// WrenCore. The body arrives as a CDATA block of HTML, captured raw and then
/// flattened by `SchoolText`.
public enum SchoolFeedParser {
    public static func parse(_ data: Data) -> [SchoolFeedItem] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    public static func parse(_ xml: String) -> [SchoolFeedItem] {
        parse(Data(xml.utf8))
    }

    /// RFC 822 dates as Schoolbox emits them: "Fri, 04 Sep 2026 14:01:00 +1000".
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [SchoolFeedItem] = []

        private var position = 0
        private var inItem = false
        private var element = ""
        private var title = ""
        private var guid = ""
        private var category = ""
        private var pubDate = ""
        private var descriptionHTML = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            element = elementName
            if elementName == "item" {
                inItem = true
                title = ""; guid = ""; category = ""; pubDate = ""; descriptionHTML = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inItem else { return }
            switch element {
            case "title": title += string
            case "guid": guid += string
            case "category": category += string
            case "pubDate": pubDate += string
            case "description": descriptionHTML += string
            default: break
            }
        }

        // CDATA (the description body) arrives here, not as characters.
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard inItem, element == "description" else { return }
            descriptionHTML += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if elementName == "item" {
                let id = guid
                    .replacingOccurrences(of: "\\?.*$", with: "", options: .regularExpression)
                    .split(separator: "/").last.map(String.init) ?? guid.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(
                    SchoolFeedItem(
                        guid: id.trimmingCharacters(in: .whitespacesAndNewlines),
                        title: SchoolText.decodeEntities(title.trimmingCharacters(in: .whitespacesAndNewlines)),
                        bodyText: SchoolText.plain(fromHTML: descriptionHTML),
                        published: SchoolFeedParser.dateFormatter.date(from: pubDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                        category: category.trimmingCharacters(in: .whitespacesAndNewlines),
                        position: position,
                        imageHash: SchoolText.firstImageHash(inHTML: descriptionHTML)
                    )
                )
                position += 1
                inItem = false
            }
            element = ""
        }
    }
}
