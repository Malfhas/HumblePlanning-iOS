import XCTest

/// Changes made elsewhere (the REST API as the administrator) reach the screen by themselves, like RealtimeTest of
/// the Android app: no gesture once the app shows the planning or the task.
final class RealtimeUITests: XCTestCase {
    /// Socket event, then the reload of the screen.
    private let realtime: TimeInterval = 20

    override func setUpWithError() throws {
        try TestServer.require()
        continueAfterFailure = false
    }

    /// Signed in as Emma on today's page, real time connected: a task made now shows without any gesture.
    @MainActor
    private func planningWithRealtime(_ server: PlanningServer, emma: String, today: String) throws -> Driver {
        let ui = Driver(test: self, shots: TestServer.shots)
        ui.launch(as: .seeded("emma"), "-planning_view", "Day")
        ui.expectSignedIn()
        ui.expectVisible(ui.heading(PlanningDays().long(PlanningDays().today)))
        // A probe: once it shows, real time is connected (connecting reloads the planning too)
        let probe = testTitle("probe")
        _ = try server.createTask(probe, for: [emma], on: today)
        ui.expect(ui.cardIfAny(probe), timeout: realtime)
        return ui
    }

    @MainActor
    func testPlanningFollowsCreateEditDelete() throws {
        let server = try PlanningServer(self)
        let days = PlanningDays()
        let emma = try server.userId("emma")
        let ui = try planningWithRealtime(server, emma: emma, today: days.iso(days.today))

        let title = testTitle("live")
        let id = try server.createTask(title, for: [emma], on: days.iso(days.today))
        ui.expect(ui.cardIfAny(title), timeout: realtime)
        ui.shot("created")

        let renamed = testTitle("renamed")
        try server.renameTask(id, to: renamed)
        ui.expect(ui.cardIfAny(renamed), timeout: realtime)
        ui.expectGone(ui.cardIfAny(title), timeout: realtime)
        ui.shot("renamed")

        try server.deleteTask(id)
        ui.expectGone(ui.cardIfAny(renamed), timeout: realtime)
        ui.shot("deleted")
    }

    @MainActor
    func testOpenTaskFollowsChangesAndSaysWhenDeleted() throws {
        let server = try PlanningServer(self)
        let days = PlanningDays()
        let emma = try server.userId("emma")
        let ui = try planningWithRealtime(server, emma: emma, today: days.iso(days.today))
        let app = ui.app

        let title = testTitle("live detail")
        let id = try server.createTask(title, for: [emma], on: days.iso(days.today))
        ui.card(title).tap()
        ui.expect(app.staticTexts[title].firstMatch, timeout: 15)
        ui.expect(app.buttons["Edit"])

        let renamed = testTitle("live detail renamed")
        try server.renameTask(id, to: renamed)
        ui.expect(app.staticTexts[renamed].firstMatch, timeout: realtime)
        ui.shot("detail-renamed")

        try server.deleteTask(id)
        ui.expect(app.staticTexts["This task no longer exists."], timeout: realtime)
        ui.expectGone(app.buttons["Edit"])
        ui.shot("detail-deleted")
        app.buttons["Back"].firstMatch.tap()
        ui.expectGone(app.staticTexts["This task no longer exists."])
        ui.expectGone(ui.cardIfAny(renamed))
    }
}
