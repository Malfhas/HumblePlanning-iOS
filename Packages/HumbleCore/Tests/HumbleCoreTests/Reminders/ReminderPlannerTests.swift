import Foundation
import Testing
@testable import HumbleCore

struct ReminderPlannerTests {
    let paris = TimeZone(identifier: "Europe/Paris")!

    func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func plan(_ tasks: [PlanningTask], offset: ReminderOffset = .fifteenMinutes) -> [Reminder] {
        ReminderPlanner.plan(tasks, defaultStart: "08:00", offset: offset, now: date(5, 7, 0), timeZone: paris) { ($0.id, "detail") }
    }

    @Test func timedTask() {
        let reminders = plan([PlanningTask(id: "t", startDate: "2026-11-05", startTime: "09:30:00")])
        #expect(reminders == [Reminder(taskId: "t", fireAt: date(5, 9, 15), title: "t", text: "09:30 · detail")])
    }

    @Test func allDayTaskUsesTheMorningStart() {
        #expect(plan([PlanningTask(id: "t", startDate: "2026-11-05")]).first?.fireAt == date(5, 7, 45))
    }

    @Test func pastAndUnreadableAreSkipped() {
        #expect(plan([PlanningTask(id: "a", startDate: "2026-11-05", startTime: "07:10"),
                      PlanningTask(id: "b", startDate: "2026-11-04", startTime: "10:00"),
                      PlanningTask(id: "c", startDate: "soon")]).isEmpty)
        #expect(plan([PlanningTask(id: "t", startDate: "2026-11-05", startTime: "10:00")], offset: .none).isEmpty)
    }

    @Test func sortedAndCapped() {
        let tasks = (0..<80).map { PlanningTask(id: "t\($0)", startDate: "2026-11-\(String(format: "%02d", 6 + $0 % 8))", startTime: "10:00") }
            + [PlanningTask(id: "soon", startDate: "2026-11-05", startTime: "10:00")]
        let reminders = plan(tasks)
        #expect(reminders.count == ReminderPlanner.maximum)
        #expect(reminders.first?.taskId == "soon")
        #expect(zip(reminders, reminders.dropFirst()).allSatisfy { $0.fireAt <= $1.fireAt })
    }

    @Test func times() {
        #expect(ReminderPlanner.parseTime("09:30:00")! == (9, 30))
        #expect(ReminderPlanner.parseTime("bad") == nil)
        #expect(ReminderPlanner.parseTime("24:00") == nil)
        let fallback = ReminderPlanner.plan([PlanningTask(id: "t", startDate: "2026-11-06", startTime: "bad")], defaultStart: "also bad",
                                            offset: .fifteenMinutes, now: date(5, 7, 0), timeZone: paris) { ($0.id, "") }
        #expect(fallback.first?.fireAt == date(6, 7, 45))
    }

    @Test func offsets() {
        #expect(ReminderOffset(stored: "weird") == .fifteenMinutes)
        #expect(ReminderOffset(stored: "1j").minutes == 1440)
    }

    @Test func labels() {
        let references = References(projects: [Project(id: "p", name: "Tilleuls", businessNumber: "B26-014")])
        let people = [User(id: "u", name: "Turner", firstName: "Liam")]
        #expect(ReminderPlanner.label(PlanningTask(id: "t", startDate: "2026-11-05", projectId: "p", users: people), references: references)
            == ("[B26-014] Tilleuls", "Liam Turner"))
        #expect(ReminderPlanner.label(PlanningTask(id: "t", title: "Visite", startDate: "2026-11-05", projectId: "p"), references: references)
            == ("[B26-014] Tilleuls", "Visite"))
    }
}
