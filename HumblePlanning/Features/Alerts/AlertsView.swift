import SwiftUI
import HumbleCore

/// Changes others made to my tasks, kept seven days by the server; newest first.
struct AlertsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var alerts: [MobileAlert] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Banner(text: error, tone: .error)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(alerts) { alert in
                if let taskId = alert.taskId {
                    NavigationLink(value: TaskRoute(id: taskId)) { AlertRow(alert: alert) }
                } else {
                    AlertRow(alert: alert)
                }
            }
        }
        .overlay {
            if !loaded {
                ProgressView()
            } else if alerts.isEmpty && error == nil {
                EmptyState(systemImage: "bell.slash", title: String(localized: .alertsEmpty), subtitle: String(localized: .alertsEmptyHelp))
            }
        }
        .navigationTitle(String(localized: .tabAlerts))
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: app.repository.alertsChanged) { Task { await load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }

    private func load() async {
        do {
            alerts = try await app.repository.alertsHistory()
            error = nil
        } catch {
            self.error = screenMessage(error)
        }
        loaded = true
    }
}

private struct AlertRow: View {
    let alert: MobileAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.tint)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                AdaptiveStack(alignment: .firstTextBaseline) {
                    Text(alert.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(RelativeDate.text(alert.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !alert.message.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Navigation to a task, from any tab.
struct TaskRoute: Hashable {
    let id: String
}
