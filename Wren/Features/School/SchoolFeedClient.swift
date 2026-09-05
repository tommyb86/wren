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
}
