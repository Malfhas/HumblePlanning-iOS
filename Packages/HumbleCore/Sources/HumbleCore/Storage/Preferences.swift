import Foundation

/// Plain settings of the app (nothing secret), with the keys of the Android app.
public final class Preferences: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func string(_ key: String) -> String? { defaults.string(forKey: key) }
    private func set(_ key: String, _ value: Any?) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// Normalized address of the last server.
    public var server: String? { get { string("server") } set { set("server", newValue) } }
    /// Identifier filled in at sign-in (empty when not remembered).
    public var lastLogin: String { get { string("last_login") ?? "" } set { set("last_login", newValue) } }
    public var rememberMe: Bool {
        get { defaults.object(forKey: "remember_me") as? Bool ?? true }
        set { set("remember_me", newValue) }
    }
    public var userId: String? { get { string("user_id") } set { set("user_id", newValue) } }
    public var userName: String? { get { string("user_name") } set { set("user_name", newValue) } }
    /// `system`, `light` or `dark`.
    public var theme: String { get { string("theme") ?? "system" } set { set("theme", newValue) } }
    /// `project` (default) or `title`: main text of the task cards.
    public var cardTitle: String { get { string("card_title") ?? "project" } set { set("card_title", newValue) } }
    /// When the offline copy was taken.
    public var offlineDate: Date? {
        get { defaults.object(forKey: "offline_date") as? Date }
        set { set("offline_date", newValue) }
    }
    /// Alert cursor (ISO date-time).
    public var alertsAfter: String? { get { string("alerts_after") } set { set("alerts_after", newValue) } }
    /// Alerts already notified, oldest first, 200 at most.
    public var alertsShown: [String] {
        get { defaults.stringArray(forKey: "alerts_shown") ?? [] }
        set { set("alerts_shown", Array(newValue.suffix(200))) }
    }
    public var planningFilter: Data? { get { defaults.data(forKey: "planning_filter") } set { set("planning_filter", newValue) } }
    /// `day`, `week`, `month` or `grid`.
    public var planningView: String? { get { string("planning_view") } set { set("planning_view", newValue) } }
    public var gridCellWidth: Double? {
        get { defaults.object(forKey: "grid_cell_width") as? Double }
        set { set("grid_cell_width", newValue) }
    }
    /// `none`, `5min`, `15min` (default), `30min`, `1h`, `4h`, `1j`.
    public var reminderOffset: String { get { string("reminder_offset") ?? "15min" } set { set("reminder_offset", newValue) } }
    /// Reminders for every visible task instead of mine.
    public var reminderAll: Bool { get { defaults.bool(forKey: "reminder_all") } set { set("reminder_all", newValue) } }
    public var reminderFailed: Bool { get { defaults.bool(forKey: "reminder_failed") } set { set("reminder_failed", newValue) } }
    public var notificationsAsked: Bool { get { defaults.bool(forKey: "notifications_asked") } set { set("notifications_asked", newValue) } }
    /// The language last sent to the server.
    public var localeSent: String? { get { string("locale_sent") } set { set("locale_sent", newValue) } }
    /// APNs token last sent to the server (hex).
    public var pushTokenSent: String? { get { string("push_token_sent") } set { set("push_token_sent", newValue) } }

    /// What belongs to the account and goes with it at sign-out.
    public func clearAccountData() {
        for key in ["user_id", "user_name", "offline_date", "alerts_after", "alerts_shown", "planning_filter", "push_token_sent"] {
            defaults.removeObject(forKey: key)
        }
    }
}
