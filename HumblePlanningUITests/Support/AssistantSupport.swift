import XCTest

// Helpers of AssistantUITests, AlertsUITests and SettingsUITests: what they prepare and read back on the test
// server, beside the app. Everything they create is titled "[iOS test] …" and removed by the test that made it.

/// "[iOS test] <what> <n>": a title no other run or test uses.
func uniqueTitle(_ what: String) -> String {
    "[iOS test] \(what) \(Int(Date().timeIntervalSince1970 * 10) % 10_000_000)"
}

/// A day as the server writes it (`yyyy-MM-dd`), `days` after today in the time zone of the simulator.
func isoDay(_ days: Int) -> String {
    let date = Calendar.current.date(byAdding: .day, value: days, to: Date())!
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
}

/// Holds what a request to the server answered, for a test that waits for it.
@MainActor
private final class Answer<T> {
    var result: Result<T, any Error>?
}

extension XCTestCase {
    // These tests stay synchronous, like TaskFlowUITests: an async test method stopped by its first failure
    // (`continueAfterFailure = false`) never lets its teardown blocks run, and the cleanup would never happen.

    /// The answer of requests to the server, waited for without blocking the main thread.
    @MainActor
    func server<T>(timeout: TimeInterval = 60, _ work: @escaping @MainActor () async throws -> T) throws -> T {
        let answer = Answer<T>()
        let done = XCTestExpectation(description: "server")
        Task { @MainActor in
            do { answer.result = .success(try await work()) } catch { answer.result = .failure(error) }
            done.fulfill()
        }
        _ = XCTWaiter().wait(for: [done], timeout: timeout)
        guard let result = answer.result else { throw TestAPIError.status(0, "no answer from the server in \(Int(timeout)) s") }
        return try result.get()
    }

    /// Cleanup on the server once the test is over, passed or failed.
    @MainActor
    func cleanUp(_ work: @escaping @MainActor () async -> Void) {
        addTeardownBlock { [weak self] in
            MainActor.assumeIsolated { _ = try? self?.server { await work() } }
        }
    }

    /// Waits until the server has what the app did: asks again every half second; nil (and a failure) when it
    /// never comes.
    @MainActor
    func firstFound<T>(_ what: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line,
                       _ find: @escaping @MainActor () async throws -> T?) throws -> T? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let found = try server(find) { return found }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("Never on the server: \(what)", file: file, line: line)
        return nil
    }

    /// Waits until the server shows what the app did (or did not do).
    @MainActor
    func eventually(_ what: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line,
                    _ condition: @escaping @MainActor () async throws -> Bool) throws {
        _ = try firstFound(what, timeout: timeout, file: file, line: line) { try await condition() ? true : nil }
    }
}

/// Ids of the seeded company the tests write with.
struct SeededData {
    let projectId: String
    /// The name alone: the alerts of the server begin with it.
    let projectName: String
    /// What the cards show for the project: "[number] name", or the name alone.
    let projectLabel: String
    let statusId: String
    let userIds: [String: String]

    func userId(_ login: String) -> String { userIds[login] ?? "" }
}

extension TestAPI {
    /// The first project, the default status and the accounts, read once per test.
    func seeded() async throws -> SeededData {
        let projects = try await call("GET", "/api/projects") as? [[String: Any]] ?? []
        let statuses = try await call("GET", "/api/statuses") as? [[String: Any]] ?? []
        let users = try await call("GET", "/api/users") as? [[String: Any]] ?? []
        guard let project = projects.first, let projectId = project["id"] as? String,
              let status = statuses.first(where: { $0["isDefault"] as? Bool == true }) ?? statuses.first,
              let statusId = status["id"] as? String else { throw TestAPIError.status(0, "no project or status") }
        let name = project["name"] as? String ?? ""
        let number = (project["businessNumber"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        var ids: [String: String] = [:]
        for user in users {
            if let login = user["username"] as? String, let id = user["id"] as? String { ids[login] = id }
        }
        return SeededData(projectId: projectId, projectName: name, projectLabel: number.isEmpty ? name : "[\(number)] \(name)",
                          statusId: statusId, userIds: ids)
    }

    /// A task of the seeded company, created by the administrator (so its people get an alert); returns its id.
    func createTask(_ title: String, for userIds: [String], on day: String, start: String? = nil, end: String? = nil,
                    seeded: SeededData) async throws -> String {
        var body: [String: Any] = ["projectId": seeded.projectId, "userIds": userIds, "statusId": seeded.statusId,
                                   "startDate": day, "title": title, "isMilestone": false]
        if let start { body["startTime"] = start }
        if let end { body["endTime"] = end }
        let task = try await call("POST", "/api/tasks", body) as? [String: Any]
        guard let id = task?["id"] as? String else { throw TestAPIError.status(0, "task without id") }
        return id
    }

    func updateTask(_ id: String, _ fields: [String: Any]) async throws {
        try await call("PUT", "/api/tasks/\(id)", fields)
    }

    /// The assistant of the server answers with the scripted model of the test server (tools/test-server of the
    /// Android repository), as tools/api-tests does. A setting of the whole server: turned on once, left on.
    func enableAssistant() async throws {
        let current = try await call("GET", "/api/ai-chat/admin/config") as? [String: Any]
        var config = current?["config"] as? [String: Any] ?? [:]
        let keyConfigured = (current?["apiKey"] as? [String: Any])?["configured"] as? Bool == true
        if config["enabled"] as? Bool == true, keyConfigured, (config["models"] as? [String])?.contains("test/model") == true { return }
        config["enabled"] = true
        config["apiKey"] = "test-key"
        config["models"] = ["test/model"]
        config["defaultModel"] = "test/model"
        try await call("PUT", "/api/ai-chat/admin/config", config)
    }

    /// Deletes a task, also when the test already did or never got that far.
    func deleteTask(_ id: String) async {
        _ = try? await call("DELETE", "/api/tasks/\(id)?scope=single")
    }

    /// The tasks of everyone on that day with that title.
    func tasks(titled title: String, on day: String) async throws -> [[String: Any]] {
        let sync = try await call("GET", "/api/mobile/tasks/sync?startDate=\(day)&endDate=\(day)") as? [String: Any]
        let changed = sync?["changed"] as? [[String: Any]] ?? []
        return changed.filter { $0["title"] as? String == title }
    }
}

/// A session of a seeded account opened by the test as another phone (`POST /api/mobile/auth/login`): reads what
/// the app wrote as this account, and is itself a device the app lists.
@MainActor
final class AccountSession {
    let deviceName: String
    private let cookie: String
    private let session = URLSession(configuration: .ephemeral)

    private init(deviceName: String, cookie: String) {
        self.deviceName = deviceName
        self.cookie = cookie
    }

    static func open(_ account: TestAccount, deviceName: String) async throws -> AccountSession {
        var request = URLRequest(url: URL(string: TestServer.url + "/api/mobile/auth/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "identifier": account.login, "password": account.password,
            "device": ["name": deviceName, "platform": "ios", "appVersion": "1.0.2", "locale": "en"],
        ])
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200, body?["status"] as? String == "authenticated",
              let session = body?["session"] as? [String: Any], let name = session["cookieName"] as? String,
              let value = session["cookieValue"] as? String else {
            throw TestAPIError.status((response as? HTTPURLResponse)?.statusCode ?? 0, "sign-in of \(account.login)")
        }
        return AccountSession(deviceName: deviceName, cookie: "\(name)=\(value)")
    }

    /// The status and JSON answer of a request.
    func send(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> (Int, Any?) {
        var request = URLRequest(url: URL(string: TestServer.url + path)!)
        request.httpMethod = method
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data))
    }

    /// Whether the server still accepts this session.
    var isAlive: Bool {
        get async { (try? await send("GET", "/api/profile").0) == 200 }
    }

    /// Signs this session out (already revoked: nothing happens).
    func close() async {
        _ = try? await send("POST", "/api/mobile/auth/logout")
    }

    /// The conversations of the account with the assistant: `[id: title]`.
    func conversations() async throws -> [String: String] {
        let (status, list) = try await send("GET", "/api/ai-chat/conversations")
        guard status == 200, let list = list as? [[String: Any]] else { throw TestAPIError.status(status, "conversations") }
        var titles: [String: String] = [:]
        for conversation in list {
            if let id = conversation["id"] as? String { titles[id] = conversation["title"] as? String ?? "" }
        }
        return titles
    }

    /// The first question of a conversation.
    func firstQuestion(of id: String) async throws -> String? {
        let (_, detail) = try await send("GET", "/api/ai-chat/conversations/\(id)")
        let messages = (detail as? [String: Any])?["messages"] as? [[String: Any]] ?? []
        return messages.first { $0["role"] as? String == "USER" }?["content"] as? String
    }

    /// The conversations the app started with a question holding these words: named after it (the beginning of
    /// the question, until the server names it after the first answer), or holding it as first question.
    func conversations(markedWith marker: String) async throws -> [String] {
        var found: [String] = []
        for (id, title) in try await conversations() {
            if title.contains(marker) {
                found.append(id)
            } else if try await firstQuestion(of: id)?.contains(marker) == true {
                found.append(id)
            }
        }
        return found
    }

    /// Renames a conversation, as the app's Rename does.
    func renameConversation(_ id: String, to title: String) async throws {
        let (status, _) = try await send("PATCH", "/api/ai-chat/conversations/\(id)", ["title": title])
        guard status == 200 else { throw TestAPIError.status(status, "rename conversation") }
    }

    func deleteConversation(_ id: String) async {
        _ = try? await send("DELETE", "/api/ai-chat/conversations/\(id)")
    }
}

extension Driver {
    /// The tab of the bar with this name, in the tab bar only (the iPhone layout): `tab(_:)` also looks in the
    /// iPad sidebar and among the buttons, too wide to prove that a tab is absent.
    func barTab(_ name: String) -> XCUIElement { app.tabBars.buttons[name] }

    /// A picker of a settings form (shown as "Title, value"): opens it and chooses an option.
    func choose(_ option: String, in picker: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", picker + ",")).firstMatch
        expect(button, file: file, line: line)
        scroll(to: button)
        button.tap()
        let item = app.buttons[option].firstMatch
        expect(item, file: file, line: line)
        item.tap()
        let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(picker), \(option)"), object: button)
        if XCTWaiter.wait(for: [chosen], timeout: 5) != .completed {
            shot("failure")
            XCTFail("\(picker) is not \(option): \(button.label)", file: file, line: line)
        }
    }

    /// Waits until the element stops moving (an alert goes up when the keyboard comes): a tap lands where it is.
    func waitStill(_ element: XCUIElement) {
        var frame = element.frame
        for _ in 0..<20 {
            usleep(250_000)
            let now = element.frame
            if now == frame { return }
            frame = now
        }
    }

    /// The system asks whether the app may notify: allowed. Nothing happens when it does not ask (already answered).
    func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    /// Mean brightness (0…1) of a strip of the screen far from any text: light or dark appearance.
    func backgroundBrightness() -> Double {
        let image = XCUIScreen.main.screenshot().image
        guard let cgImage = image.cgImage else { return -1 }
        let width = cgImage.width, height = cgImage.height
        // Bottom-left corner of the content, under the last section and beside the tab bar
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var total = 0.0
        let points = [(0.02, 0.3), (0.02, 0.5), (0.98, 0.4)]
        for (x, y) in points {
            guard let pixel = cgImage.cropping(to: CGRect(x: Int(Double(width) * x), y: Int(Double(height) * y), width: 1, height: 1)) else { continue }
            context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            total += (Double(data[0]) + Double(data[1]) + Double(data[2])) / (3 * 255)
        }
        return total / Double(points.count)
    }
}
