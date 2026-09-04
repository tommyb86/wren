import SwiftUI
import SwiftData

@main
@MainActor
struct WrenApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(WrenTheme.storageKey) private var themeRaw = WrenTheme.lime.rawValue

    private let container: ModelContainer

    init() {
        self.container = ModelContainerFactory.make()
        Logger.shared.info("app", "launch — \(BuildInfo.summary)")
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .tint(Color.wren.accent)
                .preferredColorScheme((Appearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                // Injected once at the root: every view that paints a highlight
                // reads it from the environment, so changing it redraws them all.
                .environment(\.wrenTheme, WrenTheme(rawValue: themeRaw) ?? .lime)
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
        await ReminderCoordinator.rebuild(context: container.mainContext)
    }
}
