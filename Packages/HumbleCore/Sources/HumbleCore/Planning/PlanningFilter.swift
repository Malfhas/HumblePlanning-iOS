import Foundation

/// Whose tasks the planning shows.
public enum PeopleFilter: String, Codable, CaseIterable, Sendable {
    case mine = "Mine", all = "All", specific = "Specific"
}

/// Filters of the planning, applied in the app on the tasks the server returned; kept from one launch to the
/// next (cleared on sign-out or a change of account or server). A specific choice with nothing picked matches
/// nothing.
public struct PlanningFilter: Codable, Sendable, Hashable {
    public var people: PeopleFilter
    /// Used when `people` is `.specific`.
    public var userIds: Set<String>
    /// false = every team.
    public var specificTeams: Bool
    public var teamIds: Set<String>
    /// false = every project.
    public var specificProjects: Bool
    public var projectIds: Set<String>
    /// false = every status.
    public var specificStatuses: Bool
    public var statusIds: Set<String>

    public init(people: PeopleFilter = .mine, userIds: Set<String> = [], specificTeams: Bool = false, teamIds: Set<String> = [],
                specificProjects: Bool = false, projectIds: Set<String> = [], specificStatuses: Bool = false,
                statusIds: Set<String> = []) {
        self.people = people
        self.userIds = userIds
        self.specificTeams = specificTeams
        self.teamIds = teamIds
        self.specificProjects = specificProjects
        self.projectIds = projectIds
        self.specificStatuses = specificStatuses
        self.statusIds = statusIds
    }

    /// A missing key takes its default, so that a filter saved by an older version still reads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            people: try c.decodeIfPresent(PeopleFilter.self, forKey: .people) ?? .mine,
            userIds: try c.decodeIfPresent(Set<String>.self, forKey: .userIds) ?? [],
            specificTeams: try c.decodeIfPresent(Bool.self, forKey: .specificTeams) ?? false,
            teamIds: try c.decodeIfPresent(Set<String>.self, forKey: .teamIds) ?? [],
            specificProjects: try c.decodeIfPresent(Bool.self, forKey: .specificProjects) ?? false,
            projectIds: try c.decodeIfPresent(Set<String>.self, forKey: .projectIds) ?? [],
            specificStatuses: try c.decodeIfPresent(Bool.self, forKey: .specificStatuses) ?? false,
            statusIds: try c.decodeIfPresent(Set<String>.self, forKey: .statusIds) ?? []
        )
    }

    /// Badge of the filter button: the specific choices (me and everyone do not count).
    public var activeCount: Int {
        [people == .specific, specificTeams, specificProjects, specificStatuses].filter { $0 }.count
    }

    /// Cards show their people unless the planning shows only mine.
    public var showsPeople: Bool { people != .mine }

    /// Tasks of the Day, Week and Month views. The grid applies the people and team filters to its rows instead
    /// (see `GridLayout.people`).
    public func matches(_ task: PlanningTask, me: String, teams: [Team]) -> Bool {
        let ids = task.userIds
        let person = switch people {
        case .all: true
        case .mine: ids.contains(me)
        case .specific: ids.contains { userIds.contains($0) }
        }
        guard person else { return false }
        if specificTeams {
            let members = Set(teams.filter { teamIds.contains($0.id) }.flatMap(\.userIds))
            if !ids.contains(where: members.contains) { return false }
        }
        if specificProjects && !projectIds.contains(task.projectId) { return false }
        if specificStatuses && !statusIds.contains(task.statusId) { return false }
        return true
    }

    /// The people choice of the filter sheet: picking people starts from the user when nobody is picked yet.
    public func choosingPeople(_ value: PeopleFilter, me: String) -> PlanningFilter {
        var filter = self
        filter.people = value
        if value == .specific && userIds.isEmpty { filter.userIds = [me] }
        return filter
    }
}
