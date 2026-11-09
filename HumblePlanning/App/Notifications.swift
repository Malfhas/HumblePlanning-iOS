import UserNotifications
import HumbleCore

/// Local notifications: alerts of the server and reminders before tasks. A tap opens the task.
final class Notifications: NSObject, UNUserNotificationCenterDelegate, ReminderScheduling, AlertPresenting, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    @MainActor var onOpenTask: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asks once whether the app may notify.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    var isAuthorized: Bool {
        get async {
            let status = await center.notificationSettings().authorizationStatus
            return status == .authorized || status == .provisional || status == .ephemeral
        }
    }

    // MARK: Reminders

    func schedule(_ reminders: [Reminder]) async {
        await cancelAll()
        let calendar = Calendar.current
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title.isEmpty ? String(localized: .notifTitre) : reminder.title
            content.body = reminder.text
            content.sound = .default
            content.threadIdentifier = "reminders"
            content.userInfo = ["task_id": reminder.taskId]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "reminder-\(reminder.taskId)", content: content, trigger: trigger))
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("reminder-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }

    // MARK: Alerts

    func show(_ alert: MobileAlert) async {
        guard await isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        content.threadIdentifier = "alerts"
        content.interruptionLevel = .timeSensitive
        if let taskId = alert.taskId { content.userInfo = ["task_id": taskId] }
        try? await center.add(UNNotificationRequest(identifier: "alert-\(alert.id)", content: content, trigger: nil))
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let taskId = response.notification.request.content.userInfo["task_id"] as? String else { return }
        await MainActor.run { onOpenTask?(taskId) }
    }
}
