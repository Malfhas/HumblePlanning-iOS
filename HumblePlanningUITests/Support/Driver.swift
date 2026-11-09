import XCTest

/// What the scenario does on screen, in the English of the app.
@MainActor
final class Driver {
    let app = XCUIApplication()
    private let test: XCTestCase
    private let shots: URL?
    private var step = 0

    init(test: XCTestCase, shots: URL?) {
        self.test = test
        self.shots = shots
    }

    /// Starts the app as just installed and signs it in on the test server; English unless asked otherwise.
    func launch(as account: TestAccount = .admin, language: String = "en", _ arguments: String...) {
        app.launchArguments = ["-HPResetState", "YES", "-HPSkipNotificationPrompt", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US",
                               "-HPServer", TestServer.url, "-HPLogin", account.login, "-HPPassword", account.password,
                               "-HPAutoSignIn", "YES"] + arguments
        app.launch()
    }

    /// Starts the app without signing in (sign-in tests): as just installed, unless `keepState`.
    func launchSignedOut(language: String = "en", keepState: Bool = false, _ arguments: String...) {
        app.launchArguments = (keepState ? [] : ["-HPResetState", "YES"]) + ["-HPSkipNotificationPrompt", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US"] + arguments
        app.launch()
    }

    /// The tab bar is there: signed in and on the main screen.
    func expectSignedIn(file: StaticString = #filePath, line: UInt = #line) {
        expect(app.tabBars.buttons["Planning"], timeout: 30, file: file, line: line)
    }

    func shot(_ name: String) {
        step += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        if let shots {
            try? png.write(to: shots.appending(path: String(format: "%02d-%@.png", step, name)))
        }
    }

    func expect(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForExistence(timeout: timeout) {
            shot("failure")
            XCTFail("Not found: \(element)\n\(app.debugDescription)", file: file, line: line)
        }
    }

    func expectGone(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForNonExistence(timeout: timeout) {
            shot("failure")
            XCTFail("Still there: \(element)\n\(app.debugDescription)", file: file, line: line)
        }
    }

    /// Waits until the element can be touched, or until something covers it.
    func waitHittable(_ element: XCUIElement, _ hittable: Bool, timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == %@", NSNumber(value: hittable)), object: element)
        if XCTWaiter.wait(for: [expectation], timeout: timeout) != .completed {
            shot("failure")
            XCTFail("\(element) hittable is not \(hittable)\n\(app.debugDescription)", file: file, line: line)
        }
    }

    func any(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The card of a task in Upcoming (the first one, or the one at that place), waited for.
    func card(_ title: String, index: Int = 0, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).element(boundBy: index)
        expect(card, timeout: 20, file: file, line: line)
        return card
    }

    func cardIfAny(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    func selectedCount(in list: XCUIElement) -> Int {
        list.buttons.allElementsBoundByIndex.filter(\.isSelected).count
    }

    /// Selects the first row not selected yet; returns its name (the first line of the row).
    func selectFirstUnselected(in list: XCUIElement) -> String {
        guard let row = list.buttons.allElementsBoundByIndex.first(where: { !$0.isSelected }) else {
            XCTFail("Nobody else to choose")
            return ""
        }
        let name = row.label.components(separatedBy: ", ").first ?? row.label
        row.tap()
        return name
    }

    /// Scrolls until the element is well inside the screen, away from its bottom edge.
    func scroll(to element: XCUIElement) {
        var tries = 0
        while !visible(element) && tries < 8 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    private func visible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        return element.frame.maxY < app.frame.maxY - 140
    }

    /// Taps the switch itself, at the end of its row, and waits for it to turn.
    func toggle(_ row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        expect(row, file: file, line: line)
        let before = row.value as? String ?? ""
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let turned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: row)
        if XCTWaiter.wait(for: [turned], timeout: 5) != .completed {
            shot("failure")
            XCTFail("The switch did not turn\n\(app.debugDescription)", file: file, line: line)
        }
    }

    /// Replaces the whole text of a field.
    func replaceText(of field: XCUIElement, with text: String) {
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text + "\n")
        XCTAssertEqual(field.value as? String, text)
    }

    /// A day in the open calendar, a month later if needed.
    func pickDay(_ date: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let day = app.datePickers.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", formatter.string(from: date))).firstMatch
        if !day.waitForExistence(timeout: 3) {
            app.datePickers.buttons["Next Month"].tap()
        }
        expect(day)
        day.tap()
    }

    /// Closes a popover the way a finger does: a tap outside it.
    func dismissPopover() {
        let region = app.otherElements["PopoverDismissRegion"]
        if region.exists {
            region.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        }
    }

    /// More → Delete, then the choice of the dialog; the detail closes.
    func delete(choice: String, shot name: String?) {
        let more = app.buttons["detail.more"]
        expect(more)
        more.tap()
        app.buttons["Delete"].tap()
        let button = app.buttons[choice].firstMatch
        expect(button)
        if let name { shot(name) }
        button.tap()
        expectGone(more, timeout: 15)
    }
}
