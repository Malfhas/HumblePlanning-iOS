import SwiftUI
import HumbleCore

/// My tasks of the next 30 days, day by day; readable offline.
struct UpcomingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var days: [UpcomingDay] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var offlineSince: Date?
    @State private var offline = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(.upcomingSubtitle(PlanningPeriod.upcomingDays))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if offline { OfflineBanner(since: offlineSince) }
                if let error { Banner(text: error, tone: .error) }
                ForEach(days) { entry in
                    // One block per day: a task over several days shows under each of them
                    VStack(alignment: .leading, spacing: 10) {
                        header(entry)
                        ForEach(entry.tasks) { task in
                            NavigationLink(value: TaskRoute(id: task.id)) { TaskCard(task: task, day: entry.day) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .overlay {
            if !loaded {
                ProgressView()
            } else if days.isEmpty && error == nil {
                EmptyState(systemImage: "calendar.badge.checkmark", title: String(localized: .upcomingEmpty),
                           subtitle: String(localized: .upcomingEmptyHelp(PlanningPeriod.upcomingDays)))
            }
        }
        .navigationTitle(String(localized: .upcomingTitle))
        .toolbar {
            if app.repository.access.canCreateTask {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: .newTask), systemImage: "plus") { app.formRoute = .create(date: nil, userId: nil) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: app.repository.tasksChanged) { Task { await load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }

    private func header(_ entry: UpcomingDay) -> some View {
        let today = CalendarDay.today()
        return AdaptiveStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if entry.day == today {
                    Text(.today).foregroundStyle(Color.accentColor)
                } else if entry.day == today.adding(days: 1) {
                    Text(.tomorrow)
                } else {
                    Text(PlanningFormat.longLabel(entry.day, locale: locale))
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            if entry.day == today {
                Text(PlanningFormat.longLabel(entry.day, locale: locale)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(.nTasks(entry.tasks.count)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }

    private func load() async {
        let today = CalendarDay.today()
        do {
            let result = try await app.repository.tasks(in: PlanningPeriod.upcoming(today: today))
            days = PlanningAgenda.upcoming(result.tasks, me: app.repository.userId, today: today)
            offline = result.isOffline
            offlineSince = result.offlineSince
            error = nil
        } catch {
            self.error = screenMessage(error)
        }
        loaded = true
    }
}
