import Foundation
import XCTest

/// The disposable server of the interface tests: the test server of the Android repository (tools/test-server:
/// Docker, http://localhost:3100, stand-ins for the AI provider and push), with its test administrator and the
/// data of tools/screenshots/seed.mjs. `tools/ui-tests.sh` starts it, fills it and runs the tests.
enum TestServer {
    static let environment = ProcessInfo.processInfo.environment
    static var url: String { environment["HP_SERVER"] ?? "http://localhost:3100" }
    /// Every step also saved as a PNG in this folder (`TEST_RUNNER_HP_SHOTS`).
    static var shots: URL? { environment["HP_SHOTS"].map { URL(filePath: $0, directoryHint: .isDirectory) } }

    /// The interface tests only run against the test server, when asked (`TEST_RUNNER_HP_UITESTS=1`).
    static func require() throws {
        try XCTSkipUnless(environment["HP_UITESTS"] == "1", "Needs the test server: tools/ui-tests.sh")
    }
}

/// Accounts of the test server.
struct TestAccount: Sendable {
    let login: String
    let password: String

    /// The administrator created with the test server (the password of tools/test-server, a local server only).
    static var admin: TestAccount {
        TestAccount(login: TestServer.environment["HP_ADMIN"] ?? "testadmin",
                    password: TestServer.environment["HP_ADMIN_PASSWORD"] ?? "TestAdmin2026!x")
    }

    /// A person of the seeded company (seed.mjs prints the password of its accounts: `TEST_RUNNER_HP_SEED_PASSWORD`).
    static func seeded(_ login: String) -> TestAccount {
        TestAccount(login: login, password: TestServer.environment["HP_SEED_PASSWORD"] ?? "")
    }
}

/// The REST API of the test server as its administrator, to prepare data or change a setting from a test
/// (like Rest.kt in the Android tests). Requests go straight to the server, not through the app.
@MainActor
final class TestAPI {
    private let cookie: String
    private let session = URLSession(configuration: .ephemeral)

    private init(cookie: String) { self.cookie = cookie }

    /// A web session of the administrator.
    static func admin() async throws -> TestAPI {
        var request = URLRequest(url: URL(string: TestServer.url + "/api/auth/login")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let account = TestAccount.admin
        request.httpBody = try JSONSerialization.data(withJSONObject: ["identifier": account.login, "password": account.password])
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let http = response as! HTTPURLResponse
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: http.allHeaderFields as? [String: String] ?? [:], for: request.url!)
        guard http.statusCode == 200, !cookies.isEmpty else { throw TestAPIError.status(http.statusCode, "admin sign-in") }
        return TestAPI(cookie: cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
    }

    /// The JSON answer of a request (status 2xx), or an error with the status.
    @discardableResult
    func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> Any? {
        var request = URLRequest(url: URL(string: TestServer.url + path)!)
        request.httpMethod = method
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as! HTTPURLResponse).statusCode
        guard (200..<300).contains(status) else { throw TestAPIError.status(status, "\(method) \(path): \(String(decoding: data.prefix(300), as: UTF8.self))") }
        return data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
    }

    /// A setting of Settings (`PUT /api/config`); an empty value goes back to the default.
    func setConfig(_ key: String, _ value: String) async throws {
        try await call("PUT", "/api/config", [key: value])
    }
}

enum TestAPIError: Error {
    case status(Int, String)
}
