import XCTest

/// The alerts of the server (changes others make to my tasks), like AlertsTest of the Android app: they reach the
/// open app in real time, newest first, and open their task. There is no unread state nor badge, on Android either.
///
/// Signs in as Emma Collins; the administrator changes a task of hers created for the test, then deletes it.
final class AlertsUITests: XCTestCase {
    @MainActor
    func testAlertsArriveLiveNewestFirstAndOpenTheTask() throws {
        try TestServer.require()
        continueAfterFailure = false
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let admin = try server { try await TestAPI.admin() }
        let seeded = try server { try await admin.seeded() }
        let title = uniqueTitle("alert created")
        let retitled = uniqueTitle("alert retitled")

        ui.launch(as: .seeded("emma"), "-HPTab", "alerts")
        ui.expectSignedIn()
        ui.expect(app.navigationBars["Alerts"])
        // Loaded: the history, or nothing yet
        ui.expectGone(app.activityIndicators.firstMatch, timeout: 15)

        // Someone else gives Emma a task: the alert is listed without touching the screen
        let taskId = try server { try await admin.createTask(title, for: [seeded.userId("emma")], on: isoDay(3), seeded: seeded) }
        cleanUp { await admin.deleteTask(taskId) }
        let created = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        ui.expect(created, timeout: 20)
        XCTAssertTrue(created.label.hasPrefix(seeded.projectName + " — " + title + ", "), created.label)
        XCTAssertTrue(created.label.contains(", now"), "A fresh alert is from now: \(created.label)")

        // Then renames it: a second alert, above the first one
        try server { try await admin.updateTask(taskId, ["title": retitled]) }
        let changed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", retitled)).firstMatch
        ui.expect(changed, timeout: 20)
        XCTAssertLessThan(changed.frame.minY, created.frame.minY, "Newest first")
        ui.shot("alerts-live")

        // An alert opens its task
        changed.tap()
        ui.expect(app.staticTexts[retitled], timeout: 15)
        ui.expect(app.buttons["detail.more"])
        ui.shot("alert-task")
        app.navigationBars.buttons["BackButton"].tap()
        ui.expect(changed)
    }
}
