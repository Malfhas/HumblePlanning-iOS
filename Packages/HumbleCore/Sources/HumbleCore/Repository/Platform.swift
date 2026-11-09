import Foundation

/// The language of the app (the per-app language of the iOS settings, else the phone's), sent to the
/// server so that its messages, alerts and e-mails follow it.
public enum AppLanguage {
    public static let supported = ["en", "fr", "es", "de"]

    public static var effective: String {
        let preferred = Bundle.main.preferredLocalizations.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
        if let preferred, supported.contains(preferred) { return preferred }
        let phone = Locale.current.language.languageCode?.identifier ?? "en"
        return supported.contains(phone) ? phone : "en"
    }
}

/// Local notifications before tasks (UserNotifications in the app).
public protocol ReminderScheduling: Sendable {
    /// Replaces every scheduled reminder.
    func schedule(_ reminders: [Reminder]) async
    func cancelAll() async
}

/// Shows an alert of the server as a notification.
public protocol AlertPresenting: Sendable {
    func show(_ alert: MobileAlert) async
}

/// The overlay above the whole app while the server refuses it.
public enum BlockingState: Equatable, Sendable {
    case upgradeRequired(minimumVersion: String, storeURL: String)
    case maintenance(String)
    case appNotAllowed(String)
}

/// Tasks of a period, from the server or from the offline copy.
public struct TasksResult: Sendable {
    public var tasks: [PlanningTask]
    /// When the offline copy was taken, when the tasks come from it.
    public var offlineSince: Date?
    public var isOffline: Bool
}
