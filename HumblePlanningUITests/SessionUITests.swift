import XCTest

/// The session over time, like SessionTest of the Android app: without network the app shows the offline copy of
/// my tasks and says so, then reads the server again when the network is back; a session ended on the server
/// brings the sign-in screen back with a notice.
///
/// The test server cannot be cut: the network is cut in the app only (`humbleplanning://debug/offline` and
/// `/online`, debug builds), which tells the app as its network monitor would.
final class SessionUITests: XCTestCase {
    @MainActor
    func testOffline_showsTheBannerAndMyCopy_andNetworkBackReadsTheServer() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "offline")
        let mine = "[iOS test] offline mine \(SignInSupport.unique())"
        _ = try await newTask(admin, mine, for: user)
        let ui = Driver(test: self, shots: TestServer.shots)
        let app = ui.app
        let banner = ui.any(containing: "Offline:")

        ui.launch(as: user.account)
        ui.expectSignedIn()
        ui.expect(ui.any(containing: mine), timeout: 20)
        try await SignInSupport.waitForServer("offline copy written", timeout: 20) { AppFiles.offlineCopyExists }

        ui.open(URL(string: "humbleplanning://debug/offline")!)
        ui.expect(banner)
        // Read again, from the copy: another view, then the day again
        app.buttons["Week"].tap()
        app.buttons["Day"].tap()
        ui.expect(ui.any(containing: mine), timeout: 10)
        ui.expect(banner)
        ui.shot("planning-offline")
        app.tabBars.buttons["Upcoming"].tap()
        _ = ui.card(mine)
        ui.expect(banner)
        ui.shot("upcoming-offline")

        // The task opens from the copy, but the copy holds what a card shows, not the whole task: no form from it
        ui.card(mine).tap()
        let edit = app.buttons["Edit"]
        ui.expect(edit, timeout: 15)
        edit.tap()
        ui.expect(app.staticTexts["Server unreachable: check your internet connection."], timeout: 15)
        XCTAssertFalse(app.textFields["form.title"].exists)
        XCTAssertFalse(app.buttons["form.save"].isEnabled)
        ui.shot("form-offline")
        app.buttons["form.cancel"].tap()
        ui.expectGone(app.buttons["form.cancel"])
        app.navigationBars.buttons.element(boundBy: 0).tap()
        _ = ui.card(mine)

        // A task planned meanwhile: not in the copy
        let added = "[iOS test] offline added \(SignInSupport.unique())"
        _ = try await newTask(admin, added, for: user)
        XCTAssertFalse(ui.cardIfAny(added).waitForExistence(timeout: 3))

        // Network back: the server again, without a gesture
        ui.open(URL(string: "humbleplanning://debug/online")!)
        _ = ui.card(added)
        ui.expectGone(banner)
        ui.shot("upcoming-back-online")
        app.tabBars.buttons["Planning"].tap()
        ui.expect(ui.any(containing: added), timeout: 15)
        XCTAssertFalse(banner.exists)
    }

    @MainActor
    func testRevokedDevice_goesBackToSignIn_withTheNotice() async throws {
        try TestServer.require()
        continueAfterFailure = false
        let admin = try await AdminSession.signIn()
        let user = try await newUser(admin, "revoked")
        let web = try await WebSession.signIn(user)
        let ui = Driver(test: self, shots: TestServer.shots)

        ui.launch(as: user.account)
        ui.expectSignedIn()
        // A task planned now shows without a gesture: the real time is connected and hears the server
        let probe = "[iOS test] before revoke \(SignInSupport.unique())"
        _ = try await newTask(admin, probe, for: user)
        ui.expect(ui.any(containing: probe), timeout: 20)

        let devices = try await web.devices()
        XCTAssertEqual(devices.count, 1)
        try await web.revoke(device: try XCTUnwrap(devices.first).id)
        // No gesture: told by the server
        ui.expect(ui.loginNotice, timeout: 20)
        XCTAssertEqual(ui.loginNotice.label, "Your session has expired: please sign in again.")
        ui.shot("session-ended")
        ui.expectSignInScreen()
        XCTAssertFalse(ui.loginError.exists)
    }
}
