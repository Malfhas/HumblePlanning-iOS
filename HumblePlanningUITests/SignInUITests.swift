import XCTest

/// Signing in with a password against a real server, like SignInTest and AaFirstRunTest of the Android app: wrong
/// addresses, a wrong then the right password, sign-out from the settings, the second factor set up at a sign-in
/// that requires it then asked at the next one, and the notification question of a new installation.
///
/// Every account is made for the test ("[iOS test] …") and deleted at its end.
final class SignInUITests: XCTestCase {
    @MainActor
    func testWrongAddressesAreRefused() throws {
        try TestServer.require()
        continueAfterFailure = false
        let ui = Driver(test: self, shots: TestServer.shots)
        ui.launchSignedOut()
        ui.expectSignInScreen()
        for (server, message) in [
            ("https://planning.example.com@evil.example", "Invalid server address."),
            ("http://example.com", "The address must start with https:// (encrypted connection)."),
            // Answers, but not /api/mobile/info
            (SignInSupport.mockURL, "This address is not a Humble Planning server."),
            // Nothing listens there
            ("http://localhost:9", "Server unreachable: check your internet connection."),
        ] {
            ui.signIn(server: server, login: "someone", password: "anything")
            ui.expectLoginError(message)
        }
        ui.shot("address-refused")
        ui.expectSignInScreen()
    }

    @MainActor
    func testWrongPasswordIsRefused_theRightOneSignsIn_signOutComesBack() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "password")
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        ui.launchSignedOut()
        ui.signIn(login: user.login, password: "not the password")
        ui.expectLoginError(SignInSupport.wrongPassword)
        ui.shot("wrong-password")
        ui.expectSignInScreen()

        // The address and the identifier stay: only the password again
        XCTAssertEqual(app.textFields["login.identifier"].value as? String, user.login)
        ui.typePassword(user.password)
        ui.expectSignedIn()
        ui.expectGone(ui.loginError)
        let web = try await WebSession.signIn(user)
        try await SignInSupport.waitForServer("the session of the app") { try await web.devices().count == 1 }

        // Settings: the account, then sign-out (refused once)
        app.tabBars.buttons["Settings"].tap()
        ui.expect(app.staticTexts[user.name])
        ui.shot("settings")
        ui.signOutFromSettings(cancelFirst: true)
        ui.shot("signed-out")
        try await SignInSupport.waitForServer("the session closed on the server") { try await web.devices().isEmpty }
    }

    @MainActor
    func testRequiredTwoFactor_isSetUpAtSignIn_thenAskedAtTheNext() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "twofactor", forceTwoFactor: true)
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        // Required: password, then the key of the authenticator app
        ui.launchSignedOut()
        ui.signIn(login: user.login, password: user.password)
        ui.expect(app.staticTexts["Your organization requires two-step verification: set it up to continue."], timeout: 20)
        let password = app.secureTextFields["Password"]
        ui.expect(password)
        password.tap()
        password.typeText(user.password + "\n")
        let key = app.staticTexts["twoFactorSetup.secret"]
        ui.expect(key, timeout: 15)
        ui.expect(app.images["QR code to scan with your authenticator app"])
        let secret = key.label.replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(secret.range(of: "^[A-Z2-7]{16,}=*$", options: .regularExpression) != nil, secret)
        ui.shot("two-factor-key")
        let code = app.textFields["Verification code"]
        code.tap()
        code.typeText(try await TOTP.now(secret))
        app.buttons["Verify"].tap()
        let saved = app.buttons["I have saved them"]
        ui.expect(saved, timeout: 15)
        ui.shot("backup-codes")
        saved.tap()
        ui.expectSignedIn()

        // From now on the code is asked: a wrong one is refused and emptied, then the right one
        ui.signOutFromSettings()
        ui.signIn(login: user.login, password: user.password)
        ui.expect(app.staticTexts["Enter the 6-digit code shown by your authenticator app."], timeout: 20)
        let field = app.textFields["login.code"]
        let right = try await TOTP.now(secret)
        field.tap()
        field.typeText(right == "000000" ? "111111" : "000000")
        app.buttons["Verify"].tap()
        ui.expect(ui.loginError, timeout: 15)
        ui.shot("two-factor-refused")
        XCTAssertEqual(field.value as? String, "Verification code", "The refused code is emptied")
        field.tap()
        field.typeText(try await TOTP.now(secret))
        app.buttons["Verify"].tap()
        ui.expectSignedIn()
    }

    /// The system asks once whether the app may notify: at the first sign-in of a new installation. The answer
    /// stays on the simulator (XCUITest cannot reset it, a new installation within a day keeps it too), so only
    /// a simulator that never answered shows it (`xcrun simctl erase`).
    @MainActor
    func testFirstSignIn_asksForNotifications() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "firstrun")
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        // The question belongs to the system (in the language of the simulator, not of the app): it is answered
        // when it covers a tap. Its last button allows.
        var asked = false
        let monitor = addUIInterruptionMonitor(withDescription: "Notification question") { question in
            guard question.label.contains("Humble Planning"), let allow = question.buttons.allElementsBoundByIndex.last else { return false }
            asked = true
            ui.shot("notification-question")
            allow.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.launchArguments = ["-HPResetState", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-HPServer", TestServer.url, "-HPLogin", user.login, "-HPPassword", user.password, "-HPAutoSignIn", "YES"]
        app.launch()
        ui.expectSignedIn()
        // The system can take a while to show it (about 20 s on a simulator just started)
        let end = Date().addingTimeInterval(40)
        while !asked && Date() < end {
            app.tabBars.buttons["Planning"].tap()
            try await Task.sleep(for: .seconds(1))
        }
        try XCTSkipUnless(asked, "Notifications already answered on this simulator: not a new installation")
        // The settings of the app see the answer
        app.tabBars.buttons["Settings"].tap()
        ui.expect(app.images["Allowed"], timeout: 20)
        ui.shot("notifications-allowed")
    }
}
