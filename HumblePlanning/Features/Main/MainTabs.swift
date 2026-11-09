import SwiftUI
import HumbleCore

/// The tabs of the app. The assistant only shows when the server offers it to the account.
struct MainTabs: View {
    enum Section: String, Hashable { case planning, upcoming, alerts, assistant, settings }

    @Environment(AppModel.self) private var app
    @SceneStorage("tab") private var selection = Section.planning
    @State private var planningPath = NavigationPath()
    @State private var planning: PlanningModel?
    /// Measured once, before the tabs are made: their first placement depends on it.
    @State private var wideAtLaunch: Bool?

    /// A window wide enough for a sidebar beside the planning (an iPad in landscape) starts with the sidebar, like
    /// the rail of the Android tablets; a narrower one keeps the tab bar, where a sidebar would cover the planning.
    var body: some View {
        Group {
            if let wideAtLaunch {
                tabs.defaultAdaptableTabBarPlacement(wideAtLaunch ? .sidebar : .automatic)
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 1100 } action: { wide in
            if wideAtLaunch == nil { wideAtLaunch = wide }
        }
    }

    private var tabs: some View {
        @Bindable var app = app
        let assistant = app.repository.references.assistant.available
        return TabView(selection: displayed(assistant: assistant)) {
            Tab(String(localized: .tabPlanning), systemImage: "calendar", value: Section.planning) {
                NavigationStack(path: $planningPath) {
                    Group {
                        if let planning { PlanningView(model: planning) }
                    }
                    .taskDestinations()
                }
            }
            Tab(String(localized: .tabUpcoming), systemImage: "list.bullet.rectangle", value: Section.upcoming) {
                NavigationStack { UpcomingView().taskDestinations() }
            }
            Tab(String(localized: .tabAlerts), systemImage: "bell", value: Section.alerts) {
                NavigationStack { AlertsView().taskDestinations() }
            }
            if assistant {
                Tab(String(localized: .tabAssistant), systemImage: "sparkles", value: Section.assistant) {
                    NavigationStack {
                        AssistantView()
                            .navigationDestination(for: ConversationRoute.self) { route in
                                ConversationView(model: ConversationModel(repository: app.repository, conversationId: route.id))
                            }
                    }
                }
            }
            Tab(String(localized: .tabSettings), systemImage: "gearshape", value: Section.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: $app.formRoute) { route in
            TaskFormView(route: route)
        }
        .onAppear {
            if planning == nil { planning = PlanningModel(repository: app.repository) }
            openPendingTask()
            #if DEBUG
            // Development only: `-HPTab settings`
            if let tab = UserDefaults.standard.string(forKey: "HPTab").flatMap(Section.init(rawValue:)) { selection = tab }
            // `-HPOpenTask <id>`, `-HPOpenForm create|edit:<id>|duplicate:<id>`
            if let id = UserDefaults.standard.string(forKey: "HPOpenTask") { app.openTaskId = id }
            if let form = UserDefaults.standard.string(forKey: "HPOpenForm") {
                if form == "create" { app.formRoute = .create(date: nil, userId: nil) }
                if form.hasPrefix("edit:") { app.formRoute = .edit(id: String(form.dropFirst(5))) }
                if form.hasPrefix("duplicate:") { app.formRoute = .duplicate(id: String(form.dropFirst(10))) }
            }
            #endif
        }
        .onChange(of: app.openTaskId) { openPendingTask() }
        .task { await firstEntry() }
    }

    /// The assistant tab falls back to the planning while the assistant is unavailable.
    private func displayed(assistant: Bool) -> Binding<Section> {
        Binding(get: { selection == .assistant && !assistant ? .planning : selection }, set: { selection = $0 })
    }

    /// A tapped notification opens its task on the planning.
    private func openPendingTask() {
        guard let id = app.openTaskId else { return }
        app.openTaskId = nil
        selection = .planning
        planningPath.append(TaskRoute(id: id))
    }

    /// Once per session: the notification permission (asked once ever), reminders, background refresh.
    private func firstEntry() async {
        var asks = !app.repository.preferences.notificationsAsked
        #if DEBUG
        // Development only: `-HPSkipNotificationPrompt YES` (screenshots)
        if UserDefaults.standard.bool(forKey: "HPSkipNotificationPrompt") { asks = false }
        #endif
        if asks {
            app.repository.preferences.notificationsAsked = true
            _ = await app.notifications.requestAuthorization()
        }
        BackgroundRefresh.schedule()
        await app.repository.syncReminders()
    }
}

extension View {
    /// Task detail pushed from any list of the tab.
    func taskDestinations() -> some View {
        navigationDestination(for: TaskRoute.self) { TaskDetailView(id: $0.id) }
    }
}
