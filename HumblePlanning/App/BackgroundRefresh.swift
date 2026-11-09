import BackgroundTasks
import HumbleCore

/// The opportunistic background refresh of iOS: alerts and reminders when the app is closed
/// (iOS decides when; push takes over once the server can reach this phone).
enum BackgroundRefresh {
    static let identifier = "com.humbleplanning.app.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }

    /// One background run: new alerts are notified, reminders brought up to date.
    @MainActor
    static func run(_ repository: Repository) async {
        schedule()
        guard repository.isLoggedIn else { return }
        try? await repository.syncAlerts(notify: true)
        await repository.syncReminders()
    }
}
