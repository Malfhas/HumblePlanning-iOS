import Foundation

/// How long before a task its reminder fires.
public enum ReminderOffset: String, CaseIterable, Sendable {
    case none, fiveMinutes = "5min", fifteenMinutes = "15min", thirtyMinutes = "30min", oneHour = "1h", fourHours = "4h", oneDay = "1j"

    /// An unknown stored value is the default, 15 minutes.
    public init(stored: String) {
        self = ReminderOffset(rawValue: stored) ?? .fifteenMinutes
    }

    public var minutes: Int? {
        switch self {
        case .none: nil
        case .fiveMinutes: 5
        case .fifteenMinutes: 15
        case .thirtyMinutes: 30
        case .oneHour: 60
        case .fourHours: 240
        case .oneDay: 1440
        }
    }
}

/// A local notification before a task starts.
public struct Reminder: Codable, Sendable, Equatable {
    public var taskId: String
    public var fireAt: Date
    public var title: String
    public var text: String

    public init(taskId: String, fireAt: Date, title: String, text: String) {
        self.taskId = taskId
        self.fireAt = fireAt
        self.title = title
        self.text = text
    }
}

public enum ReminderPlanner {
    /// iOS keeps 64 pending notifications per app: the nearest ones, with room left for the others.
    public static let maximum = 60
    /// Reminders cover the next 14 days.
    public static let days = 14

    /// One reminder per task, on its start date (a task over several days is reminded once; every
    /// occurrence of a series is its own task). All-day tasks start at `defaultStart` (morning start).
    public static func plan(_ tasks: [PlanningTask], defaultStart: String, offset: ReminderOffset, now: Date,
                            timeZone: TimeZone, label: (PlanningTask) -> (title: String, detail: String)) -> [Reminder] {
        guard let minutes = offset.minutes else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let reminders = tasks.compactMap { task -> Reminder? in
            let parts = task.startDate.split(separator: "-")
            guard task.startDate.count == 10, parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
            else { return nil }
            let time = parseTime(task.startTime) ?? parseTime(defaultStart) ?? (8, 0)
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute)) else { return nil }
            let fireAt = start.addingTimeInterval(TimeInterval(-minutes * 60))
            guard fireAt > now else { return nil }
            let (title, detail) = label(task)
            let clock = String(format: "%02d:%02d", time.hour, time.minute)
            return Reminder(taskId: task.id, fireAt: fireAt, title: title, text: "\(clock) · \(detail)")
        }
        return Array(reminders.sorted { $0.fireAt < $1.fireAt }.prefix(maximum))
    }

    /// `HH:MM…` → hour and minute, nil when unreadable.
    public static func parseTime(_ value: String?) -> (hour: Int, minute: Int)? {
        guard let value, value.count >= 5 else { return nil }
        let characters = Array(value)
        guard let hour = Int(String(characters[0..<2])), let minute = Int(String(characters[3..<5])),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// The text of a reminder: the project, and the title (or the people when the title is the project).
    public static func label(_ task: PlanningTask, references: References) -> (title: String, detail: String) {
        let project = task.project?.label ?? references.project(task.projectId)?.label ?? (task.title ?? "")
        let rawTitle = (task.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? project : rawTitle
        return (project, title == project ? task.users.map(\.displayName).joined(separator: ", ") : title)
    }
}
