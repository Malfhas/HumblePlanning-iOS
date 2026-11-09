import SwiftUI
import HumbleCore

@main
struct HumblePlanningApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.theme.colorScheme)
                .tint(.accentColor)
                .onOpenURL { app.handle($0) }
        }
        .commands { TaskCommands(app: app) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                app.repository.syncLanguage()
                app.repository.onForeground()
            case .background:
                app.repository.onBackground()
                if app.repository.isLoggedIn { BackgroundRefresh.schedule() }
            default: break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run(app.repository)
        }
    }
}

/// The menu bar of the iPad and the shortcuts of a hardware keyboard: Command-N opens a new task.
struct TaskCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: .newTask)) { app.formRoute = .create(date: nil, userId: nil) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!app.showsMain || !app.repository.access.canCreateTask || app.formRoute != nil)
        }
    }
}
