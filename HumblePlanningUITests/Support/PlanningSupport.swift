import XCTest

/// The days of the planning tests, written as the app writes them. The seeded company works around the Monday of
/// the current week (tools/screenshots/seed.mjs), with a public holiday on its Wednesday.
struct PlanningDays {
    let language: String
    let today: Date
    private let calendar: Calendar
    private let locale: Locale

    init(language: String = "en") {
        self.language = language
        locale = Locale(identifier: language == "fr" ? "fr_FR" : "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        self.calendar = calendar
        today = calendar.startOfDay(for: Date())
    }

    /// Monday of the current week.
    var monday: Date { day(-((calendar.component(.weekday, from: today) + 5) % 7), from: today) }
    /// The seeded public holiday.
    var holiday: Date { day(2) }
    static let holidayLabel = "Armistice Day"
    /// The holiday under a day title, as VoiceOver reads it: its icon in words, then its name.
    static let spokenHolidayLabel = "Public holiday, " + holidayLabel

    /// A day counted from Monday (or from another day).
    func day(_ offset: Int, from start: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start ?? monday)!
    }

    /// "Monday 9 November", fr "Lundi 9 novembre"; lower case inside a sentence.
    func long(_ date: Date, capitalized: Bool = true) -> String {
        let text = format(date, "EEEE d MMMM")
        return capitalized ? text.prefix(1).uppercased() + text.dropFirst() : text
    }

    /// "Nov 9, 2026", fr "9 nov. 2026".
    func medium(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// "November 2026", fr "Novembre 2026".
    func month(_ date: Date) -> String {
        let text = format(date, "LLLL yyyy")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "2026-11-09", as the server writes it.
    func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The title of a page of the Week view.
    func weekOf(_ monday: Date) -> String {
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: monday)
        return language == "fr" ? "Semaine du \(long(monday, capitalized: false)) · S\(week)"
                                : "Week of \(long(monday, capitalized: false)) · W\(week)"
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// A unique title for a task a test makes, so that it is never mistaken for one of the seed or of another test.
func testTitle(_ name: String) -> String {
    "[iOS test] \(name) \(UUID().uuidString.prefix(6))"
}

// MARK: - On screen

@MainActor
extension Driver {
    /// A view of the planning (the segment of that name: Day, Week, Month, Grid, or their translation).
    func show(_ view: String) {
        let segment = app.segmentedControls.buttons[view]
        expect(segment)
        segment.tap()
        waitSelected(segment)
    }

    func waitSelected(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: element)
        if XCTWaiter.wait(for: [selected], timeout: 10) != .completed {
            shot("failure")
            XCTFail("Not selected: \(element)", file: file, line: line)
        }
    }

    /// Waits until the element is on the screen and can be touched (not only built off screen by a pager).
    func expectVisible(_ element: XCUIElement, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        if XCTWaiter.wait(for: [shown], timeout: timeout) != .completed {
            shot("failure")
            XCTFail("Not on screen: \(element)\n\(app.debugDescription)", file: file, line: line)
        }
    }

    /// Waits for something the queries cannot express (a position on screen…), looking again every 0.2 s.
    func waitUntil(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                   _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                shot("failure")
                XCTFail("Timed out: \(what)", file: file, line: line)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// Checks that nothing matching shows up for a moment.
    func expectAbsent(_ element: XCUIElement, for seconds: TimeInterval = 1, _ message: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        if element.waitForExistence(timeout: seconds) {
            shot("failure")
            XCTFail("Should not be there (\(message)): \(element)", file: file, line: line)
        }
    }

    /// The title of a day (Day view, or under the month).
    func heading(_ text: String) -> XCUIElement {
        app.staticTexts[text].firstMatch
    }

    /// A card (or a grid bar) whose text contains these words, on the screen rather than on a neighbouring page;
    /// the list scrolls to it when it is below or above.
    func visibleCard(_ text: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let query = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text))
        let screen = app.windows.firstMatch.frame
        func onScreen() -> XCUIElement? {
            for index in 0..<query.count {
                let card = query.element(boundBy: index)
                if card.exists, screen.contains(CGPoint(x: card.frame.midX, y: card.frame.minY + 8)), card.isHittable { return card }
            }
            return nil
        }
        if query.firstMatch.waitForExistence(timeout: timeout) {
            // Loaded: on screen, else further down, else further up
            for swipe in [nil] + Array(repeating: true, count: 4) + Array(repeating: false, count: 8) {
                if let swipe { swipe ? app.swipeUp(velocity: .slow) : app.swipeDown(velocity: .slow) }
                if let card = onScreen() { return card }
            }
        }
        shot("failure")
        XCTFail("No card on screen with \"\(text)\"\n\(app.debugDescription)", file: file, line: line)
        return query.firstMatch
    }

    /// The day of the strip of the Day view (or a cell of the Month view).
    func tapDay(_ label: String) {
        let day = app.buttons[label].firstMatch
        expectVisible(day)
        day.tap()
        waitSelected(day)
    }

    // MARK: Filters

    func openFilters() {
        app.buttons["Filters"].firstMatch.tap()
        expect(app.navigationBars["Filters"])
    }

    func applyFilters() {
        app.buttons["Apply"].tap()
        expectGone(app.navigationBars["Filters"])
    }

    /// Ticks or unticks rows of the open picker, then confirms it.
    func pick(_ names: [String]) {
        let list = app.collectionViews["picker.list"]
        expect(list)
        for name in names {
            let row = list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            expect(row)
            row.tap()
        }
        app.buttons["picker.done"].tap()
        expectGone(list)
    }

    /// "All projects" (or teams, statuses) turned off opens the picker: these rows are chosen.
    func filterOnly(_ switchLabel: String, _ names: [String]) {
        openFilters()
        toggle(app.switches[switchLabel])
        pick(names)
        applyFilters()
    }

    var filterBadge: String { app.buttons["Filters"].firstMatch.value as? String ?? "" }

    // MARK: Grid

    /// The row of a person on the grid (its name, in the names column).
    func gridRow(_ person: String) -> XCUIElement {
        app.otherElements.matching(NSPredicate(format: "label == %@", person)).firstMatch
    }

    /// The column of a day on the grid ("Wednesday 11 November, Armistice Day").
    func gridColumn(_ day: String) -> XCUIElement {
        app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", day)).firstMatch
    }

    /// Taps the grid where the row of the person meets the column of the day, from their accessibility frames.
    func tapGrid(person: String, day: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = gridRow(person), column = gridColumn(day)
        expect(row, file: file, line: line)
        expect(column, file: file, line: line)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: column.frame.midX, dy: row.frame.midY))
            .tap()
    }

    /// Back from a task detail to the planning.
    func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expect(app.segmentedControls.firstMatch)
    }
}

// MARK: - Data of the tests

/// The REST API of the test server as its administrator, one request at a time while the test waits (like Rest.kt
/// of the Android tests): the tests stay synchronous, so that a failure stops them cleanly. What a test makes here
/// is deleted at its end, also when it fails.
@MainActor
final class PlanningServer {
    private let api: TestAPI
    private let test: XCTestCase

    init(_ test: XCTestCase) throws {
        self.test = test
        api = try answer { try await TestAPI.admin() }
    }

    func userId(_ login: String) throws -> String {
        try id(in: "/api/users", where: "username", is: login)
    }

    func projectId(_ name: String) throws -> String {
        try id(in: "/api/projects", where: "name", is: name)
    }

    /// The tasks of these days as the server returns them (title, startDate, users…).
    func tasks(from start: String, to end: String) throws -> [[String: Any]] {
        try list("/api/tasks?startDate=\(start)&endDate=\(end)")
    }

    /// A one-day, all-day task of a seeded project for these people, with the default status.
    func createTask(_ title: String, for userIds: [String], on day: String, project: String = "Riverside Clinic") throws -> String {
        let statuses = try list("/api/statuses")
        let status = statuses.first { $0["isDefault"] as? Bool == true } ?? statuses[0]
        let body: [String: Any] = [
            "projectId": try projectId(project), "userIds": userIds, "statusId": status["id"] as! String,
            "startDate": day, "title": title, "isMilestone": false,
        ]
        let id = try created("/api/tasks", body)
        removeAtEnd("/api/tasks/\(id)?scope=single")
        return id
    }

    func renameTask(_ id: String, to title: String) throws {
        try call("PUT", "/api/tasks/\(id)", ["title": title, "isMilestone": false])
    }

    func deleteTask(_ id: String) throws {
        try call("DELETE", "/api/tasks/\(id)?scope=single")
    }

    /// A role with these permissions and an account with it (its login is the name of both).
    func createAccount(_ name: String, permissions: [String]) throws -> (id: String, account: TestAccount) {
        let roleId = try created("/api/roles", ["name": name, "color": "#64748b", "permissions": permissions])
        removeAtEnd("/api/roles/\(roleId)")
        let account = TestAccount(login: name, password: "IosTest-2026!" + name.suffix(6))
        let userId = try created("/api/users", [
            "name": name, "username": account.login, "password": account.password, "roleId": roleId, "color": "#3366ff",
            "visibleOnPlanning": true, "notifications": false, "pushNotifications": false, "smsNotifications": false, "active": true,
        ])
        removeAtEnd("/api/users/\(userId)")
        return (userId, account)
    }

    /// Attaches a small PDF to a task, as the web does (a multipart upload, through a web session of its own).
    func attachPDF(_ name: String, to taskId: String) throws {
        try answer {
            let session = URLSession(configuration: .ephemeral)
            var login = URLRequest(url: URL(string: TestServer.url + "/api/auth/login")!)
            login.httpMethod = "POST"
            login.setValue("application/json", forHTTPHeaderField: "Content-Type")
            login.httpBody = try JSONSerialization.data(withJSONObject: ["identifier": TestAccount.admin.login,
                                                                        "password": TestAccount.admin.password])
            let (_, response) = try await session.data(for: login)
            let headers = (response as! HTTPURLResponse).allHeaderFields as? [String: String] ?? [:]
            let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: login.url!)
                .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

            let boundary = "iostest-\(UUID().uuidString)"
            var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".utf8)
            body.append(Data("Content-Type: application/pdf\r\n\r\n%PDF-1.4\n%%EOF\n\r\n--\(boundary)--\r\n".utf8))
            var upload = URLRequest(url: URL(string: TestServer.url + "/api/tasks/\(taskId)/files")!)
            upload.httpMethod = "POST"
            upload.setValue(cookie, forHTTPHeaderField: "Cookie")
            upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let (data, uploaded) = try await session.upload(for: upload, from: body)
            let status = (uploaded as! HTTPURLResponse).statusCode
            guard (200..<300).contains(status) else {
                throw TestAPIError.status(status, "upload: \(String(decoding: data.prefix(300), as: UTF8.self))")
            }
        }
    }

    /// Deleted when the test ends: teardown blocks run last added first, so what depends on something goes first.
    func removeAtEnd(_ path: String) {
        test.addTeardownBlock { [api] in
            MainActor.assumeIsolated {
                do {
                    try answer { try await api.call("DELETE", path) }
                } catch TestAPIError.status(404, _) {
                    // Already deleted by the test itself
                } catch {
                    XCTFail("Not removed: \(path): \(error)")
                }
            }
        }
    }

    /// A task the app makes during the test: found by its title when the test ends, and deleted.
    func removeAtEnd(titled title: String, from start: String, to end: String) {
        test.addTeardownBlock { [self] in
            MainActor.assumeIsolated {
                do {
                    for task in try tasks(from: start, to: end) where task["title"] as? String == title {
                        try deleteTask(task["id"] as! String)
                    }
                } catch {
                    XCTFail("Not removed: \(title): \(error)")
                }
            }
        }
    }

    // MARK: Requests

    @discardableResult
    private func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) throws -> Any? {
        let api = api
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try answer {
            let json = try payload.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
            return try await api.call(method, path, json)
        }
    }

    private func created(_ path: String, _ body: [String: Any]) throws -> String {
        guard let id = (try call("POST", path, body) as? [String: Any])?["id"] as? String else {
            throw TestAPIError.status(0, "POST \(path): no id")
        }
        return id
    }

    private func list(_ path: String) throws -> [[String: Any]] {
        let json = try call("GET", path)
        return json as? [[String: Any]] ?? (json as? [String: Any])?["data"] as? [[String: Any]] ?? []
    }

    private func id(in path: String, where key: String, is value: String) throws -> String {
        guard let id = try list(path).first(where: { $0[key] as? String == value })?["id"] as? String else {
            throw TestAPIError.status(404, "\(path): no \(key) \(value)")
        }
        return id
    }
}

/// The answer of async work, waited for with the run loop turning (the main actor and the app's events go on).
@MainActor
@discardableResult
private func answer<T>(_ work: @escaping @MainActor () async throws -> T) throws -> T {
    let box = AnswerBox<T>()
    let done = XCTestExpectation(description: "answer of the server")
    Task { @MainActor in
        do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
        done.fulfill()
    }
    _ = XCTWaiter().wait(for: [done], timeout: 60)
    guard let result = box.result else { throw TestAPIError.status(0, "no answer from the server within 60 s") }
    return try result.get()
}

@MainActor
private final class AnswerBox<T> {
    var result: Result<T, any Error>?
}
