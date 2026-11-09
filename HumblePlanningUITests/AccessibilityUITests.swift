import XCTest

/// The accessibility audit of Xcode on every main screen, on the iPhone and the iPad: labels, descriptions, hit
/// regions, Dynamic Type, clipped text, contrast and traits. Each test lists every issue of its screens at once.
///
/// Signs in as Emma Collins (see `TestServer`). The task and the conversation it makes are titled "[iOS test] …"
/// and deleted by the test, also when it fails.
final class AccessibilityUITests: XCTestCase {
    private var stamp: String { "\(Int(Date().timeIntervalSince1970 * 1000) % 100_000_000)" }

    /// The controls of the planning are Liquid Glass buttons (in the navigation bar on the iPhone, above the
    /// planning on the iPad).
    static let planningBar: [AuditException] = [.glass("Today", "New task", "Choose a date", "Filters")]

    @MainActor
    func testSignIn() throws {
        try TestServer.require()
        let ui = Driver(test: self, shots: TestServer.shots)
        let audit = AccessibilityAudit(ui: ui)
        ui.launchSignedOut()
        ui.expect(ui.app.buttons["Sign in"], timeout: 20)
        audit.audit("sign-in", except: [.glass("Sign in", "Scan the sign-in QR code")])
        audit.assertClean()
    }

    @MainActor
    func testPlanningViewsAndFilters() throws {
        try TestServer.require()
        continueAfterFailure = false
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let audit = AccessibilityAudit(ui: ui)
        ui.launch(as: .seeded("emma"), "-planning_view", "Day")
        ui.expectMain()
        ui.expect(ui.any(containing: "Switchboard replacement"), timeout: 20)
        let bar = AccessibilityUITests.planningBar
        audit.audit("planning-day", except: bar)

        app.buttons["Week"].tap()
        ui.expect(ui.any(containing: "Week of"))
        audit.audit("planning-week", except: bar)

        app.buttons["Month"].tap()
        ui.expect(app.staticTexts["Monday 9 November"].firstMatch, timeout: 15)
        audit.audit("planning-month", except: bar)

        app.buttons["Grid"].tap()
        ui.expect(app.buttons["Previous month"])
        ui.expect(ui.any(containing: "Emma Collins"), timeout: 20)
        audit.audit("planning-grid", except: bar + [.glass("Previous month", "Next month", "Width of the days"), .fixedGrid])

        app.buttons["Filters"].tap()
        ui.expect(app.buttons["Apply"])
        audit.audit("filters")
        app.buttons["Apply"].tap()
        ui.expectGone(app.buttons["Apply"])
        audit.assertClean()
    }

    @MainActor
    func testTaskDetailAndForm() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let title = "[iOS test] a11y \(stamp)"
        let id = try await A11yData.createTask(title: title)
        addTeardownBlock { try await A11yData.deleteTask(id) }
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let audit = AccessibilityAudit(ui: ui)

        ui.launch(as: .seeded("emma"), "-HPOpenTask", id)
        ui.expect(app.buttons["detail.more"], timeout: 30)
        ui.expect(ui.any(containing: "Accessibility test notes"))
        let firstRow = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Date'")).firstMatch
        audit.audit("task-detail", except: [.above(firstRow, reason: "dark text on the light tint of the project colour (7:1 or more)")])

        // The identifier added for the iPad (its sidebar has an Edit button too) keeps the label of the button
        XCTAssertEqual(app.buttons["detail.edit"].label, "Edit")
        app.buttons["detail.edit"].tap()
        let save = app.buttons["form.save"]
        ui.expect(save, timeout: 15)
        audit.audit("task-form", except: [.systemColours("When")])

        app.buttons["form.date.start"].tap()
        ui.expect(app.datePickers.firstMatch)
        audit.audit("task-form-calendar", except: [.systemColours("When")])
        app.buttons["form.date.start"].tap()

        app.buttons["form.project"].tap()
        ui.expect(app.collectionViews["picker.list"])
        audit.audit("picker", except: [.inside(app.collectionViews["picker.list"], reason: "black text on the glass of a sheet at its medium height")])
        app.buttons["Cancel"].firstMatch.tap()
        ui.expectGone(app.collectionViews["picker.list"])
        app.buttons["form.cancel"].tap()
        ui.expectGone(save)
        audit.assertClean()
    }

    /// The markers of a card come after its title, as on the web, the milestone last: VoiceOver says them there.
    @MainActor
    func testCardMarkersAfterTheTitle() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let title = "[iOS test] markers \(stamp)"
        let id = try await A11yData.createTask(title: title)
        addTeardownBlock { try await A11yData.deleteTask(id) }
        let ui = Driver(test: self, shots: TestServer.shots)
        ui.launch(as: .seeded("emma"), "-planning_view", "Day")
        ui.expectMain()
        let card = ui.visibleCard(title, timeout: 30)
        ui.shot("card-markers")
        // The project (the title of the card), its notes and milestone, then the own title of the task
        XCTAssertTrue(card.label.contains("Has notes, Milestone, \(title)"), card.label)
    }

    @MainActor
    func testNewTaskForm() throws {
        try TestServer.require()
        continueAfterFailure = false
        let ui = Driver(test: self, shots: TestServer.shots)
        let audit = AccessibilityAudit(ui: ui)
        ui.launch(as: .seeded("emma"), "-HPOpenForm", "create")
        ui.expect(ui.app.buttons["form.save"], timeout: 30)
        audit.audit("task-form-new", except: [.systemColours("When")])
        ui.app.buttons["form.save"].tap()
        ui.expect(ui.app.staticTexts["Choose a project."])
        audit.audit("task-form-refused", except: [.systemColours("When")])
        audit.assertClean()
    }

    @MainActor
    func testUpcomingAndAlerts() throws {
        try TestServer.require()
        continueAfterFailure = false
        let ui = Driver(test: self, shots: TestServer.shots)
        let audit = AccessibilityAudit(ui: ui)
        ui.launch(as: .seeded("emma"), "-HPTab", "upcoming")
        ui.expectMain()
        ui.expect(ui.any(containing: "Switchboard replacement"), timeout: 20)
        audit.audit("upcoming")

        ui.tab("Alerts").tap()
        ui.expect(ui.app.navigationBars["Alerts"])
        sleep(2)
        audit.audit("alerts")
        audit.assertClean()
    }

    @MainActor
    func testAssistant() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let marker = "[iOS test] a11y \(stamp)"
        let request = try await A11yData.writeRequest(title: marker)
        addTeardownBlock { try await AccountAPI.signIn(.seeded("emma")).deleteConversations(containing: marker) }
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let audit = AccessibilityAudit(ui: ui)
        ui.launch(as: .seeded("emma"), "-HPTab", "assistant")
        ui.expectMain()
        let new = app.buttons["New conversation"]
        ui.expect(new, timeout: 20)
        sleep(1)
        audit.audit("assistant-list")

        new.tap()
        let field = app.textFields["Your message"]
        ui.expect(field)
        audit.audit("conversation-new", except: [.glass("Send")])

        // The stand-in of the AI provider asks to create a task when told "crée une tâche"
        field.tap()
        field.typeText(request)
        app.buttons["Send"].tap()
        let refuse = app.buttons["Refuse"]
        ui.expect(refuse, timeout: 30)
        audit.audit("conversation-approval", except: [.glass("Send", "Stop the answer", "Approve", "Refuse"), .systemColours("projectId:")])
        refuse.tap()
        ui.expectGone(refuse, timeout: 30)
        audit.assertClean()
    }

    @MainActor
    func testSettingsAndSheets() throws {
        try TestServer.require()
        continueAfterFailure = false
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let audit = AccessibilityAudit(ui: ui)
        ui.launch(as: .seeded("emma"), "-HPTab", "settings")
        ui.expectMain()
        let profile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Emma Collins'")).firstMatch
        ui.expect(profile, timeout: 20)
        // The devices of the account load after the screen: the audit measures a still layout
        ui.expectGone(app.activityIndicators.firstMatch, timeout: 30)
        audit.audit("settings")
        let signOut = app.buttons["Sign out"]
        ui.scroll(to: signOut)
        audit.audit("settings-end")

        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        profile.tap()
        ui.expect(app.navigationBars["My profile"])
        audit.audit("profile")
        app.navigationBars["My profile"].buttons.element(boundBy: 0).tap()
        ui.expectGone(app.navigationBars["My profile"])

        let password = app.buttons["Change password"]
        ui.scroll(to: password)
        password.tap()
        ui.expect(app.navigationBars["Change password"])
        audit.audit("password")
        app.navigationBars["Change password"].buttons.element(boundBy: 0).tap()
        ui.expectGone(app.navigationBars["Change password"])

        let twoFactor = app.buttons["Enable two-step verification"]
        if twoFactor.exists {
            twoFactor.tap()
            ui.expect(app.navigationBars["Enable two-step verification"])
            audit.audit("two-factor", except: [.glass("Continue")])
            app.navigationBars["Enable two-step verification"].buttons.element(boundBy: 0).tap()
        }
        audit.assertClean()
    }
}
