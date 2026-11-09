import XCTest

/// An issue of the accessibility audit that is not a fault of the app, with the reason it is accepted.
struct AuditException {
    let reason: String
    let matches: @MainActor (XCUIAccessibilityAuditIssue, XCUIApplication) -> Bool

    /// Text in the colours of the system (a section header of a form, the primary label on a grey fill) that the audit
    /// measures wrongly on the iPad; checked on the screenshot of the screen.
    static func systemColours(_ labels: String...) -> AuditException {
        AuditException(reason: "text in system colours, checked on the screenshot") { issue, _ in
            issue.auditType == .contrast && labels.contains { issue.element?.label.hasPrefix($0) ?? false }
        }
    }

    /// Contrast of what lies above this element: the header of a task detail, black or dark grey text on a light
    /// tint of the colour of the project (7:1 or more), which the audit misreads on the iPad.
    static func above(_ anchor: XCUIElement, reason: String) -> AuditException {
        AuditException(reason: reason) { issue, _ in
            guard issue.auditType == .contrast, let element = issue.element, element.exists, anchor.exists else { return false }
            return element.frame.maxY <= anchor.frame.minY
        }
    }

    /// Contrast of the rows of a list on the Liquid Glass of a sheet at its medium height (black text): the audit
    /// measures them through the glass.
    static func inside(_ container: XCUIElement, reason: String) -> AuditException {
        AuditException(reason: reason) { issue, _ in
            guard issue.auditType == .contrast, let element = issue.element, element.exists, container.exists else { return false }
            return container.frame.insetBy(dx: -2, dy: -2).contains(element.frame)
        }
    }

    /// Liquid Glass buttons of the screen, by label: their text is white on the violet of the brand or the violet
    /// on light glass (about 7:1), but the audit samples the bright rim and the reflections of the glass.
    static func glass(_ labels: String...) -> AuditException {
        AuditException(reason: "Liquid Glass button (text on the tint, about 7:1): the audit samples the rim of the glass") { issue, _ in
            issue.auditType == .contrast && labels.contains(issue.element?.label ?? "\u{0}")
        }
    }
}

extension AuditException {
    /// The team grid is drawn by UIKit at a fixed size, like a chart: its rows and bars cannot grow with the text.
    /// At the accessibility sizes, touch and hold shows the bar, name or day under the finger in large (Large Content
    /// Viewer, as the tab bar does); the same tasks are in the Day, Week and Month lists, which follow Dynamic Type.
    static let fixedGrid = AuditException(reason: "team grid drawn at a fixed size, with the Large Content Viewer") { issue, _ in
        issue.auditType == .dynamicType && issue.detailedDescription.contains("UILabel")
    }
}

/// The accessibility audit of Xcode (`performAccessibilityAudit`), screen by screen, collected for one report.
@MainActor
final class AccessibilityAudit {
    private let ui: Driver
    private(set) var problems: [String] = []
    private(set) var ignored: [String] = []

    init(ui: Driver) { self.ui = ui }

    /// Audits what is on the screen now (a screenshot first); issues are kept for `assertClean()`.
    func audit(_ screen: String, types: XCUIAccessibilityAuditType = .all, except exceptions: [AuditException] = []) {
        // Sheets and pushes settle first: the audit measures what is still moving
        Thread.sleep(forTimeInterval: 1)
        ui.shot("audit-" + screen)
        let app = ui.app
        let all = exceptions + AccessibilityAudit.systemExceptions
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let text = "\(screen): [\(Self.name(issue.auditType))] \(issue.compactDescription) — \(Self.describe(issue.element))"
                    + " — \(issue.detailedDescription.prefix(240))"
                if let exception = all.first(where: { $0.matches(issue, app) }) {
                    self.ignored.append(text + " (ignored: \(exception.reason))")
                } else {
                    self.problems.append(text)
                }
                return true
            }
        } catch {
            problems.append("\(screen): the audit failed: \(error)")
        }
    }

    /// One failure listing every issue of every screen; the ignored ones go to the log.
    func assertClean(file: StaticString = #filePath, line: UInt = #line) {
        if !ignored.isEmpty { print("Accessibility issues ignored:\n" + ignored.joined(separator: "\n")) }
        XCTAssertTrue(problems.isEmpty, "Accessibility issues:\n" + problems.joined(separator: "\n"), file: file, line: line)
    }

    /// Issues that are not faults of the app, on every screen. Each one says why.
    static let systemExceptions: [AuditException] = [
        AuditException(reason: "secondary label colour of the system (iOS darkens it with Increase Contrast)") { issue, _ in
            issue.auditType == .contrast && issue.compactDescription.localizedCaseInsensitiveContains("nearly")
        },
        AuditException(reason: "button of a navigation bar or toolbar, on Liquid Glass: the audit samples the rim of the glass") { issue, app in
            guard issue.auditType == .contrast, let element = issue.element, element.elementType == .button else { return false }
            return app.navigationBars.allElementsBoundByIndex.contains { $0.frame.insetBy(dx: -4, dy: -4).contains(element.frame) }
        },
        AuditException(reason: "content scrolled under the floating tab bar: the audit measures it through the glass") { issue, app in
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            let bar = app.tabBars.firstMatch
            return bar.exists && bar.frame.intersects(element.frame)
        },
        AuditException(reason: "text partly hidden by the edge of its scroll view or a bar: measured on what covers it") { issue, _ in
            guard issue.auditType == .contrast, let element = issue.element, element.exists else { return false }
            return !element.isHittable
        },
        // SwiftUI text styles follow Dynamic Type: AdaptiveUITests launches the app with the largest sizes, checks the
        // actions and clipped text there and takes screenshots. The audit, which only simulates the change, reports
        // SwiftUI text as "partially unsupported".
        AuditException(reason: "SwiftUI text style: checked at the real sizes by AdaptiveUITests") { issue, _ in
            issue.auditType == .dynamicType && issue.detailedDescription.contains("SwiftUI.AccessibilityNode")
        },
        // The same goes for "may be clipped at larger sizes" on SwiftUI text: the line limits of the app grow with
        // the text size (and rows stack), which the prediction does not see; the screenshots at the largest size
        // show the same texts whole.
        AuditException(reason: "SwiftUI text: clipping predicted, not seen at the real sizes (AdaptiveUITests screenshots)") { issue, _ in
            issue.auditType == .textClipped && issue.detailedDescription.contains("SwiftUI.AccessibilityNode")
        },
        AuditException(reason: "text of a navigation bar: one line at a fixed size like the system titles, with the Large Content Viewer") { issue, app in
            guard [.dynamicType, .textClipped].contains(issue.auditType), let element = issue.element else { return false }
            return app.navigationBars.allElementsBoundByIndex.contains { $0.frame.insetBy(dx: -4, dy: -4).contains(element.frame) }
        },
        AuditException(reason: "calendar of the system date picker") { issue, app in
            guard issue.auditType == .dynamicType, let element = issue.element else { return false }
            return app.datePickers.allElementsBoundByIndex.contains { $0.frame.contains(element.frame) }
        },
        AuditException(reason: "single-line text field of the system: its text scrolls inside it") { issue, _ in
            issue.auditType == .textClipped && [.textField, .secureTextField].contains(issue.element?.elementType)
        },
        // Seen on the screenshots of each screen: a row cut by the bottom of the screen or the tab bar, the screen
        // behind a sheet, or the weekday letters of the system calendar. The audit cannot name an element for them.
        AuditException(reason: "no element: a row cut by the edge or the tab bar, the screen behind a sheet, or the system calendar") { issue, _ in
            [.contrast, .textClipped, .elementDetection].contains(issue.auditType) && !(issue.element?.exists ?? false)
        },
        AuditException(reason: "no element: a label of the system bars or calendar (they keep their size, with the Large Content Viewer)") { issue, _ in
            issue.auditType == .dynamicType && !(issue.element?.exists ?? false)
        },
    ]

    static func name(_ type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "element detection"
        case .hitRegion: "hit region"
        case .sufficientElementDescription: "description"
        case .dynamicType: "dynamic type"
        case .textClipped: "text clipped"
        case .trait: "trait"
        default: "type \(type.rawValue)"
        }
    }

    static func describe(_ element: XCUIElement?) -> String {
        guard let element, element.exists else { return "no element" }
        return "\(element.elementType.rawValue) '\(element.label)' id '\(element.identifier)' \(element.frame.integral)"
    }
}

extension Driver {
    /// The button of a tab, in the tab bar of the iPhone or the tab bar / sidebar of the iPad.
    func tab(_ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        if inBar.exists { return inBar }
        let inSidebar = app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if inSidebar.exists { return inSidebar }
        return app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Signed in, on any width: the Planning tab is there.
    func expectMain(file: StaticString = #filePath, line: UInt = #line) {
        let planning = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Planning' AND (elementType == %d OR elementType == %d)",
                                                                             XCUIElement.ElementType.button.rawValue,
                                                                             XCUIElement.ElementType.cell.rawValue)).firstMatch
        expect(planning, timeout: 30, file: file, line: line)
    }

    /// Scrolls up until the element is whole on the screen and can be touched (a card taller than the screen, or
    /// the end of a long list with the largest text, included).
    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        var tries = 0
        while !revealed(element) && tries < 20 {
            app.swipeUp(velocity: tries < 4 ? .slow : .default)
            tries += 1
        }
        expect(element, file: file, line: line)
    }

    /// Touchable is not enough: a strip of the element at the bottom edge already is. Its end must be on the
    /// screen, and its top too unless it is taller than the screen.
    private func revealed(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let screen = app.frame, frame = element.frame
        return frame.maxY <= screen.maxY && (frame.minY >= screen.minY || frame.height > screen.height)
    }

    /// The element is on the screen and can be touched.
    func expectReachable(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        expect(element, file: file, line: line)
        let screen = app.frame
        XCTAssertTrue(element.isHittable, "\(what) cannot be touched: \(element.frame)", file: file, line: line)
        XCTAssertTrue(screen.contains(element.frame), "\(what) is outside the screen: \(element.frame) in \(screen)", file: file, line: line)
    }
}

/// The web API of the test server as one account (the administrator, or a person of the seeded company), off the
/// main actor so that teardown blocks can use it: to make the data of a test and remove it, also after a failure.
final class AccountAPI: Sendable {
    private let cookie: String
    private let session = URLSession(configuration: .ephemeral)

    private init(cookie: String) { self.cookie = cookie }

    static func signIn(_ account: TestAccount) async throws -> AccountAPI {
        var request = URLRequest(url: URL(string: TestServer.url + "/api/auth/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["identifier": account.login, "password": account.password])
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let http = response as! HTTPURLResponse
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: http.allHeaderFields as? [String: String] ?? [:], for: request.url!)
        guard http.statusCode == 200, !cookies.isEmpty else { throw TestAPIError.status(http.statusCode, "\(account.login) sign-in") }
        return AccountAPI(cookie: cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
    }

    /// The body of the answer (status 2xx), or an error with the status.
    @discardableResult
    func call(_ method: String, _ path: String, json body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: TestServer.url + path)!)
        request.httpMethod = method
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as! HTTPURLResponse).statusCode
        guard (200..<300).contains(status) else {
            throw TestAPIError.status(status, "\(method) \(path): \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        return data
    }

    /// A list of the API as dictionaries.
    func list(_ path: String) async throws -> [[String: Any]] {
        try JSONSerialization.jsonObject(with: try await call("GET", path)) as? [[String: Any]] ?? []
    }

    /// Deletes the account's conversations with the assistant that contain this text (a marker of the test).
    func deleteConversations(containing marker: String) async throws {
        for id in try await list("/api/ai-chat/conversations").compactMap({ $0["id"] as? String }) {
            let detail = String(decoding: try await call("GET", "/api/ai-chat/conversations/\(id)"), as: UTF8.self)
            if detail.contains(marker) { try await call("DELETE", "/api/ai-chat/conversations/\(id)") }
        }
    }
}

/// Test data of the accessibility tests, made through the administrator and removed by the test.
enum A11yData {
    /// What a new task of Emma today needs: project, person, status and date (the ids of this server), as JSON.
    static func taskBasics(_ api: AccountAPI, title: String, extra: [String: Any] = [:]) async throws -> Data {
        let users = try await api.list("/api/users")
        let projects = try await api.list("/api/projects")
        let statuses = try await api.list("/api/statuses")
        guard let emma = users.first(where: { $0["username"] as? String == "emma" })?["id"] as? String,
              let project = projects.first?["id"] as? String,
              let status = (statuses.first { $0["isDefault"] as? Bool == true } ?? statuses.first)?["id"] as? String
        else { throw TestAPIError.status(0, "seeded data missing") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let body: [String: Any] = ["title": title, "projectId": project, "userIds": [emma], "statusId": status,
                                   "startDate": formatter.string(from: Date())]
        return try JSONSerialization.data(withJSONObject: body.merging(extra) { $1 }, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// A task of Emma today with everything a detail can show: own title, place, times, notes, milestone.
    static func createTask(title: String) async throws -> String {
        let api = try await AccountAPI.signIn(.admin)
        let body = try await taskBasics(api, title: title, extra: [
            "isMilestone": true, "startTime": "08:00", "endTime": "10:00", "placeText": "12 Harbour Road",
            "notes": "Accessibility test notes.",
        ])
        let task = try JSONSerialization.jsonObject(with: try await api.call("POST", "/api/tasks", json: body)) as? [String: Any]
        guard let id = task?["id"] as? String else { throw TestAPIError.status(0, "task not created") }
        return id
    }

    static func deleteTask(_ id: String) async throws {
        try await AccountAPI.signIn(.admin).call("DELETE", "/api/tasks/\(id)?scope=single")
    }

    /// The message that makes the stand-in of the AI provider ask to create this task (it waits for approval).
    static func writeRequest(title: String) async throws -> String {
        "crée une tâche :: " + String(decoding: try await taskBasics(try await AccountAPI.signIn(.admin), title: title), as: UTF8.self)
    }
}
