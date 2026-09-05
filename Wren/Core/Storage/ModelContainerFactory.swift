import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([
        BinCollection.self,
        RecurringTask.self,
        TaskCompletion.self,
        Bill.self,
        BillPayment.self,
        Receipt.self,
        SchoolNotice.self
    ])

    /// A failed container must be *visible*. On device the only symptom would
    /// otherwise be a blank launch with no way to find out why.
    @MainActor
    static func make() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            Logger.shared.info("storage", "model container opened at \(configuration.url.lastPathComponent)")
            return container
        } catch {
            Logger.shared.error("storage", "model container failed: \(error.localizedDescription)")
        }

        // Phase 0's throwaway model was dropped in Phase 1, so an old store can
        // be incompatible. If it cannot be opened the data is already
        // unreachable — move it aside (never delete: it stays inspectable) and
        // start clean rather than silently running in memory.
        if quarantineStore(at: configuration.url) {
            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                Logger.shared.warn("storage", "opened a fresh store after quarantining the old one")
                return container
            } catch {
                Logger.shared.error("storage", "fresh store also failed: \(error.localizedDescription)")
            }
        }

        Logger.shared.flush()

        // Last resort: launch in memory so Diagnostics is still reachable and can
        // explain what happened. Data will not persist — the log says so loudly.
        do {
            let fallback = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            Logger.shared.error("storage", "RUNNING IN MEMORY — nothing you add will be saved")
            return fallback
        } catch {
            fatalError("SwiftData unavailable: \(error)")
        }
    }

    /// Renames the store (and its -wal/-shm siblings) out of the way.
    @MainActor
    private static func quarantineStore(at url: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return false }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        var moved = false

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard manager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: "\(url.path).quarantine-\(stamp)\(suffix)")
            do {
                try manager.moveItem(at: source, to: destination)
                Logger.shared.warn("storage", "quarantined \(source.lastPathComponent)")
                moved = true
            } catch {
                Logger.shared.error("storage", "could not quarantine \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return moved
    }
}
