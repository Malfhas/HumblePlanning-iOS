import Foundation

/// Main text of a card or a bar, chosen in the settings; the raw value is the stored setting.
public enum CardTitleMode: String, Codable, CaseIterable, Sendable {
    /// The project label, the task's own title below it (default).
    case project
    /// The task's own title, the project label below it.
    case title
}

extension References {
    public func place(_ id: String?) -> Place? { id.flatMap { id in places.first { $0.id == id } } }
    public func resource(_ id: String?) -> PlanningResource? { id.flatMap { id in resources.first { $0.id == id } } }
    public func holiday(on day: CalendarDay) -> Holiday? { holidays.first { $0.date == day.iso } }
}

extension Holiday {
    /// Its colour, or the default orange.
    public var tint: RGBColor { RGBColor(hex: color) ?? .holiday }
    /// The label when not blank (the screens then say "Holiday").
    public var shownLabel: String? {
        let text = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : label
    }
}

extension PlanningTask {
    public var startDay: CalendarDay? { CalendarDay(startDate) }
    public var lastDay: CalendarDay? { CalendarDay(lastDate) }

    public func occursOn(_ day: CalendarDay) -> Bool { occursOn(day.iso) }

    /// Some day of the task is in `range` (dates compared as text, like the offline copy).
    public func overlaps(_ range: DayRange) -> Bool { startDate <= range.upperBound.iso && lastDate >= range.lowerBound.iso }

    /// The embedded project wins over the reference list (it may be archived there).
    public func projectOf(_ references: References) -> Project? { project ?? references.project(projectId) }
    public func statusOf(_ references: References) -> TaskStatus? { status ?? references.status(statusId) }

    /// Own title when not blank.
    public var ownTitle: String? {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return title
    }

    public func cardTitle(_ references: References, mode: CardTitleMode) -> String {
        let project = projectOf(references)?.label ?? ""
        switch mode {
        case .title: return ownTitle ?? project
        case .project: return project.isEmpty ? title ?? "" : project
        }
    }

    /// Second line of a full card; empty when there is none.
    public func cardSubtitle(_ references: References, mode: CardTitleMode) -> String {
        let project = projectOf(references)?.label ?? ""
        switch mode {
        case .title: return ownTitle == nil ? "" : project
        case .project: return project.isEmpty ? "" : ownTitle ?? ""
        }
    }

    /// "Day 2 of 3" of a task over several days shown on `day`; nil for a one-day task or unreadable dates.
    public func dayPosition(on day: CalendarDay) -> (index: Int, total: Int)? {
        guard isMultiDay, let start = startDay, let end = lastDay else { return nil }
        return (start.days(to: day) + 1, start.days(to: end) + 1)
    }
}

/// Up to 3 project colours of a day of the month view, and how many more there are (`+N`).
public struct MonthDots: Equatable, Sendable {
    /// nil for a colour that cannot be read (drawn in `outline`).
    public let colors: [RGBColor?]
    public let more: Int
}

/// The Day, Week and Month views over the loaded tasks: filtered once, sorted per day.
public struct PlanningAgenda: Sendable {
    /// The period the tasks were loaded for; nil while nothing is loaded.
    public let loaded: DayRange?
    /// The tasks the filter keeps.
    public let tasks: [PlanningTask]
    private let byDay: [CalendarDay: [PlanningTask]]

    public init(tasks: [PlanningTask], filter: PlanningFilter, me: String, teams: [Team], loaded: DayRange?) {
        let visible = tasks.filter { filter.matches($0, me: me, teams: teams) }
        var byDay: [CalendarDay: [PlanningTask]] = [:]
        for day in loaded.map(Array.init) ?? [] {
            byDay[day] = visible.filter { $0.occursOn(day) }.sortedForDay()
        }
        self.loaded = loaded
        self.tasks = visible
        self.byDay = byDay
    }

    /// The loaded period holds this day: no task there means nothing planned, not "still loading".
    public func covers(_ day: CalendarDay) -> Bool { loaded?.contains(day) ?? false }

    /// Tasks of a day, a task over several days on each of its days, in the order of the day.
    public func tasks(on day: CalendarDay) -> [PlanningTask] {
        if covers(day) { return byDay[day] ?? [] }
        return tasks.filter { $0.occursOn(day) }.sortedForDay()
    }

    /// Dots under a day of the week strip: one per distinct project, 3 at most (one colour).
    public func stripDots(on day: CalendarDay) -> Int {
        var seen = Set<String>()
        for task in tasks(on: day) { seen.insert(task.projectId) }
        return Swift.min(seen.count, 3)
    }

    /// Dots under a day of the month view: the distinct project colours (a project without colour gives none).
    public func monthDots(on day: CalendarDay, references: References) -> MonthDots {
        var colors: [String] = []
        for task in tasks(on: day) {
            guard let color = task.project?.color ?? references.project(task.projectId)?.color else { continue }
            if !colors.contains(color) { colors.append(color) }
        }
        return MonthDots(colors: colors.prefix(3).map { RGBColor(hex: $0) }, more: Swift.max(0, colors.count - 3))
    }

    /// Days of the week view from its Monday: a weekend day without task nor holiday is left out.
    public func weekDays(of day: CalendarDay, references: References) -> [CalendarDay] {
        let monday = day.monday
        return (0..<7).map { monday.adding(days: $0) }.filter { day in
            !(day.isWeekend && tasks(on: day).isEmpty && references.holiday(on: day) == nil)
        }
    }
}

/// A day of the Upcoming screen and the user's tasks on it.
public struct UpcomingDay: Equatable, Sendable, Identifiable {
    public let day: CalendarDay
    public let tasks: [PlanningTask]
    public var id: CalendarDay { day }
}

extension PlanningAgenda {
    /// The user's own tasks from today to 30 days later, day by day (whatever the planning filter); days without
    /// a task are left out, a task over several days is under each of them.
    public static func upcoming(_ tasks: [PlanningTask], me: String, today: CalendarDay) -> [UpcomingDay] {
        let mine = tasks.filter { $0.userIds.contains(me) }
        return PlanningPeriod.upcoming(today: today).compactMap { day in
            let list = mine.filter { $0.occursOn(day) }.sortedForDay()
            return list.isEmpty ? nil : UpcomingDay(day: day, tasks: list)
        }
    }
}
