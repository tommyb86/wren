import SwiftUI
import SwiftData

@main
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
                // From Phase 1 this is where the notification set is rebuilt.
                Task { await NotificationScheduler.shared.refreshPending() }
            default:
                break
            }
        }
    }
}
