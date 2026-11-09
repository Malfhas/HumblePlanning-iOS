import XCTest

/// The screenshots of the App Store listing, taken on the test server filled by seed.mjs (the fictitious company of
/// the Android screenshots), signed in as Emma Collins, the site manager. Skipped unless asked: `tools/screenshots.sh`
/// sets `TEST_RUNNER_HP_APPSTORE=1`, the status bar and the simulators (iPhone 6.9", iPad 13").
///
/// Each screen is saved as `<shots>/appstore/<iphone|ipad>-<language>-<NN>-<name>.png`. The scripted answer of the
/// assistant (a question about who is "available") is in English: that screen is only taken in English.
final class AppStoreScreenshots: XCTestCase {
    private var ui: Driver!
    @MainActor private var app: XCUIApplication { ui.app }
    private let emma = TestAccount.seeded("emma")

    @MainActor
    private func prepare() throws {
        try TestServer.require()
        try XCTSkipUnless(TestServer.environment["HP_APPSTORE"] == "1", "App Store screenshots: tools/screenshots.sh")
        continueAfterFailure = false
        ui = Driver(test: self, shots: nil)
    }

    @MainActor
    func testEnglish() throws {
        try prepare()
        try takeAll(language: "en")
    }

    @MainActor
    func testFrench() throws {
        try prepare()
        try takeAll(language: "fr")
    }

    @MainActor
    private func takeAll(language: String) throws {
        let english = language == "en"
        let planning = try PlanningServer(self)
        let task = try showcaseTask(planning)

        // 1. The week: Emma's tasks around today
        ui.launch(as: emma, language: language, "-planning_view", "Week")
        ui.expectMain()
        settle(on: app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Riverside")).firstMatch)
        save(language, 1, "week")

        // 2. The team grid, like the web schedule
        ui.launch(as: emma, language: language, "-planning_view", "Grid")
        ui.expectMain()
        showEveryone(english)
        settle(on: app.otherElements["Emma Collins"].firstMatch, fallback: 4)
        save(language, 2, "grid")

        // 3. A task with several people and its details
        ui.launch(as: emma, language: language, "-HPOpenTask", task)
        ui.expectMain()
        settle(on: app.navigationBars.firstMatch, fallback: 3)
        save(language, 3, "task")

        // 4. Upcoming: the next thirty days, also offline
        ui.launch(as: emma, language: language, "-HPTab", "upcoming")
        ui.expectMain()
        settle(on: app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Riverside")).firstMatch, fallback: 3)
        save(language, 4, "upcoming")

        // 5. Alerts: the changes made by the others to Emma's tasks (seed.mjs makes a few)
        ui.launch(as: emma, language: language, "-HPTab", "alerts")
        ui.expectMain()
        settle(on: app.cells.firstMatch, fallback: 3)
        save(language, 5, "alerts")

        // 6. The assistant, with the scripted answer of the test server (English only)
        if english { try assistant(language) }

        // 7. The grid in dark mode
        ui.launch(as: emma, language: language, "-planning_view", "Grid", "-theme", "dark")
        ui.expectMain()
        showEveryone(english)
        settle(on: app.otherElements["Emma Collins"].firstMatch, fallback: 4)
        save(language, 7, "grid-dark")
    }

    /// Emma's task of this week with the most people: the richest detail screen.
    @MainActor
    private func showcaseTask(_ planning: PlanningServer) throws -> String {
        let emmaId = try planning.userId("emma")
        let days = PlanningDays()
        let tasks = try planning.tasks(from: days.iso(days.monday), to: days.iso(days.day(6)))
        let hers = tasks.filter { task in
            ((task["users"] as? [[String: Any]]) ?? []).contains { $0["id"] as? String == emmaId }
        }
        let best = hers.max { a, b in
            ((a["users"] as? [Any])?.count ?? 0) < ((b["users"] as? [Any])?.count ?? 0)
        }
        return try XCTUnwrap(best?["id"] as? String, "Emma has no task this week: run seed.mjs with --week <this Monday>")
    }

    @MainActor
    private func assistant(_ language: String) throws {
        try server { try await TestAPI.admin().enableAssistant() }
        let question = "Who is available next week in the Plumbing team?"
        cleanUp { [emma] in
            guard let reader = try? await AccountSession.open(emma, deviceName: "[iOS test] screenshots reader") else { return }
            for id in (try? await reader.conversations(markedWith: "available next week")) ?? [] {
                await reader.deleteConversation(id)
            }
            await reader.close()
        }
        ui.launch(as: emma, language: language, "-HPTab", "assistant")
        ui.expectMain()
        let new = app.navigationBars.buttons["New conversation"]
        ui.expect(new)
        new.tap()
        let input = app.textFields["assistant.input"]
        ui.expect(input)
        input.tap()
        input.typeText(question)
        app.buttons["Send"].tap()
        // The turn is over when the send button comes back
        ui.expectGone(app.buttons["Stop the answer"], timeout: 40)
        ui.expect(app.buttons["Send"], timeout: 40)
        // The model of the test server titles every conversation "Titre de test": a title a real model would write
        try server { [emma] in
            let reader = try await AccountSession.open(emma, deviceName: "[iOS test] screenshots title")
            for id in try await reader.conversations(markedWith: "available next week") {
                try await reader.renameConversation(id, to: "Plumbing team availability")
            }
            await reader.close()
        }
        // The app opened again: the input is not focused, so the answer shows without the keyboard. The assistant
        // comes back on the conversation, or on its list (then the conversation is opened from it)
        ui.launch(as: emma, language: language, "-HPTab", "assistant")
        ui.expectMain()
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Liam Turner")).firstMatch
        if !answer.waitForExistence(timeout: 8) {
            // The latest conversation, first of the list (its title is written by the model, not the question)
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "assistant.conversation.")).firstMatch
            ui.expect(row, timeout: 15)
            row.tap()
            ui.expect(answer, timeout: 15)
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The keyboard hides the answer")
        Thread.sleep(forTimeInterval: 1.5)
        save(language, 6, "assistant")
    }

    /// The grid starts on the user's own row: the screenshot shows the whole company, team by team.
    @MainActor
    private func showEveryone(_ english: Bool) {
        let button = app.buttons[english ? "Show everyone" : "Voir tout le monde"]
        ui.expect(button)
        button.tap()
        ui.expectGone(button)
    }

    /// Waits for the screen to be filled and still: the element when given, then a short pause (images, glass).
    @MainActor
    private func settle(on element: XCUIElement, fallback: TimeInterval = 2) {
        if !element.waitForExistence(timeout: 20) { Thread.sleep(forTimeInterval: fallback) }
        Thread.sleep(forTimeInterval: 2)
    }

    @MainActor
    private func save(_ language: String, _ index: Int, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let shots = TestServer.shots else { return }
        let folder = shots.appending(path: "appstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try? png.write(to: folder.appending(path: String(format: "%@-%@-%02d-%@.png", device, language, index, name)))
    }
}
