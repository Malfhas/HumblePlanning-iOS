import Testing
@testable import HumbleCore

/// What the Day, Week, Month and Upcoming views list (spec 02 §2.6–2.9, §4).
@Suite struct PlanningAgendaTests {
    private let week = day("2026-11-02")...day("2026-11-08")

    private func agenda(_ tasks: [PlanningTask], filter: PlanningFilter = PlanningFilter(people: .all),
                        loaded: DayRange? = nil) -> PlanningAgenda {
        PlanningAgenda(tasks: tasks, filter: filter, me: "u1", teams: [], loaded: loaded ?? week)
    }

    @Test func aDayListsItsFilteredTasksInOrder() {
        let tasks = [
            task("late", "2026-11-04", from: "14:00"),
            task("other", "2026-11-04", users: ["u2"]),
            task("span", "2026-11-03", "2026-11-05"),
            task("early", "2026-11-04", from: "8:00"),
        ]
        let mine = agenda(tasks, filter: PlanningFilter())
        #expect(mine.tasks(on: day("2026-11-04")).map(\.id) == ["span", "early", "late"])
        #expect(mine.tasks(on: day("2026-11-05")).map(\.id) == ["span"])
        #expect(mine.tasks(on: day("2026-11-06")).isEmpty)
        #expect(agenda(tasks).tasks(on: day("2026-11-04")).map(\.id) == ["span", "other", "early", "late"])
    }

    @Test func coversTellsNothingPlannedFromNotLoaded() {
        let list = agenda([task("a", "2026-11-12")])
        #expect(list.covers(day("2026-11-02")) && list.covers(day("2026-11-08")))
        #expect(!list.covers(day("2026-11-09")))
        // Outside the loaded period the tasks are still found
        #expect(list.tasks(on: day("2026-11-12")).map(\.id) == ["a"])
        #expect(!PlanningAgenda(tasks: [], filter: PlanningFilter(), me: "u1", teams: [], loaded: nil).covers(day("2026-11-02")))
    }

    @Test func aTaskEndingBeforeItStartsIsNowhere() {
        #expect(agenda([task("odd", "2026-11-04", "2026-11-03")]).tasks(on: day("2026-11-04")).isEmpty)
    }

    @Test func emptyWeekendDaysAreLeftOutOfTheWeek() {
        let refs = References(holidays: [Holiday(id: "h", date: "2026-11-08", label: "Fête")])
        let list = agenda([task("sat", "2026-11-07", users: ["u2"])], filter: PlanningFilter())
        #expect(list.weekDays(of: day("2026-11-05"), references: refs).map(\.iso)
                == ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-08"])
        #expect(agenda([task("sat", "2026-11-07")]).weekDays(of: day("2026-11-02"), references: References()).count == 6)
    }

    @Test func stripDotsCountDistinctProjects() {
        let tasks = ["p1", "p1", "p2", "p3", "p4"].enumerated().map { task("t\($0.offset)", "2026-11-04", project: $0.element) }
        #expect(agenda(tasks).stripDots(on: day("2026-11-04")) == 3)
        #expect(agenda(Array(tasks.prefix(2))).stripDots(on: day("2026-11-04")) == 1)
        #expect(agenda(tasks).stripDots(on: day("2026-11-05")) == 0)
    }

    @Test func monthDotsShowDistinctProjectColours() {
        let refs = References(projects: [
            Project(id: "p1", name: "A", color: "#FF0000"), Project(id: "p2", name: "B", color: "#ff0000"),
            Project(id: "p3", name: "C"), Project(id: "p4", name: "D", color: "bad"), Project(id: "p5", name: "E", color: "#00FF00"),
            Project(id: "p6", name: "F", color: "#FF0000"),
        ])
        var embedded = task("z", "2026-11-04", project: "p3")
        embedded.project = Project(id: "p3", name: "C", color: "#0000FF")
        let tasks = ["p1", "p2", "p3", "p4", "p5", "p6"].map { task($0, "2026-11-04", project: $0) } + [embedded]
        let dots = agenda(tasks).monthDots(on: day("2026-11-04"), references: refs)
        // "#FF0000" and "#ff0000" count apart, as on Android; a project without colour gives no dot
        #expect(dots.colors == [RGBColor(hex: "#FF0000"), RGBColor(hex: "#FF0000"), nil])
        #expect(dots.more == 2)
        let few = agenda([task("p5", "2026-11-04", project: "p5")]).monthDots(on: day("2026-11-04"), references: refs)
        #expect(few == MonthDots(colors: [RGBColor(hex: "#00FF00")], more: 0))
    }

    @Test func cardTitleFollowsTheSetting() {
        let refs = References(projects: [Project(id: "p1", name: "Roof", businessNumber: "42")])
        let titled = task("a", "2026-11-04", title: "Visit")
        let untitled = task("b", "2026-11-04", title: "  ")
        let orphan = task("c", "2026-11-04", title: "Alone", project: "gone")
        #expect(titled.cardTitle(refs, mode: .project) == "[42] Roof")
        #expect(titled.cardSubtitle(refs, mode: .project) == "Visit")
        #expect(titled.cardTitle(refs, mode: .title) == "Visit")
        #expect(titled.cardSubtitle(refs, mode: .title) == "[42] Roof")
        #expect(untitled.cardTitle(refs, mode: .title) == "[42] Roof")
        #expect(untitled.cardSubtitle(refs, mode: .title) == "")
        #expect(untitled.cardSubtitle(refs, mode: .project) == "")
        #expect(orphan.cardTitle(refs, mode: .project) == "Alone")
        #expect(orphan.cardSubtitle(refs, mode: .project) == "")
        #expect(CardTitleMode(rawValue: "title") == .title && CardTitleMode(rawValue: "project") == .project)
    }

    @Test func multiDayPositionOfTheShownDay() {
        let span = task("a", "2026-11-04", "2026-11-06")
        #expect(span.dayPosition(on: day("2026-11-04"))! == (1, 3))
        #expect(span.dayPosition(on: day("2026-11-05"))! == (2, 3))
        #expect(task("b", "2026-11-04").dayPosition(on: day("2026-11-04")) == nil)
    }

    @Test func overlapsLikeTheOfflineCopy() {
        #expect(task("a", "2026-11-01", "2026-11-02").overlaps(week))
        #expect(task("a", "2026-11-08").overlaps(week))
        #expect(!task("a", "2026-11-09").overlaps(week))
        #expect(!task("a", "2026-10-30", "2026-11-01").overlaps(week))
    }

    @Test func upcomingListsMyNextThirtyDays() {
        let tasks = [
            task("today", "2026-11-05"),
            task("span", "2026-11-06", "2026-11-07", from: "08:00"),
            task("other", "2026-11-06", users: ["u2"]),
            task("last", "2026-12-05"),
            task("after", "2026-12-06"),
            task("before", "2026-11-04"),
        ]
        let days = PlanningAgenda.upcoming(tasks, me: "u1", today: day("2026-11-05"))
        #expect(days.map(\.day.iso) == ["2026-11-05", "2026-11-06", "2026-11-07", "2026-12-05"])
        #expect(days.map { $0.tasks.map(\.id) } == [["today"], ["span"], ["span"], ["last"]])
    }

    @Test func referenceLookups() {
        let refs = References(places: [decoded(#"{"id": "pl", "name": "Depot"}"#)], resources: [decoded(#"{"id": "r", "name": "Van"}"#)],
                              holidays: [Holiday(id: "h", date: "2026-11-11", label: " ")])
        #expect(refs.place("pl")?.name == "Depot" && refs.place(nil) == nil)
        #expect(refs.resource("r")?.name == "Van")
        #expect(refs.holiday(on: day("2026-11-11"))?.shownLabel == nil)
        #expect(refs.holiday(on: day("2026-11-12")) == nil)
    }
}
