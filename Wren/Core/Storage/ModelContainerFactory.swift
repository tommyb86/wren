import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([PipelineProbe.self])

    /// A failed container is fatal but must be *visible* — on device the only
    /// symptom would otherwise be a blank launch.
    @MainActor
    static func make() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            Logger.shared.info("storage", "model container opened at \(configuration.url.lastPathComponent)")
            return container
        } catch {
            Logger.shared.error("storage", "model container failed: \(error.localizedDescription)")
            Logger.shared.flush()
            // Fall back to memory so the app launches and Diagnostics is reachable.
            do {
                let fallback = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
                Logger.shared.warn("storage", "running on in-memory fallback container")
                return fallback
            } catch {
                fatalError("SwiftData unavailable: \(error)")
            }
        }
    }
}
