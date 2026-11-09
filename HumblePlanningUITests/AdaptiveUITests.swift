import XCTest

/// The iPad and large text, like AdaptiveTest of the Android app: a sidebar instead of the bottom bar on the
/// iPad, the planning and the grid using the width, Save reachable in the form sheet, Command-N; with the largest
/// text sizes, the actions stay on the screen and the words of the segments stay whole. Screenshots of every step
/// (`TEST_RUNNER_HP_SHOTS`) are for a person to look at.
///
/// Signs in as Emma Collins (see `TestServer`). The task it makes is titled "[iOS test] …" and deleted by the test.
final class AdaptiveUITests: XCTestCase {
    private var stamp: String { "\(Int(Date().timeIntervalSince1970 * 1000) % 100_000_000)" }

    @MainActor
    func testIPadSidebarWidthAndShortcuts() async throws {
        try TestServer.require()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        continueAfterFailure = false
        let title = "[iOS test] adaptive \(stamp)"
        let id = try await A11yData.createTask(title: title)
        addTeardownBlock { try await A11yData.deleteTask(id) }
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        ui.launch(as: .seeded("emma"), "-planning_view", "Day")
        ui.expectMain()

        // A sidebar, like the rail of the Android tablets: the tabs one under the other, on the left
        let planning = ui.tab("Planning"), settings = ui.tab("Settings")
        ui.expect(settings)
        XCTAssertEqual(planning.frame.minX, settings.frame.minX, accuracy: 2, "tabs in a column")
        XCTAssertGreaterThan(settings.frame.minY, planning.frame.minY, "tabs in a column")
        XCTAssertLessThan(settings.frame.maxX, app.frame.width / 3, "the sidebar is on the left")

        // The controls of the planning, side by side above it
        ui.expect(ui.any(containing: title), timeout: 20)
        for name in ["Today", "New task", "Filters", "Choose a date"] { ui.expectReachable(app.buttons[name], name) }
        ui.shot("ipad-day")

        // The grid: its days fill the width, and each bar is an element VoiceOver can open
        app.buttons["Grid"].tap()
        let bar = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        ui.expect(bar, timeout: 20)
        let days = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Monday '"))
        XCTAssertGreaterThanOrEqual(days.count, 2, "several weeks across the width")
        ui.shot("ipad-grid")
        bar.tap()
        let edit = app.buttons["detail.edit"]
        ui.expect(edit, timeout: 15)
        ui.expect(app.staticTexts[title])
        ui.shot("ipad-detail")

        // The form in a sheet: Save at hand, the sheet narrower than the screen
        edit.tap()
        let save = app.buttons["form.save"]
        ui.expect(save, timeout: 15)
        ui.expectReachable(save, "Save")
        XCTAssertLessThan(save.frame.maxX, app.frame.maxX - 100, "the form is a sheet, not the whole screen")
        ui.shot("ipad-form")
        app.buttons["form.cancel"].tap()
        ui.expectGone(save)

        // Command-N: a new task from the keyboard
        app.typeKey("n", modifierFlags: .command)
        ui.expect(save, timeout: 10)
        ui.expect(app.navigationBars["New task"])
        ui.shot("ipad-command-n")
        app.buttons["form.cancel"].tap()
        ui.expectGone(save)
    }

    @MainActor
    func testAccessibilityTextSizeKeepsActionsAndWholeWords() async throws {
        try await checkLargeText("UICTContentSizeCategoryAccessibilityXXXL", name: "ax5")
    }

    @MainActor
    func testLargestStandardTextSizeKeepsActionsAndWholeWords() async throws {
        try await checkLargeText("UICTContentSizeCategoryXXXL", name: "xxxl")
    }

    /// The main screens with this text size: the actions are reachable and no text is cut.
    @MainActor
    private func checkLargeText(_ category: String, name: String) async throws {
        try TestServer.require()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Large text on the iPhone, like on Android")
        continueAfterFailure = false
        let title = "[iOS test] large text \(stamp)"
        let id = try await A11yData.createTask(title: title)
        addTeardownBlock { try await A11yData.deleteTask(id) }
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let audit = AccessibilityAudit(ui: ui)
        let clipped: XCUIAccessibilityAuditType = [.textClipped, .hitRegion, .sufficientElementDescription]
        ui.launch(as: .seeded("emma"), "-planning_view", "Day", "-UIPreferredContentSizeCategoryName", category)
        ui.expectMain()

        // Planning: New task, Today, the filters and every tab stay on the screen; the segments are whole
        ui.expect(app.buttons["Day"], timeout: 20)
        for action in ["New task", "Today", "Filters", "Day", "Week", "Month", "Grid"] { ui.expectReachable(app.buttons[action], action) }
        for tab in ["Planning", "Upcoming", "Alerts", "Settings"] { ui.expectReachable(ui.tab(tab), tab) }
        audit.audit("\(name)-planning-day", types: clipped)
        app.buttons["Filters"].tap()
        ui.expect(app.buttons["Apply"])
        audit.audit("\(name)-filters", types: clipped)
        app.buttons["Apply"].tap()
        ui.expectGone(app.buttons["Apply"])
        app.buttons["Week"].tap()
        audit.audit("\(name)-planning-week", types: clipped)
        app.buttons["Month"].tap()
        audit.audit("\(name)-planning-month", types: clipped)
        app.buttons["Grid"].tap()
        ui.expect(app.buttons["Previous month"])
        audit.audit("\(name)-planning-grid", types: clipped)
        app.buttons["Day"].tap()

        // The detail: Edit and More; the form: Save and the whole words of the day parts
        let card = ui.cardIfAny(title)
        ui.reveal(card)
        card.tap()
        let edit = app.buttons["detail.edit"]
        ui.expect(edit, timeout: 15)
        ui.expectReachable(edit, "Edit")
        ui.expectReachable(app.buttons["detail.more"], "More")
        audit.audit("\(name)-detail", types: clipped)
        edit.tap()
        let save = app.buttons["form.save"]
        ui.expect(save, timeout: 15)
        ui.expectReachable(save, "Save")
        let afternoon = app.buttons["Afternoon"]
        ui.scroll(to: afternoon)
        for part in ["All day", "Morning", "Afternoon", "Times"] { ui.expectReachable(app.buttons[part], part) }
        audit.audit("\(name)-form", types: clipped)
        app.buttons["form.cancel"].tap()
        ui.expectGone(save)

        // The other tabs
        ui.tab("Upcoming").tap()
        ui.expect(app.navigationBars["My upcoming tasks"], timeout: 20)
        ui.expectReachable(app.buttons["New task"], "New task")
        audit.audit("\(name)-upcoming", types: clipped)
        ui.tab("Alerts").tap()
        ui.expect(app.navigationBars["Alerts"], timeout: 20)
        audit.audit("\(name)-alerts", types: clipped)
        ui.tab("Assistant").tap()
        let newConversation = app.buttons["New conversation"]
        ui.expect(newConversation, timeout: 20)
        audit.audit("\(name)-assistant", types: clipped)
        newConversation.tap()
        ui.expect(app.textFields["Your message"])
        ui.expectReachable(app.buttons["Send"], "Send")
        audit.audit("\(name)-conversation", types: clipped)
        ui.tab("Settings").tap()
        let profile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Emma Collins'")).firstMatch
        ui.expect(profile, timeout: 15)
        ui.expectGone(app.activityIndicators.firstMatch, timeout: 30)
        audit.audit("\(name)-settings", types: clipped)
        let signOut = app.buttons["Sign out"]
        ui.reveal(signOut)
        audit.audit("\(name)-settings-end", types: clipped)
        audit.assertClean()
    }

    /// The sign-in screen with the largest text: its button can be reached by scrolling.
    @MainActor
    func testSignInWithAccessibilityTextSize() throws {
        try TestServer.require()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Large text on the iPhone, like on Android")
        let ui = Driver(test: self, shots: TestServer.shots)
        let audit = AccessibilityAudit(ui: ui)
        ui.launchSignedOut("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        let signIn = ui.app.buttons["Sign in"]
        ui.expect(signIn, timeout: 20)
        audit.audit("ax5-sign-in", types: [.textClipped, .hitRegion, .sufficientElementDescription])
        ui.reveal(signIn)
        ui.expectReachable(signIn, "Sign in")
        ui.shot("ax5-sign-in-button")
        audit.assertClean()
    }
}
