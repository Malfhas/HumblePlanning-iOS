import CryptoKit
import XCTest

/// What the sign-in, blocking and session tests share: accounts made for one test, the server as a browser or as
/// the app sees it, the codes of an authenticator app, and the sign-in screen.
enum SignInSupport {
    /// The stand-in server of tools/test-server (AI provider, push): it answers, but not like Humble Planning.
    static var mockURL: String { TestServer.environment["HP_MOCK"] ?? "http://localhost:3102" }

    /// The version the app sends today (`MARKETING_VERSION`), for the requests made "as the app".
    static let appVersion = "1.0.2"

    /// Messages of the server in English (src/messages/en of the server). Read here rather than asked to the
    /// server: every wrong password or used QR code counts on the lock of the address, which the parallel runs
    /// share.
    static let wrongPassword = "Incorrect username or password"
    static let usedPairingCode = "This QR code is no longer valid. Generate a new one from your profile."

    static func unique() -> String {
        "\(Int(Date().timeIntervalSince1970) % 1_000_000)-\(Int.random(in: 100...999))"
    }

    /// The sign-in link as the simulator reaches the server: the test server names itself for the Android
    /// emulator (`APP_BASE_URL` = 10.0.2.2), an address the simulator does not reach. The code stays as it is.
    static func reachable(_ link: String, server: String = TestServer.url) -> URL {
        var components = URLComponents(string: link)!
        components.queryItems = components.queryItems?.map { $0.name == "url" ? URLQueryItem(name: "url", value: server) : $0 }
        return components.url!
    }

    /// A link to that server with a code of the right shape that no server issued.
    static func link(to server: String, code: String = String(repeating: "a", count: 64)) -> URL {
        var components = URLComponents(string: "humbleplanning://login")!
        components.queryItems = [URLQueryItem(name: "url", value: server), URLQueryItem(name: "code", value: code)]
        return components.url!
    }

    static func code(of link: URL) -> String {
        URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value ?? ""
    }

    /// Waits until the condition holds, on the server or in the files of the app (a few seconds at most).
    @MainActor
    static func waitForServer(_ what: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line,
                              _ condition: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTFail("Timed out waiting for: \(what)", file: file, line: line)
    }
}

// MARK: - Accounts of a test

/// An account created by a test ("[iOS test] …", login "iostest-…"), deleted at the end of the test.
struct TestUser: Sendable {
    let id: String
    let login: String
    let password: String
    let name: String

    var account: TestAccount { TestAccount(login: login, password: password) }
}

/// The administrator's REST calls, like `TestAPI` but outside the main actor: the clean-up blocks make them too,
/// and an async clean-up block that waits for the main actor never ends (XCTest holds the main thread meanwhile).
struct AdminSession: Sendable {
    let cookie: String

    static func signIn() async throws -> AdminSession {
        let account = TestAccount.admin
        let answer = try await ServerCall.send("POST", "/api/auth/login", body: ["identifier": account.login, "password": account.password])
        guard answer.status == 200, !answer.cookies.isEmpty else { throw TestAPIError.status(answer.status, "admin sign-in") }
        return AdminSession(cookie: answer.cookies.joined(separator: "; "))
    }

    /// The answer of a request, which must succeed (2xx).
    @discardableResult
    func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> ServerAnswer {
        let answer = try await ServerCall.send(method, path, cookie: cookie, body: body)
        guard (200..<300).contains(answer.status) else {
            throw TestAPIError.status(answer.status, "\(method) \(path): \(String(decoding: answer.body.prefix(300), as: UTF8.self))")
        }
        return answer
    }

    func id(_ method: String, _ path: String, _ body: [String: Any]) async throws -> String {
        guard let id = try await call(method, path, body).object["id"] as? String else { throw TestAPIError.status(0, "\(method) \(path): no id") }
        return id
    }

    func roleId(named name: String) async throws -> String {
        guard let id = try await call("GET", "/api/roles").list.first(where: { $0["name"] as? String == name })?["id"] as? String else {
            throw TestAPIError.status(404, "role \(name)")
        }
        return id
    }

    func firstProjectId() async throws -> String {
        guard let id = try await call("GET", "/api/projects").list.first?["id"] as? String else { throw TestAPIError.status(404, "project") }
        return id
    }

    func defaultStatusId() async throws -> String {
        let statuses = try await call("GET", "/api/statuses").list
        guard let id = (statuses.first { $0["isDefault"] as? Bool == true } ?? statuses.first)?["id"] as? String else {
            throw TestAPIError.status(404, "status")
        }
        return id
    }

    /// A setting of Settings (`PUT /api/config`).
    func config(_ key: String) async throws -> String? {
        try await call("GET", "/api/config").object[key] as? String
    }

    func setConfig(_ key: String, _ value: String) async throws {
        try await call("PUT", "/api/config", [key: value])
    }
}

extension XCTestCase {
    /// A new active account of this test, hidden from the planning of the others; deleted at the end of the
    /// test, even when it fails. A Technician (a seeded role, which has the mobile app) unless `roleId`.
    @MainActor
    func newUser(_ admin: AdminSession, _ label: String, roleId: String? = nil, forceTwoFactor: Bool = false) async throws -> TestUser {
        let suffix = SignInSupport.unique()
        let login = "iostest-\(label)-\(suffix)"
        let name = "[iOS test] \(label) \(suffix)"
        let password = "iOS-Test-\(UUID().uuidString.prefix(8))-Aa9!"
        var role = roleId ?? ""
        if role.isEmpty { role = try await admin.roleId(named: "Technician") }
        let id = try await admin.id("POST", "/api/users", [
            "name": name, "username": login, "password": password, "roleId": role, "color": "#3366ff",
            "visibleOnPlanning": false, "notifications": false, "pushNotifications": false, "smsNotifications": false,
            "active": true, "forceTwoFactor": forceTwoFactor,
        ])
        addTeardownBlock { try await admin.call("DELETE", "/api/users/\(id)") }
        return TestUser(id: id, login: login, password: password, name: name)
    }

    /// A new role of this test, deleted at its end (after its users, created later).
    @MainActor
    func newRole(_ admin: AdminSession, _ label: String, permissions: [String]) async throws -> String {
        let id = try await admin.id("POST", "/api/roles", ["name": "[iOS test] \(label) \(SignInSupport.unique())", "permissions": permissions])
        addTeardownBlock { try await admin.call("DELETE", "/api/roles/\(id)") }
        return id
    }

    /// A task of today for that person, made by the administrator; deleted at the end of the test.
    @MainActor
    func newTask(_ admin: AdminSession, _ title: String, for user: TestUser) async throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let project = try await admin.firstProjectId()
        let status = try await admin.defaultStatusId()
        let id = try await admin.id("POST", "/api/tasks", [
            "projectId": project, "statusId": status, "userIds": [user.id], "startDate": formatter.string(from: Date()),
            "title": title, "isMilestone": false,
        ])
        addTeardownBlock { try await admin.call("DELETE", "/api/tasks/\(id)?scope=single") }
        return id
    }
}

// MARK: - The server as others see it

/// One answer of the server, whatever its status.
struct ServerAnswer: Sendable {
    let status: Int
    let body: Data
    /// `name=value` of the cookies it set.
    let cookies: [String]

    var object: [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
    var list: [[String: Any]] { (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]] ?? [] }
    /// The translated message of a refusal.
    var error: String { object["error"] as? String ?? "" }
}

enum ServerCall {
    static func send(_ method: String, _ path: String, cookie: String? = nil, body: [String: Any]? = nil,
                     headers: [String: String] = [:]) async throws -> ServerAnswer {
        let url = URL(string: TestServer.url + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue(([cookie, "HP_LOCALE=en"].compactMap { $0 }).joined(separator: "; "), forHTTPHeaderField: "Cookie")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let http = response as! HTTPURLResponse
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: http.allHeaderFields as? [String: String] ?? [:], for: url)
        return ServerAnswer(status: http.statusCode, body: data, cookies: cookies.map { "\($0.name)=\($0.value)" })
    }

    /// What the app sends with each request (version and platform).
    static let appHeaders = ["X-App-Version": SignInSupport.appVersion, "X-App-Platform": "ios"]

    /// The sign-in of the app for that account, as another phone would do it.
    static func appSignIn(_ login: String, _ password: String) async throws -> ServerAnswer {
        try await send("POST", "/api/mobile/auth/login", body: ["identifier": login, "password": password, "device": ["name": "rest"]],
                       headers: appHeaders)
    }

    /// Uses the code of a sign-in link, as another phone would.
    static func redeemPairing(_ code: String) async throws -> ServerAnswer {
        try await send("POST", "/api/mobile/auth/pairing", body: ["code": code, "device": ["name": "rest"]], headers: appHeaders)
    }

    /// The session cookie of a successful app sign-in.
    static func sessionCookie(_ answer: ServerAnswer) -> String? {
        guard let session = answer.object["session"] as? [String: Any], let name = session["cookieName"] as? String,
              let value = session["cookieValue"] as? String else { return nil }
        return "\(name)=\(value)"
    }
}

struct ServerDevice: Sendable {
    let id: String
    let name: String
}

/// A browser session of a test account: what its web profile does (devices, the QR code).
struct WebSession: Sendable {
    let cookie: String

    static func signIn(_ user: TestUser) async throws -> WebSession {
        let answer = try await ServerCall.send("POST", "/api/auth/login", body: ["identifier": user.login, "password": user.password])
        guard answer.status == 200, !answer.cookies.isEmpty else { throw TestAPIError.status(answer.status, "web sign-in \(user.login)") }
        return WebSession(cookie: answer.cookies.joined(separator: "; "))
    }

    /// The phones signed in to the account.
    func devices() async throws -> [ServerDevice] {
        let answer = try await ServerCall.send("GET", "/api/mobile/devices", cookie: cookie)
        guard answer.status == 200 else { throw TestAPIError.status(answer.status, "devices") }
        return answer.list.compactMap { device in
            (device["id"] as? String).map { ServerDevice(id: $0, name: device["deviceName"] as? String ?? "") }
        }
    }

    /// The link of a new QR code of the web profile.
    func pairingLink() async throws -> String {
        let answer = try await ServerCall.send("POST", "/api/mobile/pairing", cookie: cookie, headers: ["Sec-Fetch-Site": "same-origin"])
        guard answer.status == 201, let link = answer.object["link"] as? String else { throw TestAPIError.status(answer.status, "pairing") }
        return link
    }

    /// Signs that phone out, as from the web profile.
    func revoke(device id: String) async throws {
        let answer = try await ServerCall.send("DELETE", "/api/mobile/devices/\(id)", cookie: cookie)
        guard answer.status == 200 else { throw TestAPIError.status(answer.status, "revoke") }
    }
}

// MARK: - Authenticator app

/// RFC 6238 codes (SHA-1, 30 s, 6 digits), what an authenticator app shows for the key.
enum TOTP {
    /// A code that still has time to reach the server (in the last 6 s of a period, the next one): the one wait
    /// on a clock of these tests, the code itself depends on it.
    static func now(_ secret: String) async throws -> String {
        let left = 30 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 30)
        if left < 6 { try await Task.sleep(for: .seconds(left + 0.2)) }
        return code(secret, at: Date())
    }

    static func code(_ secret: String, at date: Date) -> String {
        var counter = UInt64(date.timeIntervalSince1970 / 30).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: base32(secret))))
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let value = (UInt32(mac[offset]) & 0x7f) << 24 | UInt32(mac[offset + 1]) << 16 | UInt32(mac[offset + 2]) << 8 | UInt32(mac[offset + 3])
        let text = String(value % 1_000_000)
        return String(repeating: "0", count: 6 - text.count) + text
    }

    /// The bytes of a base 32 key (RFC 4648, padding and case ignored).
    static func base32(_ text: String) -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bytes = Data()
        var buffer = 0, bits = 0
        for character in text.uppercased() where character != "=" {
            guard let index = alphabet.firstIndex(of: character) else { continue }
            buffer = (buffer << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return bytes
    }
}

// MARK: - Files of the app (simulator)

enum AppFiles {
    /// The data folder of the app: on the simulator, next to the one of this runner, the newest folder whose
    /// metadata names the app (an earlier installation may leave its own for a while).
    static func container(of bundleId: String = "com.humbleplanning.app") -> URL? {
        let applications = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory).deletingLastPathComponent()
        let folders = (try? FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return folders
            .filter { folder in
                let metadata = NSDictionary(contentsOf: folder.appending(path: ".com.apple.mobile_container_manager.metadata.plist"))
                return metadata?["MCMMetadataIdentifier"] as? String == bundleId
            }
            .max { a, b in
                let first = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let second = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return first < second
            }
    }

    /// The encrypted offline copy of my tasks has been written.
    static var offlineCopyExists: Bool {
        guard let container = container() else { return false }
        return FileManager.default.fileExists(atPath: container.appending(path: "Library/Application Support/offline/tasks.bin").path(percentEncoded: false))
    }
}

// MARK: - The sign-in screen

@MainActor
extension Driver {
    var signInButton: XCUIElement { app.buttons["login.signIn"] }
    var loginError: XCUIElement { app.descendants(matching: .any)["login.error"] }
    var loginNotice: XCUIElement { app.descendants(matching: .any)["login.notice"] }

    /// Starts the app on what it kept (session, settings), as after an update; signs in when `account`.
    func relaunch(as account: TestAccount? = nil, _ arguments: String...) {
        app.terminate()
        var launch = ["-HPSkipNotificationPrompt", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let account {
            launch += ["-HPServer", TestServer.url, "-HPLogin", account.login, "-HPPassword", account.password, "-HPAutoSignIn", "YES"]
        }
        app.launchArguments = launch + arguments
        app.launch()
    }

    func expectSignInScreen(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        expect(signInButton, timeout: timeout, file: file, line: line)
        XCTAssertFalse(app.tabBars.buttons["Planning"].exists, "Still signed in", file: file, line: line)
    }

    /// The error above the sign-in form says exactly this.
    func expectLoginError(_ message: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        expect(loginError, timeout: timeout, file: file, line: line)
        XCTAssertEqual(loginError.label, message, file: file, line: line)
    }

    /// Fills the form (every field replaced) and signs in with the Go key of the password.
    func signIn(server: String = TestServer.url, login: String, password: String) {
        fill(app.textFields["login.server"], with: server)
        fill(app.textFields["login.identifier"], with: login)
        typePassword(password)
    }

    /// Replaces the password and signs in with the Go key.
    func typePassword(_ password: String) {
        let field = app.secureTextFields["login.password"]
        expect(field)
        field.tap()
        // A secure field empties itself at the first key of a new edit
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + password + "\n")
    }

    /// Replaces the whole text of a field, the cursor at its end.
    func fill(_ field: XCUIElement, with text: String) {
        expect(field)
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 8) + text)
    }

    /// Settings → Sign out, refused once then confirmed: back on the sign-in screen.
    func signOutFromSettings(cancelFirst: Bool = false) {
        app.tabBars.buttons["Settings"].tap()
        expect(app.navigationBars["Settings"])
        let button = app.buttons["settings.signOut"]
        // At the end of the list, built as it scrolls
        scroll(to: button)
        expect(button)
        let alert = app.alerts["Sign out"]
        if cancelFirst {
            button.tap()
            expect(alert)
            alert.buttons["Cancel"].tap()
            expectGone(alert)
            XCTAssertTrue(app.tabBars.buttons["Settings"].exists, "Still signed in after Cancel")
        }
        button.tap()
        expect(alert)
        shot("sign-out-question")
        alert.buttons["Sign out"].tap()
        expectSignInScreen()
    }

    /// A finger on that tab, under the blocking screen, does not reach it.
    func expectTabUntouchable(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[name]
        expect(tab, file: file, line: line)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tab.frame.midX, dy: tab.frame.midY)).tap()
        XCTAssertFalse(tab.isSelected, "The tab under the blocking screen was reached", file: file, line: line)
        XCTAssertFalse(app.navigationBars[name].exists, file: file, line: line)
    }

    /// The question asked before following a sign-in link.
    var linkQuestion: XCUIElement { app.alerts["Sign in to this server?"] }

    /// Opens a link through the system, as the camera or another app would. (`XCUIApplication.open` launches the
    /// app again with its launch arguments, which would start it as just installed.)
    func open(_ link: URL) {
        XCUIDevice.shared.system.open(link)
    }
}
