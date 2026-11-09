import XCTest

/// What each account is offered on screen, like PermissionsTest of the Android app (the server enforces the same
/// rules again: tools/api-tests covers that side).
final class PermissionsUITests: XCTestCase {
    override func setUpWithError() throws {
        try TestServer.require()
        continueAfterFailure = false
    }

    /// Liam Turner, electrical technician: modifies his own tasks only and assigns only himself.
    @MainActor
    func testTechnicianEditsHisOwnTasksOnly() throws {
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let days = PlanningDays()
        ui.launch(as: .seeded("liam"), "-planning_view", "Day")
        ui.expectSignedIn()
        ui.tapDay(days.long(days.monday))

        // His task (with Emma): Edit, and More with Delete
        ui.visibleCard("Switchboard replacement").tap()
        ui.expect(app.buttons["Edit"], timeout: 15)
        app.buttons["detail.more"].tap()
        ui.expect(app.buttons["Duplicate"])
        ui.expect(app.buttons["Delete"])
        ui.shot("own-task-more")
        closeMenu(ui)
        ui.back()

        // Ava's task: no Edit, More only to duplicate it
        ui.openFilters()
        app.segmentedControls.buttons["Everyone"].tap()
        ui.applyFilters()
        ui.visibleCard("Bathroom fit-out").tap()
        ui.expect(app.staticTexts["Bathroom fit-out"].firstMatch, timeout: 15)
        ui.expectAbsent(app.buttons["Edit"], "someone else's task")
        app.buttons["detail.more"].tap()
        ui.expect(app.buttons["Duplicate"])
        ui.expectAbsent(app.buttons["Delete"], for: 1, "someone else's task")
        ui.shot("other-task-more")
        closeMenu(ui)
        ui.back()

        // A new task: for him, and nobody else to choose
        app.buttons["New task"].tap()
        let save = app.buttons["form.save"]
        ui.expect(save, timeout: 15)
        XCTAssertTrue(app.buttons["form.people"].label.contains("Liam Turner"), app.buttons["form.people"].label)
        app.buttons["form.people"].tap()
        let list = app.collectionViews["picker.list"]
        ui.expect(list)
        XCTAssertEqual(list.buttons.count, 1, "Only himself")
        XCTAssertTrue(list.buttons.element(boundBy: 0).label.hasPrefix("Liam Turner"), list.buttons.element(boundBy: 0).label)
        ui.shot("own-people")
        app.buttons["picker.done"].tap()
        ui.expectGone(list)
        app.buttons["form.cancel"].tap()
        ui.expectGone(save)

        // The grid: an empty day of Chloe's row opens nothing, of his own the form for him on that day
        ui.show("Grid")
        let holiday = "\(days.long(days.holiday)), \(PlanningDays.holidayLabel)"
        ui.tapGrid(person: "Chloe Ward", day: holiday)
        ui.expectAbsent(save, for: 2, "a row of someone else")
        ui.tapGrid(person: "Liam Turner", day: holiday)
        ui.expect(save, timeout: 15)
        XCTAssertEqual(app.buttons["form.date.start"].value as? String, days.medium(days.holiday))
        XCTAssertTrue(app.buttons["form.people"].label.contains("Liam Turner"), app.buttons["form.people"].label)
        app.buttons["form.cancel"].tap()
        ui.expectGone(save)
    }

    /// A role that only reads the planning (no `scope:modify_*`, `tasks:*` or `files:*`, attachments seen through
    /// the Files page), and an account with it: nothing that writes is offered.
    @MainActor
    func testReaderIsOfferedNothingThatWrites() throws {
        let server = try PlanningServer(self)
        let days = PlanningDays()
        let name = "iostest-reader-\(UUID().uuidString.prefix(6).lowercased())"
        let reader = try server.createAccount(name, permissions: [
            "mobile_app:use", "pages:home", "pages:planning", "pages:files", "planning:view_calendar",
            "scope:bu_all", "scope:projects_all", "scope:users_all",
        ])
        let title = testTitle("reader")
        let task = try server.createTask(title, for: [reader.id], on: days.iso(days.today))
        try server.attachPDF("iostest-plan.pdf", to: task)

        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        ui.launch(as: reader.account, "-planning_view", "Day")
        ui.expectSignedIn()

        // The planning: his task, but no New task
        let card = ui.visibleCard(title)
        ui.expectAbsent(app.buttons["New task"], "a reader")
        ui.shot("reader-planning")

        // His task: no Edit, no More; the attachment can be seen, not added nor deleted
        card.tap()
        ui.expect(app.staticTexts[title].firstMatch, timeout: 15)
        ui.expect(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'iostest-plan.pdf'")).firstMatch, timeout: 15)
        ui.expectAbsent(app.buttons["Edit"], for: 1, "a reader")
        ui.expectAbsent(app.buttons["detail.more"], for: 1, "a reader")
        ui.expectAbsent(app.buttons["detail.addFile"], for: 1, "a reader")
        ui.expectAbsent(app.buttons["Delete iostest-plan.pdf"], for: 1, "a reader")
        ui.shot("reader-detail")
        ui.back()

        // The grid: his own row opens nothing
        ui.show("Grid")
        ui.tapGrid(person: name, day: "\(days.long(days.holiday)), \(PlanningDays.holidayLabel)")
        ui.expectAbsent(app.buttons["form.save"], for: 2, "a reader")
        ui.shot("reader-grid")
    }

    /// Closes the open menu with a tap above it, away from the buttons of the detail.
    @MainActor
    private func closeMenu(_ ui: Driver) {
        ui.app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        ui.expectGone(ui.app.buttons["Duplicate"])
    }
}
