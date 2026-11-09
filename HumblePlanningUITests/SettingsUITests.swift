import XCTest

/// The settings, like SettingsTest of the Android app: display (theme, card title), reminders, devices, about and
/// sign-out. The language is the one of iOS (Settings > Humble Planning), outside the app.
///
/// Signs in as Emma Collins. The display and reminder settings only live on the phone (each launch starts from
/// scratch); the tasks and the second session the tests create are removed at the end.
final class SettingsUITests: XCTestCase {
    private let emma = TestAccount.seeded("emma")

    @MainActor
    private func driver() throws -> Driver {
        try TestServer.require()
        continueAfterFailure = false
        return Driver(test: self, shots: TestServer.shots)
    }

    @MainActor
    private func waitBrightness(_ ui: Driver, _ what: String, _ condition: (Double) -> Bool,
                                file: StaticString = #filePath, line: UInt = #line) {
        var brightness = -1.0
        for _ in 0..<10 {
            brightness = ui.backgroundBrightness()
            if condition(brightness) { return }
            usleep(300_000)
        }
        ui.shot("failure")
        XCTFail("Not \(what): brightness \(brightness)", file: file, line: line)
    }

    /// Light and dark change the whole app at once; System gives the appearance of the phone back.
    @MainActor
    func testThemeChangesTheAppearance() throws {
        let ui = try driver()
        let app = ui.app
        ui.launch(as: emma, "-HPTab", "settings")
        ui.expectSignedIn()
        ui.expect(app.buttons["Theme, System"])
        let phone = ui.backgroundBrightness()

        ui.choose("Dark", in: "Theme")
        waitBrightness(ui, "dark") { $0 < 0.15 }
        ui.shot("theme-dark")
        // The other screens too
        ui.barTab("Alerts").tap()
        ui.expect(app.navigationBars["Alerts"])
        waitBrightness(ui, "dark everywhere") { $0 < 0.15 }
        ui.barTab("Settings").tap()

        ui.choose("Light", in: "Theme")
        waitBrightness(ui, "light") { $0 > 0.85 }
        ui.shot("theme-light")
        ui.choose("System", in: "Theme")
        waitBrightness(ui, "the appearance of the phone") { abs($0 - phone) < 0.05 }
    }

    /// The main text of the task cards: the project (default), or the title of the task.
    @MainActor
    func testCardTitleOption() throws {
        let ui = try driver()
        let app = ui.app
        let admin = try server { try await TestAPI.admin() }
        let seeded = try server { try await admin.seeded() }
        let title = uniqueTitle("card")
        // All day today: on top of Upcoming
        let taskId = try server { try await admin.createTask(title, for: [seeded.userId("emma")], on: isoDay(0), seeded: seeded) }
        cleanUp { await admin.deleteTask(taskId) }

        ui.launch(as: emma, "-HPTab", "upcoming")
        ui.expectSignedIn()
        let card = ui.card(title)
        XCTAssertTrue(card.label.hasPrefix(seeded.projectLabel + ", " + title), card.label)
        ui.shot("card-project")

        ui.barTab("Settings").tap()
        ui.choose("Task title", in: "Card title")
        ui.barTab("Upcoming").tap()
        let retitled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ", " + seeded.projectLabel)).firstMatch
        ui.expect(retitled)
        ui.shot("card-title")

        ui.barTab("Settings").tap()
        ui.choose("Project", in: "Card title")
        ui.barTab("Upcoming").tap()
        ui.expect(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", seeded.projectLabel + ", " + title)).firstMatch)
    }

    /// The delay and the tasks of the reminders: "Never" stops them, another delay plans them again, all the tasks
    /// are at least as many as mine.
    @MainActor
    func testReminders() throws {
        let ui = try driver()
        let app = ui.app
        let admin = try server { try await TestAPI.admin() }
        let seeded = try server { try await admin.seeded() }
        // A task of Emma tomorrow morning: at least one reminder
        let taskId = try server {
            try await admin.createTask(uniqueTitle("reminder"), for: [seeded.userId("emma")], on: isoDay(1),
                                       start: "10:00", end: "11:00", seeded: seeded)
        }
        cleanUp { await admin.deleteTask(taskId) }

        ui.launch(as: emma, "-HPTab", "settings")
        ui.expectSignedIn()
        let status = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "scheduled (next 14 days).")).firstMatch
        func count() -> Int { Int(status.label.components(separatedBy: " ")[0]) ?? -1 }
        func waitCount(_ what: String, _ condition: (Int) -> Bool) {
            for _ in 0..<30 {
                if status.exists && condition(count()) { return }
                usleep(500_000)
            }
            ui.shot("failure")
            XCTFail("\(what): \(status.exists ? status.label : "no status")")
        }
        // 15 minutes before, by default: planned at the opening of the app
        ui.expect(app.buttons["Notify me, 15 minutes before"])
        ui.scroll(to: status)
        ui.expect(status)
        waitCount("planned at the opening") { $0 >= 1 }
        ui.shot("reminders-default")

        ui.choose("Never", in: "Notify me")
        ui.expectGone(status)
        ui.shot("reminders-never")

        ui.choose("1 hour before", in: "Notify me")
        ui.allowNotificationsIfAsked()
        ui.expect(status)
        waitCount("planned again") { $0 >= 1 }
        let mine = count()
        ui.scroll(to: app.buttons["All tasks"])
        app.buttons["All tasks"].tap()
        XCTAssertTrue(app.buttons["All tasks"].isSelected)
        waitCount("all the tasks") { $0 >= mine }
        ui.shot("reminders-all")
    }

    /// The devices of the account: this phone, and another session signed out from here.
    @MainActor
    func testDevicesListAndRevokeAnotherOne() throws {
        let ui = try driver()
        let app = ui.app
        let name = uniqueTitle("second phone")
        let other = try server { [emma] in try await AccountSession.open(emma, deviceName: name) }
        cleanUp { await other.close() }

        ui.launch(as: emma, "-HPTab", "settings")
        ui.expectSignedIn()
        let thisPhone = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This phone · ")).firstMatch
        ui.scroll(to: thisPhone)
        ui.expect(thisPhone, timeout: 15)
        XCTAssertTrue(thisPhone.label.hasSuffix(" · now"), thisPhone.label)
        // The account may have more devices than the three shown first
        let showAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show all (")).firstMatch
        if !app.staticTexts[name].exists && showAll.exists {
            ui.scroll(to: showAll)
            showAll.tap()
        }
        let row = app.staticTexts[name]
        ui.scroll(to: row)
        ui.expect(row)
        ui.shot("devices")

        app.buttons["Sign out \(name)"].tap()
        let alert = app.alerts["Sign out this device?"]
        ui.expect(alert)
        ui.expect(alert.staticTexts["\(name) will have to sign in again."])
        alert.buttons["Sign out"].tap()
        ui.expectGone(row, timeout: 15)
        try eventually("the other session ended") { !(await other.isAlive) }
        // This one stays
        ui.expect(thisPhone)
        XCTAssertTrue(ui.barTab("Settings").exists)
    }

    /// Version, licence, and the source code opened in Safari.
    @MainActor
    func testAbout() throws {
        let ui = try driver()
        let app = ui.app
        ui.launch(as: emma, "-HPTab", "settings")
        ui.expectSignedIn()
        let version = Bundle(for: SettingsUITests.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionRow = app.staticTexts["App version, \(version)"]
        ui.scroll(to: versionRow)
        ui.expect(versionRow)
        ui.expect(app.staticTexts["Open source licence, AGPL-3.0-or-later"])
        ui.shot("about")

        let source = app.links["Source code"]
        ui.scroll(to: source)
        source.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "Safari opens the link")
        let address = safari.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", "github.com")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 20), "On GitHub")
        ui.shot("source-code")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        ui.expect(versionRow)
    }

    /// Signing out, after a confirmation, leads back to the sign-in screen, and stays there.
    @MainActor
    func testSignOut() throws {
        let ui = try driver()
        let app = ui.app
        ui.launch(as: emma, "-HPTab", "settings")
        ui.expectSignedIn()
        let signOut = app.buttons["Sign out"]
        ui.scroll(to: signOut)
        signOut.tap()
        let alert = app.alerts["Sign out"]
        ui.expect(alert)
        ui.expect(alert.staticTexts["Planning data stored on this phone and reminders will be removed."])
        ui.shot("sign-out-confirm")
        alert.buttons["Sign out"].tap()
        ui.expect(app.buttons["Sign in"], timeout: 15)
        ui.expectGone(ui.barTab("Planning"))
        XCTAssertFalse(ui.barTab("Planning").waitForExistence(timeout: 3), "Stays signed out")
        ui.shot("signed-out")
    }
}
