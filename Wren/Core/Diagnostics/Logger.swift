import Foundation
import Combine

/// There is no debugger, no console and no simulator on this setup. This buffer
/// is the only window into what the app did on the device, so every notable
/// action writes a line here.
///
/// Bounded in-memory ring buffer, flushed to UserDefaults on backgrounding.
@MainActor
final class Logger: ObservableObject {
    static let shared = Logger()

    enum Level: String, Codable, CaseIterable, Identifiable {
        case debug, info, warn, error
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .debug: return "ant"
            case .info: return "info.circle"
            case .warn: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var level: Level
        var category: String
        var message: String

        var line: String {
            "\(Self.stamp.string(from: date)) [\(level.rawValue.uppercased())] \(category): \(message)"
        }

        static let stamp: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return f
        }()
    }

    /// Newest last. Capped at `capacity`.
    @Published private(set) var entries: [Entry] = []

    private let capacity = 500
    private let defaultsKey = "wren.log.entries"

    private init() {
        entries = Self.load(key: defaultsKey)
    }

    func log(_ level: Level, _ category: String, _ message: String) {
        entries.append(Entry(date: Date(), level: level, category: category, message: message))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        #if DEBUG
        print(entries[entries.count - 1].line)
        #endif
    }

    func debug(_ category: String, _ message: String) { log(.debug, category, message) }
    func info(_ category: String, _ message: String) { log(.info, category, message) }
    func warn(_ category: String, _ message: String) { log(.warn, category, message) }
    func error(_ category: String, _ message: String) { log(.error, category, message) }

    /// Called on scene backgrounding. Cheap enough to also call after notable events.
    func flush() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Newest first, as plain text — what the share sheet exports.
    func exportText() -> String {
        entries.reversed().map(\.line).joined(separator: "\n")
    }

    private static func load(key: String) -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }
}
