import Testing
@testable import HumbleCore

/// `GridLayoutTest` (test 59) and the other rules of the team grid (spec 02 §2.10).
@Suite struct GridLayoutTests {
    private let monday = day("2026-11-02")

    @Test func halfDaysFollowTheWebRule() {
        #expect(GridLayout.partOf(task("a", "2026-11-02")) == .whole)
        #expect(GridLayout.partOf(task("b", "2026-11-02", from: "08:00:00", to: "12:00:00")) == .morning)
        #expect(GridLayout.partOf(task("c", "2026-11-02", from: "14:00:00", to: "17:00:00")) == .afternoon)
        #expect(GridLayout.partOf(task("d", "2026-11-02", from: "10:00:00", to: "15:00:00")) == .whole)
        // Several days: always whole days
        #expect(GridLayout.partOf(task("e", "2026-11-02", "2026-11-03", from: "14:00:00")) == .whole)
        // Noon is fixed; unpadded times compare padded; no end means the whole day unless it starts after noon
        #expect(GridLayout.partOf(task("f", "2026-11-02", from: "12:00")) == .afternoon)
        #expect(GridLayout.partOf(task("g", "2026-11-02", from: "9:00", to: "9:30")) == .morning)
        #expect(GridLayout.partOf(task("h", "2026-11-02", from: "09:00")) == .whole)
        #expect(GridLayout.partOf(task("i", "2026-11-02", from: " ", to: "10:00")) == .whole)
        #expect(GridLayout.partOf(task("j", "2026-11-02", "2026-11-02", from: "14:00")) == .afternoon)
    }

    @Test func aMorningAndAnAfternoonShareALineAndOverlapsStack() {
        let bars = Dictionary(uniqueKeysWithValues: GridLayout.bars([
            task("am", "2026-11-03", from: "08:00:00", to: "12:00:00"),
            task("pm", "2026-11-03", from: "14:00:00", to: "17:00:00"),
            task("week", "2026-11-02", "2026-11-06"),
        ], start: monday, days: 7).map { ($0.task.id, $0) })
        // Several days first, then by time
        #expect(bars["week"]?.lane == 0)
        #expect(bars["am"]?.lane == 1)
        #expect(bars["pm"]?.lane == 1)
        #expect(bars["week"]?.first == 0 && bars["week"]?.last == 4)
        #expect(bars["am"]?.halfDays == 2...2 && bars["pm"]?.halfDays == 3...3)
    }

    @Test func wholeDaysAndTimedTasksOfTheSameDay() {
        let bars = GridLayout.bars([
            task("pm", "2026-11-03", from: "14:00"),
            task("all", "2026-11-03"),
            task("pm2", "2026-11-03", from: "13:00", to: "15:00"),
        ], start: monday, days: 7)
        // Whole days before timed tasks, then by start time: the two afternoons stack
        #expect(bars.map(\.task.id) == ["all", "pm2", "pm"])
        #expect(bars.map(\.lane) == [0, 1, 2])
    }

    @Test func equalTasksSortByUpdateThenId() {
        var b = task("b", "2026-11-03", from: "08:00", to: "09:00")
        var a = task("a", "2026-11-03", from: "08:00", to: "09:00")
        b.updatedAt = "2026-11-01T10:00:00Z"
        a.updatedAt = "2026-11-02T10:00:00Z"
        #expect(GridLayout.bars([a, b], start: monday, days: 7).map(\.task.id) == ["b", "a"])
        #expect(GridLayout.bars([task("y", "2026-11-03"), task("x", "2026-11-03")], start: monday, days: 7).map(\.task.id) == ["x", "y"])
    }

    @Test func barsAreCutAtTheEdgesOfThePeriod() {
        let bars = GridLayout.bars([task("long", "2026-10-28", "2026-11-12"), task("before", "2026-10-01"),
                                    task("after", "2026-12-01")], start: monday, days: 7)
        #expect(bars.count == 1)
        let bar = bars[0]
        #expect(bar.first == 0 && bar.last == 6)
        #expect(bar.continuesBefore && bar.continuesAfter)
        let edge = GridLayout.bars([task("end", "2026-11-08", "2026-11-09")], start: monday, days: 7)[0]
        #expect(edge.first == 6 && edge.last == 6 && !edge.continuesBefore && edge.continuesAfter)
    }

    @Test func unreadableDatesAndReversedEnds() {
        let bars = GridLayout.bars([task("bad", "soon"), task("reversed", "2026-11-04", "2026-11-03")], start: monday, days: 7)
        #expect(bars.map(\.task.id) == ["reversed"])
        #expect(bars[0].first == 2 && bars[0].last == 2)
        #expect(GridLayout.bars([task("a", "2026-11-03")], start: monday, days: 0).isEmpty)
    }

    @Test func rowsGroupedByTeamInOrderWithTheTasksOfEachPerson() {
        let teams = [Team(id: "t2", name: "B", sortOrder: 2), Team(id: "t1", name: "A", sortOrder: 1)]
        let users = [
            User(id: "u3", name: "Zed", teamId: "t1", sortOrder: 2),
            User(id: "u1", name: "Ann", teamId: "t1", sortOrder: 1),
            User(id: "u2", name: "Bob", teamId: "t2"),
            User(id: "u4", name: "Solo"),
        ]
        let tasks = [task("shared", "2026-11-04", users: ["u1", "u2"]), task("other", "2026-11-04", users: ["u1"], project: "p2")]
        let groups = GridLayout.groups(users, teams: teams, tasks: tasks, filter: PlanningFilter(people: .all), start: monday, days: 7)
        #expect(groups.map(\.team?.id) == ["t1", "t2", nil])
        #expect(groups[0].rows.map(\.user.id) == ["u1", "u3"])
        // One bar per person on a shared task; two whole days on the same day stack; the project filter picks the bars
        #expect(groups[0].rows[0].lanes == 2)
        #expect(groups[0].rows[1].lanes == 0)
        #expect(groups[1].rows[0].bars.map(\.task.id) == ["shared"])
        let filtered = GridLayout.groups(users, teams: teams, tasks: tasks,
                                         filter: PlanningFilter(people: .all, specificProjects: true, projectIds: ["p2"]),
                                         start: monday, days: 7)
        #expect(filtered[0].rows[0].bars.map(\.task.id) == ["other"])
        let byStatus = GridLayout.groups(users, teams: teams, tasks: tasks,
                                         filter: PlanningFilter(people: .all, specificStatuses: true), start: monday, days: 7)
        #expect(byStatus.flatMap(\.rows).allSatisfy { $0.bars.isEmpty })
        #expect(groups.map(\.id) == ["t1", "t2", "none"])
    }

    @Test func teamsOfTheSameOrderSortByNameAndUnknownTeamsHaveNone() {
        let teams = [Team(id: "tb", name: "beta"), Team(id: "ta", name: "Alpha"), Team(id: "tc", name: "Gamma", sortOrder: -1)]
        let users = [User(id: "u1", name: "One", teamId: "tb"), User(id: "u2", name: "Two", teamId: "gone"),
                     User(id: "u3", name: "Three", teamId: "ta"), User(id: "u4", name: "Four", teamId: "tc"),
                     User(id: "u5", name: "abel", teamId: "ta"), User(id: "u6", name: "Bart", teamId: "ta")]
        let groups = GridLayout.groups(users, teams: teams, tasks: [], filter: PlanningFilter(people: .all), start: monday, days: 7)
        #expect(groups.map(\.team?.id) == ["tc", "ta", "tb", nil])
        #expect(groups[1].rows.map(\.user.id) == ["u5", "u6", "u3"])
        #expect(groups[3].rows.map(\.user.id) == ["u2"])
        #expect(GridLayout.showsTeamHeaders(groups))
    }

    @Test func theTeamHeaderIsHiddenOnlyForASingleGroupWithoutTeam() {
        let alone = GridLayout.groups([User(id: "u1", name: "A")], teams: [], tasks: [], filter: PlanningFilter(people: .all),
                                      start: monday, days: 7)
        #expect(!GridLayout.showsTeamHeaders(alone))
        let team = GridLayout.groups([User(id: "u1", name: "A", teamId: "t1")], teams: [Team(id: "t1", name: "T")], tasks: [],
                                     filter: PlanningFilter(people: .all), start: monday, days: 7)
        #expect(GridLayout.showsTeamHeaders(team))
        #expect(!GridLayout.showsTeamHeaders([]))
    }

    @Test func personAndTeamFiltersPickTheRows() {
        let teams = [Team(id: "t1", name: "", userIds: ["u1"])]
        let users = [User(id: "u1", name: "", teamId: "t1"), User(id: "u2", name: ""), User(id: "u3", name: "", teamId: "t1")]
        // The default filter (Mine) shows only my own row
        #expect(GridLayout.people(users, filter: PlanningFilter(people: .mine), me: "u2", teams: teams).map(\.id) == ["u2"])
        #expect(GridLayout.people(users, filter: PlanningFilter(), me: "u2", teams: teams).map(\.id) == ["u2"])
        // A team keeps the people it lists and those whose team it is
        #expect(GridLayout.people(users, filter: PlanningFilter(people: .all, specificTeams: true, teamIds: ["t1"]), me: "u2",
                                  teams: teams).map(\.id) == ["u1", "u3"])
        #expect(GridLayout.people(users, filter: PlanningFilter(people: .specific, userIds: ["u9"]), me: "u2", teams: teams).isEmpty)
        #expect(GridLayout.people(users, filter: PlanningFilter(people: .specific, userIds: ["u3", "u2"], specificTeams: true,
                                                                teamIds: ["t1"]), me: "u2", teams: teams).map(\.id) == ["u3"])
    }

    @Test func columnsOfThePeriod() {
        let period = PlanningPeriod.grid(of: day("2026-11-11"))
        let columns = GridLayout.columns(period, today: day("2026-11-09"),
                                         holidays: [Holiday(id: "h", date: "2026-11-11", label: "Armistice")])
        #expect(columns.count == 42)
        #expect(columns[0].day == day("2026-10-26") && columns[0].showsWeekNumber)
        #expect(!columns[1].showsWeekNumber && columns[7].showsWeekNumber && columns[7].isMonday)
        #expect(columns[5].isWeekend && columns[6].isWeekend && !columns[4].isWeekend)
        #expect(columns.filter(\.isToday).map(\.index) == [14])
        #expect(columns[16].holiday?.shownLabel == "Armistice")
        #expect(columns[0].day.isoWeek == 44)
    }

    @Test func tapToCreateOnlyOnRowsOfAssignablePeople() {
        let users = [User(id: "me", name: "", teamId: "t1"), User(id: "mate", name: "", teamId: "t1"), User(id: "far", name: "")]
        func ids(_ permissions: String...) -> Set<String> {
            GridLayout.creatableUserIds(Access(userId: "me", teamId: "t1", permissions: Set(permissions), isAdmin: false), users: users)
        }
        #expect(ids("tasks:create", "scope:modify_all") == ["me", "mate", "far"])
        #expect(ids("tasks:create", "scope:modify_team") == ["me", "mate"])
        #expect(ids("tasks:create", "scope:modify_own") == ["me"])
        #expect(ids("scope:modify_all").isEmpty)
        #expect(ids("tasks:create").isEmpty)
    }

    @Test func barColourComesFromTheProjectThenTheStatus() {
        let refs = References(projects: [Project(id: "p1", name: "", color: "#112233"), Project(id: "p2", name: "")],
                              statuses: [TaskStatus(id: "s1", name: "", color: "#445566")])
        #expect(GridLayout.barColor(task("a", "2026-11-02", project: "p1"), references: refs) == RGBColor(hex: "#112233"))
        #expect(GridLayout.barColor(task("a", "2026-11-02", project: "p2"), references: refs) == RGBColor(hex: "#445566"))
        #expect(GridLayout.barColor(task("a", "2026-11-02", project: "p2", status: "s9"), references: refs) == nil)
    }
}
