import XCTest

/// The assistant end to end, against the scripted model of the test server (like AssistantTest of the Android app):
/// "cree une tache :: {json}" makes it ask to create that task, a question about who is "available" gets the
/// Markdown answer of the screenshots, anything else is echoed after "Réponse de test : ". Its answer arrives at
/// once: how a stream is read and put together is covered by the HumbleCore tests (ServerSentEvents, ReplyBuilder).
///
/// Signs in as Emma Collins (site manager: may use the assistant and let it write). Her conversations and the tasks
/// they create are removed at the end, also on failure; the conversations of other runs are left alone.
final class AssistantUITests: XCTestCase {
    private var ui: Driver!
    @MainActor private var app: XCUIApplication { ui.app }
    private let emma = TestAccount.seeded("emma")

    @MainActor
    private func prepare() throws {
        try TestServer.require()
        continueAfterFailure = false
        ui = Driver(test: self, shots: TestServer.shots)
        try server { try await TestAPI.admin().enableAssistant() }
    }

    /// A session of Emma beside the app, to read back her conversations; the ones named or started with these
    /// words are deleted at the end.
    @MainActor
    private func emmaReader(removingConversationsWith markers: [String]) throws -> AccountSession {
        let reader = try server { [emma] in try await AccountSession.open(emma, deviceName: "[iOS test] assistant reader") }
        cleanUp {
            for marker in markers {
                for id in (try? await reader.conversations(markedWith: marker)) ?? [] { await reader.deleteConversation(id) }
            }
            await reader.close()
        }
        return reader
    }

    @MainActor
    private func openAssistant() {
        ui.launch(as: emma, "-HPTab", "assistant")
        ui.expectSignedIn()
        ui.expect(app.navigationBars["Assistant"])
    }

    @MainActor
    private func startConversation() {
        let new = app.navigationBars["Assistant"].buttons["New conversation"]
        ui.expect(new)
        new.tap()
        ui.expect(app.staticTexts["How can I help?"])
    }

    @MainActor
    private func send(_ text: String) {
        let input = app.textFields["assistant.input"]
        ui.expect(input)
        input.tap()
        input.typeText(text)
        XCTAssertEqual(input.value as? String, text, "Typed as is (no smart quotes)")
        app.buttons["Send"].tap()
    }

    /// The turn is over: another question can be asked.
    @MainActor
    private func expectIdle(timeout: TimeInterval = 30) {
        ui.expect(app.buttons["Send"], timeout: timeout)
        ui.expectGone(app.buttons["Stop the answer"], timeout: timeout)
    }

    @MainActor
    private func back() {
        app.navigationBars.buttons["BackButton"].tap()
        ui.expect(app.navigationBars["Assistant"])
    }

    /// A question in the conversation (not the title, which repeats it). A message is one element that VoiceOver
    /// reads after who wrote it: "You, …" or "Assistant, …".
    @MainActor
    private func asked(_ text: String) -> XCUIElement {
        app.staticTexts["You, " + text]
    }

    /// An answer of the scripted model (it begins with "Réponse de test"), with these words if given.
    @MainActor
    private func answer(containing text: String? = nil) -> XCUIElement {
        var predicates = [NSPredicate(format: "label BEGINSWITH %@", "Assistant, Réponse de test")]
        if let text { predicates.append(NSPredicate(format: "label CONTAINS %@", text)) }
        return app.staticTexts.matching(NSCompoundPredicate(andPredicateWithSubpredicates: predicates)).firstMatch
    }

    // MARK: Tests

    /// A question and its answer, kept by the server; the conversation renamed then deleted from the list.
    @MainActor
    func testAnswerHistoryRenameAndDelete() throws {
        try prepare()
        let question = uniqueTitle("question")
        let renamed = uniqueTitle("renamed conversation")
        let reader = try emmaReader(removingConversationsWith: [question])
        openAssistant()

        // The monthly quota as a ring; a tap shows its details
        let gauge = app.navigationBars["Assistant"].buttons.matching(NSPredicate(format: "label CONTAINS %@", "of the monthly quota used")).firstMatch
        ui.expect(gauge, timeout: 15)
        let quota = gauge.label
        XCTAssertTrue(quota.contains(" · Resets on "), quota)
        gauge.tap()
        ui.expect(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", quota.components(separatedBy: " · ")[0])).firstMatch)
        ui.shot("quota-details")
        ui.dismissPopover()

        startConversation()
        send(question)
        // The question, then the whole answer (several parts of the stream put together), then ready again
        ui.expect(asked(question))
        ui.expect(answer(containing: question), timeout: 30)
        expectIdle()
        // Titled by the question, until the server writes its own title after the first answer (from 1.3.0)
        let title = app.navigationBars.staticTexts.firstMatch.label
        XCTAssertTrue(title == question || (!title.isEmpty && title != "New conversation"), "Titled: \(title)")
        XCTAssertFalse((app.textFields["assistant.input"].value as? String ?? "").contains(question), "The draft is cleared")
        ui.shot("conversation-answer")

        // The server kept it: listed, and opened again with what was said
        let conversationId = try XCTUnwrap(firstFound("conversation saved") { try await reader.conversations(markedWith: question).first })
        back()
        let row = app.buttons["assistant.conversation.\(conversationId)"]
        ui.expect(row, timeout: 15)
        ui.shot("conversation-listed")
        row.tap()
        ui.expect(asked(question), timeout: 15)
        ui.expect(answer(containing: question), timeout: 15)
        back()

        // Renamed from the list
        row.swipeLeft()
        app.buttons["Rename"].tap()
        let alert = app.alerts["Rename the conversation"]
        ui.expect(alert)
        let field = alert.textFields.firstMatch
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + renamed)
        XCTAssertEqual(field.value as? String, renamed)
        ui.expect(app.keyboards.firstMatch)
        ui.waitStill(alert)
        ui.shot("conversation-rename")
        alert.buttons["Save"].tap()
        ui.expectGone(alert)
        try eventually("renamed on the server") { try await reader.conversations()[conversationId] == renamed }
        ui.expect(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@",
                                                   "assistant.conversation.\(conversationId)", renamed)).firstMatch)

        // Deleted from the list
        row.swipeLeft()
        app.buttons["Delete"].tap()
        let confirm = app.alerts["Delete this conversation?"]
        ui.expect(confirm)
        XCTAssertTrue(confirm.staticTexts[renamed].exists, "The dialog names the conversation")
        confirm.buttons["Delete"].tap()
        ui.expectGone(row)
        try eventually("deleted on the server") { try await reader.conversations()[conversationId] == nil }
    }

    /// The scripted answer about who is available: bold runs and bullets rendered, no Markdown sign left.
    @MainActor
    func testScriptedAnswerIsRenderedAsMarkdown() throws {
        try prepare()
        let question = uniqueTitle("Is Liam Turner available this week?")
        _ = try emmaReader(removingConversationsWith: [question])
        openAssistant()
        startConversation()
        send(question)

        ui.expect(app.staticTexts["Liam Turner is free on Thursday 12 and Friday 13 November."], timeout: 30)
        expectIdle()
        ui.expect(app.staticTexts["Monday 9 and Tuesday 10: switchboard replacement at Harbour View Offices, with Emma Collins"])
        ui.expect(app.staticTexts["Wednesday 11: Armistice Day, public holiday"])
        ui.expect(app.staticTexts.matching(NSPredicate(format: "label == %@", "Nothing is planned for him on Thursday and Friday: he could take the EV charger installation at Greenfield Warehouse. Shall I prepare that task?")).firstMatch)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == '•'")).count, 2, "Two bullets")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '**'")).firstMatch.exists, "No Markdown sign left")
        ui.shot("markdown-answer")
    }

    /// A write waits for approval: refused, nothing is written and the assistant is told; approved, the task exists.
    @MainActor
    func testRefusedWriteLeavesNothingApprovedWriteCreatesTheTask() throws {
        try prepare()
        let admin = try server { try await TestAPI.admin() }
        let seeded = try server { try await admin.seeded() }
        let day = isoDay(70)
        let refused = uniqueTitle("ai refused")
        let approved = uniqueTitle("ai approved")
        _ = try emmaReader(removingConversationsWith: [refused, approved])
        cleanUp {
            for title in [refused, approved] {
                for task in (try? await admin.tasks(titled: title, on: day)) ?? [] {
                    if let id = task["id"] as? String { await admin.deleteTask(id) }
                }
            }
        }
        /// What makes the scripted model ask for this write, with ids of the seeded company.
        func request(_ title: String) throws -> String {
            let input: [String: Any] = ["projectId": seeded.projectId, "userIds": [seeded.userId("emma")],
                                        "statusId": seeded.statusId, "startDate": day, "title": title]
            let json = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])
            // The title first: the conversation is named after the beginning of its first question
            return title + " cree une tache :: " + String(decoding: json, as: UTF8.self)
        }
        openAssistant()

        // Refused
        startConversation()
        send(try request(refused))
        let approve = app.buttons["Approve"]
        ui.expect(approve, timeout: 30)
        ui.expect(app.staticTexts["The assistant wants to:"])
        ui.expect(app.staticTexts["Create task"])
        ui.expect(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "title: " + refused)).firstMatch)
        ui.expect(app.staticTexts["Answer the confirmation above to continue."])
        XCTAssertFalse(app.textFields["assistant.input"].isEnabled, "Nothing else can be asked before deciding")
        ui.shot("approval-card")
        XCTAssertTrue(try server { try await admin.tasks(titled: refused, on: day) }.isEmpty, "Nothing written before the decision")
        app.buttons["Refuse"].tap()
        ui.expectGone(approve, timeout: 30)
        // The model learns the refusal: the scripted one repeats what it received
        ui.expect(answer(containing: "Tool execution denied"), timeout: 30)
        expectIdle()
        XCTAssertTrue(app.textFields["assistant.input"].isEnabled)
        ui.shot("approval-refused")
        XCTAssertTrue(try server { try await admin.tasks(titled: refused, on: day) }.isEmpty, "Refused: nothing written")
        back()

        // Approved
        startConversation()
        send(try request(approved))
        ui.expect(approve, timeout: 30)
        approve.tap()
        ui.expectGone(approve, timeout: 30)
        let created = try firstFound("task created by the assistant", timeout: 30) { try await admin.tasks(titled: approved, on: day).first }
        XCTAssertEqual(created?["projectId"] as? String, seeded.projectId)
        // The assistant goes on with the result of the tool
        ui.expect(answer(), timeout: 30)
        expectIdle()
        ui.shot("approval-approved")
    }

    /// An account without the right to use the assistant is not offered it, even when asked for its tab.
    @MainActor
    func testNoAssistantWithoutTheRight() throws {
        try prepare()
        ui.launch(as: .seeded("liam"), "-HPTab", "assistant")
        ui.expectSignedIn()
        XCTAssertTrue(ui.barTab("Planning").isSelected, "Back on the planning")
        XCTAssertFalse(ui.barTab("Assistant").exists)
        XCTAssertEqual(app.tabBars.buttons.count, 4, "Planning, Upcoming, Alerts, Settings")
        ui.shot("no-assistant")
    }
}
