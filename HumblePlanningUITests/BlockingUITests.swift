import XCTest

/// The screens of a server that refuses the app, like BlockingTest of the Android app: a version too old (426), a
/// role without the mobile app (403), maintenance (423).
///
/// The test server cannot require a newer version without changing it for every run sharing it: the app claims an
/// old one instead (`-HPAppVersion`, debug builds). Maintenance does change the server for everyone: that test only
/// runs alone (`TEST_RUNNER_HP_GLOBAL=1`) and puts the setting back, even when it fails.
final class BlockingUITests: XCTestCase {
    private let oldVersion = "0.9.0"

    private func updateText(minimum: String) -> String {
        "This app version (\(oldVersion)) is no longer accepted by the server: version \(minimum) or later is required."
    }

    /// The minimum version the server enforces (its release's, or a newer setting), as `GET /api/mobile/info` says.
    private static func serverMinimum() async throws -> String {
        let answer = try await ServerCall.send("GET", "/api/mobile/info")
        return try XCTUnwrap(answer.object["minimumAppVersion"] as? String, "minimumAppVersion of /api/mobile/info")
    }

    @MainActor
    func testTooOldAtSignIn_showsTheUpdateScreen_thenTheUpdatedAppSignsIn() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "tooold")
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        ui.launch(as: user.account, "-HPAppVersion", oldVersion)
        ui.expect(app.staticTexts["Update required"], timeout: 20)
        let minimum = try await Self.serverMinimum()
        ui.expect(app.staticTexts[updateText(minimum: minimum)])
        XCTAssertFalse(ui.loginError.exists, "Said by the screen, not as an error of the form")
        ui.shot("update-required")

        // Still too old for the server
        app.buttons["Try again"].tap()
        ui.waitHittable(app.buttons["Try again"], true, timeout: 15)
        XCTAssertTrue(app.staticTexts["Update required"].exists)

        // The store page of the app (Safari on the simulator, which has no App Store)
        app.buttons["Get the new version"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "The store page opened")
        ui.shot("store-page")
        app.activate()
        ui.expect(app.staticTexts["Update required"])

        // Updated: the same installation signs in
        ui.relaunch(as: user.account)
        ui.expectSignedIn()
        XCTAssertFalse(app.staticTexts["Update required"].exists)
        ui.shot("updated")
    }

    @MainActor
    func testTooOldWhileSignedIn_coversTheApp_untilUpdated() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "toooldsession")
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        ui.launch(as: user.account)
        ui.expectSignedIn()
        // The session kept, an older version: its first requests are refused
        ui.relaunch("-HPAppVersion", oldVersion)
        ui.expect(app.staticTexts["Update required"], timeout: 20)
        let minimum = try await Self.serverMinimum()
        ui.expect(app.staticTexts[updateText(minimum: minimum)])
        ui.expectTabUntouchable("Settings")
        ui.shot("update-over-the-app")
        app.buttons["Try again"].tap()
        ui.waitHittable(app.buttons["Try again"], true, timeout: 15)
        XCTAssertTrue(app.staticTexts["Update required"].exists)

        // Updated: still signed in, nothing left of the refusal
        ui.relaunch()
        ui.expectSignedIn()
        ui.waitHittable(app.tabBars.buttons["Settings"], true, timeout: 10)
        XCTAssertFalse(app.staticTexts["Update required"].exists)
        XCTAssertFalse(ui.signInButton.exists)
    }

    @MainActor
    func testRoleWithoutTheApp_isRefusedAtSignIn() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let role = try await newRole(admin, "no app", permissions: ["pages:planning", "pages:home"])
        let user = try await newUser(admin, "noapp", roleId: role)
        // Refused before the password is checked: this counts no failed attempt
        let expected = try await ServerCall.appSignIn(user.login, user.password)
        XCTAssertEqual(expected.status, 403)
        XCTAssertFalse(expected.error.isEmpty)
        let ui = Driver(test: self, shots: TestServer.shots)

        ui.launch(as: user.account)
        ui.expectLoginError(expected.error)
        ui.shot("app-not-allowed-at-sign-in")
        ui.expectSignInScreen()
        XCTAssertFalse(ui.app.staticTexts["App not allowed"].exists, "On the form, not the blocking screen")
    }

    @MainActor
    func testAppWithdrawnWhileSignedIn_blocks_andOffersToSignOut() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let role = try await newRole(admin, "app withdrawn", permissions: ["pages:planning", "pages:home"])
        let user = try await newUser(admin, "withdrawn")
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        ui.launch(as: user.account)
        ui.expectSignedIn()
        try await admin.call("PUT", "/api/users/\(user.id)", ["roleId": role])
        // The next request of the app is refused
        app.tabBars.buttons["Upcoming"].tap()
        ui.expect(app.staticTexts["App not allowed"], timeout: 20)
        ui.expect(app.staticTexts["Your role does not allow the mobile app. Contact your administrator."])
        ui.expectTabUntouchable("Settings")
        ui.shot("app-withdrawn")
        app.buttons["Sign out"].tap()
        ui.expectSignInScreen()
        ui.expectGone(app.staticTexts["App not allowed"])

        // Signing in again is refused on the form, with the server's words
        ui.signIn(login: user.login, password: user.password)
        ui.expectLoginError("Your role does not allow the mobile app. Contact your administrator.")
    }

    /// Changes the server for every run sharing it: only alone (`TEST_RUNNER_HP_GLOBAL=1`).
    @MainActor
    func testMaintenance_blocksTheSignIn_thenComesBack_byHandAndByItself() async throws {
        try TestServer.require()
        try XCTSkipUnless(TestServer.environment["HP_GLOBAL"] == "1", "Changes the server for everyone: run alone with TEST_RUNNER_HP_GLOBAL=1")
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let previous = try await admin.config("MAINTENANCE_MODE") ?? "false"
        addTeardownBlock { try await admin.setConfig("MAINTENANCE_MODE", previous) }
        let user = try await newUser(admin, "maintenance")
        // A session that is an app (version header) tells when the setting is in force
        let probe = try await ServerCall.appSignIn(user.login, user.password)
        let cookie = try XCTUnwrap(ServerCall.sessionCookie(probe))
        func maintenance(_ on: Bool) async throws {
            try await admin.setConfig("MAINTENANCE_MODE", on ? "true" : "false")
            try await SignInSupport.waitForServer("maintenance \(on ? "on" : "off")", timeout: 30) {
                let status = try await ServerCall.send("GET", "/api/profile", cookie: cookie, headers: ServerCall.appHeaders).status
                return (status == 423) == on
            }
        }
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let title = app.staticTexts["Under maintenance"]

        // Sign-in opens the session; its first load is refused
        try await maintenance(true)
        let message = try await ServerCall.send("GET", "/api/profile", cookie: cookie, headers: ServerCall.appHeaders).error
        ui.launch(as: user.account)
        ui.expect(title, timeout: 20)
        if !message.isEmpty { ui.expect(app.staticTexts[message]) }
        ui.expect(ui.any(containing: "Trying again in"))
        ui.shot("maintenance-at-sign-in")
        try await maintenance(false)
        app.buttons["Try again"].tap()
        // The sign-in goes on by itself
        ui.expectSignedIn()
        ui.expectGone(title)

        // Signed in: blocked, then back without a gesture within its 30 s
        try await maintenance(true)
        app.tabBars.buttons["Upcoming"].tap()
        ui.expect(title, timeout: 20)
        ui.shot("maintenance-signed-in")
        try await maintenance(false)
        ui.expectGone(title, timeout: 70)
        ui.waitHittable(app.tabBars.buttons["Planning"], true, timeout: 10)
    }
}
