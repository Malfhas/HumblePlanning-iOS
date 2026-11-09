import Foundation
import Testing
@testable import HumbleCore

/// `PlanningFilterTest` (test 58), the badge and the persistence of the filter.
@Suite struct PlanningFilterTests {
    private let teams = [Team(id: "t1", name: "", userIds: ["u1", "u2"]), Team(id: "t2", name: "", userIds: ["u3"])]
    private let shown = task("x", "2026-11-05", users: ["u1"], project: "p1", status: "s1")

    private func matches(_ filter: PlanningFilter) -> Bool { filter.matches(shown, me: "me", teams: teams) }

    @Test func mineOnlyKeepsMyTasks() {
        #expect(!matches(PlanningFilter(people: .mine)))
        #expect(PlanningFilter(people: .mine).matches(shown, me: "u1", teams: teams))
    }

    @Test func everyoneKeepsAll() {
        #expect(matches(PlanningFilter(people: .all)))
    }

    @Test func pickedPeople() {
        #expect(matches(PlanningFilter(people: .specific, userIds: ["u1", "u9"])))
        #expect(!matches(PlanningFilter(people: .specific, userIds: ["u9"])))
        #expect(!matches(PlanningFilter(people: .specific)))
    }

    @Test func teamsMatchThroughTheirMembers() {
        #expect(matches(PlanningFilter(people: .all, specificTeams: true, teamIds: ["t1"])))
        #expect(!matches(PlanningFilter(people: .all, specificTeams: true, teamIds: ["t2"])))
        #expect(!matches(PlanningFilter(people: .all, specificTeams: true)))
    }

    @Test func projectsAndStatuses() {
        #expect(matches(PlanningFilter(people: .all, specificProjects: true, projectIds: ["p1"])))
        #expect(!matches(PlanningFilter(people: .all, specificProjects: true, projectIds: ["p2"])))
        #expect(!matches(PlanningFilter(people: .all, specificProjects: true)))
        #expect(matches(PlanningFilter(people: .all, specificStatuses: true, statusIds: ["s1"])))
        #expect(!matches(PlanningFilter(people: .all, specificStatuses: true)))
    }

    @Test func everyFilterMustMatch() {
        let filter = PlanningFilter(people: .specific, userIds: ["u1"], specificTeams: true, teamIds: ["t1"],
                                    specificProjects: true, projectIds: ["p1"], specificStatuses: true, statusIds: ["s2"])
        #expect(!matches(filter))
    }

    @Test func badgeCountsTheSpecificChoices() {
        #expect(PlanningFilter().activeCount == 0)
        #expect(PlanningFilter(people: .all).activeCount == 0)
        #expect(PlanningFilter(people: .specific).activeCount == 1)
        #expect(PlanningFilter(people: .specific, specificTeams: true, specificProjects: true, specificStatuses: true).activeCount == 4)
        #expect(!PlanningFilter().showsPeople && PlanningFilter(people: .all).showsPeople)
    }

    @Test func pickingPeopleStartsFromMe() {
        #expect(PlanningFilter().choosingPeople(.specific, me: "me").userIds == ["me"])
        #expect(PlanningFilter(userIds: ["u2"]).choosingPeople(.specific, me: "me").userIds == ["u2"])
        #expect(PlanningFilter().choosingPeople(.all, me: "me") == PlanningFilter(people: .all))
    }

    @Test func keptAsJSONAndReadWithDefaults() throws {
        let filter = PlanningFilter(people: .specific, userIds: ["u1"], specificProjects: true, projectIds: ["p1", "p2"])
        let data = try JSONEncoder().encode(filter)
        #expect(try JSONDecoder().decode(PlanningFilter.self, from: data) == filter)
        #expect(try JSONDecoder().decode(PlanningFilter.self, from: Data("{}".utf8)) == PlanningFilter())
        let android = #"{"people":"All","specificStatuses":true,"statusIds":["s1"]}"#
        #expect(try JSONDecoder().decode(PlanningFilter.self, from: Data(android.utf8))
                == PlanningFilter(people: .all, specificStatuses: true, statusIds: ["s1"]))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PlanningFilter.self, from: Data(#"{"people":"Team"}"#.utf8)) }
    }
}
