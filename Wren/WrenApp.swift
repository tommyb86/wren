import SwiftUI
import SwiftData

@main
@MainActor
struct WrenApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        self.container = ModelContainerFactory.make()
        Logger.shared.info("app", "launch — \(BuildInfo.summary)")
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(Color.wren.accent)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Logger.shared.info("app", "backgrounded — flushing log")
                Logger.shared.flush()
            case .active:
                Logger.shared.debug("app", "active")
                // The whole pending set is rebuilt on every foreground. That is
                // what keeps us under the 64-request cap without diffing.
                Task { await rebuildReminders() }
            default:
                break
            }
        }
    }

    private func rebuildReminders() async {
        do {
            let bins = try container.mainContext.fetch(FetchDescriptor<BinCollection>())
            await NotificationScheduler.shared.rebuild(bins: bins)
        } catch {
            Logger.shared.error("app", "could not fetch bins on foreground: \(error.localizedDescription)")
        }
    }
}
