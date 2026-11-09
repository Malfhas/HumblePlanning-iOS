import Foundation

/// Part of a day a bar covers: the morning and afternoon halves of the web planning.
public enum DayPart: Sendable, Hashable {
    case whole, morning, afternoon
}

/// A task on one person's row: columns `first`…`last` of the period (included), its line in the row, and whether
/// it goes on before or after the period.
public struct GridBar: Sendable, Hashable, Identifiable {
    public let task: PlanningTask
    public let first: Int
    public let last: Int
    public let lane: Int
    public let part: DayPart
    public let continuesBefore: Bool
    public let continuesAfter: Bool

    public var id: String { task.id }
    /// First and last half day covered (two per column: morning, afternoon).
    public var halfDays: ClosedRange<Int> { Self.halfDays(first: first, last: last, part: part) }

    static func halfDays(first: Int, last: Int, part: DayPart) -> ClosedRange<Int> {
        (first * 2 + (part == .afternoon ? 1 : 0))...(last * 2 + (part == .morning ? 0 : 1))
    }
}

public struct GridRow: Sendable, Hashable, Identifiable {
    public let user: User
    public let bars: [GridBar]
    /// Lines of bars in the row (0 without task).
    public let lanes: Int
    public var id: String { user.id }
}

/// People of one team, in the order of the web planning; `team` is nil for those without a team.
public struct GridGroup: Sendable, Hashable, Identifiable {
    public let team: Team?
    public let rows: [GridRow]
    /// Key of its collapsed state: the team id, or `"none"`.
    public var id: String { team?.id ?? GridLayout.noTeamKey }
}

/// What a day column of the grid looks like.
public struct GridColumn: Sendable, Hashable, Identifiable {
    public let index: Int
    public let day: CalendarDay
    public let isToday: Bool
    public let holiday: Holiday?
    public var id: CalendarDay { day }
    public var isWeekend: Bool { day.isWeekend }
    /// Monday lines are drawn stronger.
    public var isMonday: Bool { day.isMonday }
    /// The week number is written on Mondays and on the first column.
    public var showsWeekNumber: Bool { day.isMonday || index == 0 }
}

/// The team grid (the web "schedule"): one row per person grouped by team, one column per day, the tasks as bars.
public enum GridLayout {
    public static let noTeamKey = "none"

    /// Same rule as the web planning (`time-slots.ts`): no start time = whole day, starting at noon or later =
    /// afternoon, ending by noon = morning. Only a one-day task takes half a day; noon is fixed, not the server's hours.
    public static func partOf(_ task: PlanningTask) -> DayPart {
        if task.startDate != task.lastDate { return .whole }
        guard let start = time(task.startTime) else { return .whole }
        if start >= noon { return .afternoon }
        if let end = time(task.endTime), end <= noon { return .morning }
        return .whole
    }

    /// Bars of one row over `days` days from `start`. Each bar takes the first free line, counted in half days:
    /// a morning and an afternoon task of the same day share a line, which keeps the rows low.
    public static func bars(_ tasks: [PlanningTask], start: CalendarDay, days: Int) -> [GridBar] {
        guard days > 0 else { return [] }
        let lastDay = start.adding(days: days - 1)
        let items: [(task: PlanningTask, from: CalendarDay, to: CalendarDay)] = tasks.compactMap { task in
            guard let from = task.startDay else { return nil }
            let to = task.lastDay.flatMap { $0 >= from ? $0 : nil } ?? from
            return to < start || from > lastDay ? nil : (task, from, to)
        }
        let sorted = items.sorted { a, b in
            if a.from != b.from { return a.from < b.from }
            func timed(_ item: (task: PlanningTask, from: CalendarDay, to: CalendarDay)) -> Int {
                isBlank(item.task.startTime) || item.from != item.to ? 0 : 1
            }
            if timed(a) != timed(b) { return timed(a) < timed(b) }
            let ta = a.task.startTime.map(PlanningFormat.paddedTime) ?? "", tb = b.task.startTime.map(PlanningFormat.paddedTime) ?? ""
            if ta != tb { return ta < tb }
            let ua = a.task.updatedAt ?? "", ub = b.task.updatedAt ?? ""
            if ua != ub { return ua < ub }
            return a.task.id < b.task.id
        }
        var lines: [[Bool]] = []
        return sorted.map { task, from, to in
            let first = max(0, start.days(to: from)), last = min(days - 1, start.days(to: to))
            let part = partOf(task)
            let halves = GridBar.halfDays(first: first, last: last, part: part)
            let lane: Int
            if let free = lines.firstIndex(where: { line in halves.allSatisfy { !line[$0] } }) {
                lane = free
            } else {
                lines.append(Array(repeating: false, count: days * 2))
                lane = lines.count - 1
            }
            for half in halves { lines[lane][half] = true }
            return GridBar(task: task, first: first, last: last, lane: lane, part: part,
                           continuesBefore: from < start, continuesAfter: to > lastDay)
        }
    }

    /// People with a row: the person filter (the default "Mine" shows only the user's own row) and the team filter
    /// (members listed by the team, or people whose team it is). People are shown even without task.
    public static func people(_ users: [User], filter: PlanningFilter, me: String, teams: [Team]) -> [User] {
        let members = filter.specificTeams ? Set(teams.filter { filter.teamIds.contains($0.id) }.flatMap(\.userIds)) : nil
        return users.filter { user in
            let person = switch filter.people {
            case .all: true
            case .mine: user.id == me
            case .specific: filter.userIds.contains(user.id)
            }
            guard person else { return false }
            guard let members else { return true }
            return members.contains(user.id) || user.teamId.map(filter.teamIds.contains) == true
        }
    }

    /// Rows grouped by team, in the default order of the web planning: teams by their order then name, people by
    /// their order then name, people without a known team last. The project and status filters pick the bars; a
    /// shared task gives a bar on the row of each of its people. `tasks` are the loaded ones, not filtered.
    public static func groups(_ users: [User], teams: [Team], tasks: [PlanningTask], filter: PlanningFilter,
                              start: CalendarDay, days: Int) -> [GridGroup] {
        var byUser: [String: [PlanningTask]] = [:]
        for task in tasks {
            if filter.specificProjects && !filter.projectIds.contains(task.projectId) { continue }
            if filter.specificStatuses && !filter.statusIds.contains(task.statusId) { continue }
            for id in task.userIds { byUser[id, default: []].append(task) }
        }
        let teamById = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var keys: [String?] = []
        var members: [String?: [User]] = [:]
        for user in users {
            let key = user.teamId.flatMap { teamById[$0] }?.id
            if members[key] == nil { keys.append(key) }
            members[key, default: []].append(user)
        }
        let orderedKeys = keys.enumerated().sorted { a, b in
            let ta = a.element.flatMap { teamById[$0] }, tb = b.element.flatMap { teamById[$0] }
            if (ta == nil) != (tb == nil) { return tb == nil }
            if (ta?.sortOrder ?? 0) != (tb?.sortOrder ?? 0) { return (ta?.sortOrder ?? 0) < (tb?.sortOrder ?? 0) }
            let na = ta?.name.lowercased() ?? "", nb = tb?.name.lowercased() ?? ""
            return na != nb ? na < nb : a.offset < b.offset
        }.map(\.element)
        return orderedKeys.map { key in
            let people = (members[key] ?? []).enumerated().sorted { a, b in
                if a.element.sortOrder != b.element.sortOrder { return a.element.sortOrder < b.element.sortOrder }
                let na = a.element.displayName.lowercased(), nb = b.element.displayName.lowercased()
                return na != nb ? na < nb : a.offset < b.offset
            }.map(\.element)
            return GridGroup(team: key.flatMap { teamById[$0] }, rows: people.map { user in
                let bars = bars(byUser[user.id] ?? [], start: start, days: days)
                return GridRow(user: user, bars: bars, lanes: (bars.map(\.lane).max() ?? -1) + 1)
            })
        }
    }

    /// The team header is hidden only when everyone is in the single "no team" group.
    public static func showsTeamHeaders(_ groups: [GridGroup]) -> Bool {
        groups.count > 1 || groups.first?.team != nil
    }

    /// The day columns of the period.
    public static func columns(_ period: DayRange, today: CalendarDay, holidays: [Holiday]) -> [GridColumn] {
        period.enumerated().map { index, day in
            GridColumn(index: index, day: day, isToday: day == today, holiday: holidays.first { $0.date == day.iso })
        }
    }

    /// People on whose row a tap on an empty day opens a new task for them.
    public static func creatableUserIds(_ access: Access, users: [User]) -> Set<String> {
        access.canCreateTask ? Set(access.assignableUsers(users).map(\.id)) : []
    }

    /// Colour of a bar: the project's, else the status's; nil = the theme's primary colour.
    public static func barColor(_ task: PlanningTask, references: References) -> RGBColor? {
        RGBColor(hex: task.projectOf(references)?.color) ?? RGBColor(hex: task.statusOf(references)?.color)
    }

    private static let noon = "12:00"

    private static func isBlank(_ text: String?) -> Bool { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private static func time(_ text: String?) -> String? {
        guard let text, !isBlank(text) else { return nil }
        return PlanningFormat.paddedTime(text)
    }
}
