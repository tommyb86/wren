import Foundation
import WrenCore

/// Fetches and parses one feed. Foreground only for now: `BGAppRefreshTask` is
/// a later increment. No conditional GET — the feed sends `no-store` and no
/// `ETag`, so every fetch is a full pull and dedupe happens on `guid`.
enum SchoolFeedClient {
    static func fetch(_ source: SchoolSource) async -> [SchoolFeedItem] {
        guard let url = URL(string: source.url) else {
            Logger.record(.warn, "school", "bad URL for source '\(source.name)'")
            return []
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                Logger.record(.warn, "school", "'\(source.name)' returned HTTP \(status)")
                return []
            }
            let items = SchoolFeedParser.parse(data)
            Logger.record(.info, "school", "fetched \(items.count) item(s) from '\(source.name)'")
            return items
        } catch {
            Logger.record(.warn, "school", "fetch of '\(source.name)' failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches an iCalendar feed. Never logs the URL — it carries the token.
    ///
    /// Subscribe links copy as `webcal://`, which `URLSession` will not fetch;
    /// it is plain HTTPS underneath, so swap the scheme rather than making the
    /// parent notice and fix it by hand.
    static func fetchICal(_ source: SchoolSource, calendar: Calendar = .current) async -> [SchoolCalendarEvent] {
        var address = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.lowercased().hasPrefix("webcal://") {
            address = "https://" + String(address.dropFirst("webcal://".count))
        }

        guard let url = URL(string: address) else {
            Logger.record(.warn, "school", "bad calendar URL for source '\(source.name)'")
            return []
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                Logger.record(.warn, "school", "calendar '\(source.name)' returned HTTP \(status)")
                return []
            }
            let events = SchoolICal.parse(data, calendar: calendar)
            Logger.record(.info, "school", "fetched \(events.count) event(s) from '\(source.name)'")
            return events
        } catch {
            Logger.record(.warn, "school", "calendar fetch of '\(source.name)' failed: \(error.localizedDescription)")
            return []
        }
    }
}
