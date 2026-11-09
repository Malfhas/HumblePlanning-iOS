import XCTest

/// `humbleplanning://login?url=…&code=…`, the QR code of the web profile, like SignInLinkTest of the Android app:
/// nothing goes to the server of a link before the person says so.
///
/// The links come from `POST /api/mobile/pairing` with a browser session of an account made for the test.
final class SignInLinkUITests: XCTestCase {
    @MainActor
    func testALinkAsksFirst_aRefusalSendsNothing_badLinksAreNotAccepted() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "linkrefused")
        let web = try await WebSession.signIn(user)
        let link = SignInSupport.reachable(try await web.pairingLink())
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        ui.launchSignedOut()
        ui.expectSignInScreen()
        ui.open(link)
        let question = ui.linkQuestion
        ui.expect(question)
        XCTAssertTrue(question.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "localhost:3100")).firstMatch.exists,
                      "The server is shown in clear")
        ui.shot("link-question")
        let before = try await web.devices().count
        XCTAssertEqual(before, 0, "Nothing on the server while the question is on screen")
        question.buttons["Cancel"].tap()
        ui.expectGone(question)
        let after = try await web.devices().count
        XCTAssertEqual(after, 0, "No session for a refused link")
        let redeemed = try await ServerCall.redeemPairing(SignInSupport.code(of: link))
        XCTAssertEqual(redeemed.object["status"] as? String, "authenticated", "The app did not use the code")

        // Not a sign-in link: ignored
        ui.open(SignInSupport.link(to: TestServer.url, code: "short"))
        XCTAssertFalse(question.waitForExistence(timeout: 2))
        // An address the app does not connect to, whatever hides in it: said so, no way forward
        let refused = app.alerts["Link not accepted"]
        for server in ["http://example.com", "https://planning.example.com@evil.example"] {
            ui.open(SignInSupport.link(to: server))
            ui.expect(refused)
            XCTAssertFalse(question.exists)
            ui.shot("link-refused")
            refused.buttons["Close"].tap()
            ui.expectGone(refused)
        }
        ui.expectSignInScreen()
    }

    @MainActor
    func testAValidLinkSignsIn_aReplayIsRefused() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "linkvalid")
        let web = try await WebSession.signIn(user)
        let link = SignInSupport.reachable(try await web.pairingLink())
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        ui.launchSignedOut()
        ui.expectSignInScreen()
        ui.open(link)
        ui.expect(ui.linkQuestion)
        ui.linkQuestion.buttons["Sign in"].tap()
        ui.expectSignedIn()
        try await SignInSupport.waitForServer("the session of the app") { try await web.devices().count == 1 }
        // Signed in as the account of the link
        app.tabBars.buttons["Settings"].tap()
        ui.expect(app.staticTexts[user.name])
        ui.shot("signed-in-by-link")

        // The code worked once
        ui.signOutFromSettings()
        ui.open(link)
        ui.expect(ui.linkQuestion)
        ui.linkQuestion.buttons["Sign in"].tap()
        ui.expectLoginError(SignInSupport.usedPairingCode)
        ui.shot("link-used")
        ui.expectSignInScreen()
        let left = try await web.devices().count
        XCTAssertEqual(left, 0)
    }

    @MainActor
    func testWhileSignedIn_refusingKeepsTheSession_confirmingSignsOutFirst() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "linkleave")
        let web = try await WebSession.signIn(user)
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app

        ui.launch(as: user.account)
        ui.expectSignedIn()
        try await SignInSupport.waitForServer("the session of the app") { try await web.devices().count == 1 }

        // The port is part of what the person decides on
        let elsewhere = SignInSupport.link(to: SignInSupport.mockURL)
        let host = URLComponents(string: SignInSupport.mockURL).map { "\($0.host ?? ""):\($0.port ?? 0)" } ?? ""
        ui.open(elsewhere)
        let question = ui.linkQuestion
        ui.expect(question)
        ui.shot("link-question-signed-in")
        XCTAssertTrue(question.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", host)).firstMatch.exists, host)
        XCTAssertTrue(question.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "You will first be signed out")).firstMatch.exists,
                      "Warned about the sign-out")
        question.buttons["Cancel"].tap()
        ui.expectGone(question)
        ui.waitHittable(app.tabBars.buttons["Planning"], true, timeout: 5)
        let kept = try await web.devices().count
        XCTAssertEqual(kept, 1, "Refusing keeps the session")

        ui.open(elsewhere)
        ui.expect(question)
        question.buttons["Sign in"].tap()
        // That server answers no sign-in: said so, signed out of the first one
        ui.expectLoginError("This address is not a Humble Planning server.")
        ui.shot("link-elsewhere")
        ui.expectSignInScreen()
        try await SignInSupport.waitForServer("the old session closed on its server") { try await web.devices().isEmpty }
    }
}
