import Foundation
import Synchronization
import Testing
@testable import HumbleCore

/// Answers requests from a table, and records them.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Answer: Sendable {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    static let answers = Mutex<[String: Answer]>([:])
    static let requests = Mutex<[URLRequest]>([])

    static func reset(_ table: [String: Answer]) {
        answers.withLock { $0 = table }
        requests.withLock { $0 = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let path = request.url?.path() ?? ""
        let answer = Self.answers.withLock { $0[path] } ?? Answer(status: 404, body: "")
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Every test answered by `StubProtocol`: its table is global, so they run one at a time.
@Suite(.serialized)
struct StubbedTests {}

extension StubbedTests {
    @Suite
    struct APIClientTests {
        let session = ServerSession(serverURL: "https://planning.example.com", cookieName: "__Secure-better-auth.session_token", cookieValue: "abc.def")

        func client(expired: (@Sendable () -> Void)? = nil, refreshed: (@Sendable (ServerSession) -> Void)? = nil) -> APIClient {
            APIClient(baseURL: "https://planning.example.com", session: session, transport: Transport(protocolClasses: [StubProtocol.self]),
                      language: { "fr" }, onSessionExpired: expired ?? {}, onSessionRefreshed: refreshed ?? { _ in })
        }

        @Test func headersAndSessionCookie() throws {
            let request = try client().request("GET", "/api/mobile/bootstrap")
            #expect(request.value(forHTTPHeaderField: "X-App-Version") == AppInfo.version)
            #expect(request.value(forHTTPHeaderField: "X-App-Platform") == "ios")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == AppInfo.userAgent)
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "fr")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=fr; __Secure-better-auth.session_token=abc.def")
            #expect(request.value(forHTTPHeaderField: "Origin") == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }

        @Test func signInCallsNeverCarryTheSession() throws {
            let request = try client().request("POST", "/api/mobile/auth/login", body: .json(Data("{}".utf8)), withSession: false)
            #expect(request.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=fr")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
        }

        @Test func otherServerGetsNoSession() throws {
            let other = APIClient(baseURL: "https://other.example.com", session: session, language: { "en" })
            #expect(try other.request("GET", "/api/profile").value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=en")
            let otherPort = APIClient(baseURL: "https://planning.example.com:8443", session: session, language: { "en" })
            #expect(try otherPort.request("GET", "/api/profile").value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=en")
        }

        @Test func plusInDatesIsEncoded() throws {
            let request = try client().request("GET", "/api/mobile/alerts", query: [URLQueryItem(name: "after", value: "2026-11-05T10:00:00+01:00")])
            #expect(request.url?.absoluteString == "https://planning.example.com/api/mobile/alerts?after=2026-11-05T10:00:00%2B01:00")
        }

        @Test func refreshedCookieIsKept() async throws {
            StubProtocol.reset(["/api/profile": .init(status: 200, body: #"{"id":"u1","name":"Turner"}"#,
                                                        headers: ["Set-Cookie": "__Secure-better-auth.session_token=new.value; Path=/; HttpOnly; Secure"])])
            let seen = Mutex<ServerSession?>(nil)
            let client = client(refreshed: { new in seen.withLock { $0 = new } })
            _ = try await client.profile()
            #expect(seen.withLock { $0 }?.cookieValue == "new.value")
            #expect(client.currentSession?.cookieValue == "new.value")
        }

        @Test func expiredSessionIsReported() async throws {
            StubProtocol.reset(["/api/profile": .init(status: 401, body: #"{"error":"Session expirée","code":"errors.sessionExpired"}"#)])
            let expired = Mutex(false)
            await #expect(throws: APIError.sessionExpired) { try await client(expired: { expired.withLock { $0 = true } }).profile() }
            #expect(expired.withLock { $0 })
        }

        @Test func infoRecognisesTheServer() async throws {
            StubProtocol.reset(["/api/mobile/info": .init(status: 200, body: #"{"service":"other"}"#)])
            await #expect(throws: APIError.notHumblePlanning) { try await client().info() }
            StubProtocol.reset(["/api/mobile/info": .init(status: 200, body: "<html>")])
            await #expect(throws: APIError.notHumblePlanning) { try await client().info() }
            StubProtocol.reset(["/api/mobile/info": .init(status: 200, body: #"{"service":"humble-planning","maintenance":true,"minimumAppVersion":null}"#)])
            let info = try await client().info()
            #expect(info.maintenance && info.loginEnabled && info.minimumAppVersion == nil)
            #expect(StubProtocol.requests.withLock { $0 }.first?.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=fr")
        }
    }

}

struct APIErrorTests {
    func failure(_ status: Int, _ body: String, path: String = "/api/tasks") -> APIError {
        APIError.failure(status: status, path: path, body: Data(body.utf8))
    }

    @Test func blockingStatuses() {
        #expect(failure(426, #"{"error":"x","code":"mobile.errors.upgradeRequired","params":{"minimumVersion":"1.2.0","storeUrl":"https://s"}}"#)
            == .upgradeRequired(minimumVersion: "1.2.0", storeURL: "https://s"))
        #expect(failure(426, "nope") == .upgradeRequired(minimumVersion: "", storeURL: ""))
        #expect(failure(423, #"{"error":"Maintenance en cours"}"#) == .maintenance("Maintenance en cours"))
        #expect(failure(403, #"{"error":"Non autorisé","code":"mobile.errors.appNotAllowed"}"#) == .appNotAllowed("Non autorisé"))
        #expect(failure(403, #"{"error":"Interdit","code":"errors.forbidden"}"#) == .server(status: 403, code: "errors.forbidden", message: "Interdit"))
    }

    @Test func bodilessAnswers() {
        #expect(failure(502, "<html>Bad gateway</html>") == .network("HTTP 502"))
        #expect(failure(500, #"{"error":"Erreur","code":"errors.internal"}"#) == .server(status: 500, code: "errors.internal", message: "Erreur"))
        #expect(failure(400, "plain") == .unexpected("plain"))
    }

    @Test func sessionExpiryOutsideSignIn() {
        let body = #"{"error":"x","code":"errors.unauthenticated"}"#
        #expect(failure(401, body) == .sessionExpired)
        #expect(failure(401, body, path: "/api/mobile/auth/2fa") == .server(status: 401, code: "errors.unauthenticated", message: "x"))
        #expect(failure(401, #"{"error":"Identifiants invalides","code":"auth.errors.invalidCredentials"}"#)
            == .server(status: 401, code: "auth.errors.invalidCredentials", message: "Identifiants invalides"))
    }

    @Test func numericParamsBecomeText() {
        #expect(failure(426, #"{"params":{"minimumVersion":2}}"#) == .upgradeRequired(minimumVersion: "2", storeURL: ""))
    }
}

struct RedirectPolicyTests {
    func request(_ url: String, cookie: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    @Test func otherHostLosesTheSessionOnly() {
        let original = request("https://planning.example.com/a", cookie: "HP_LOCALE=en; s=1")
        let next = RedirectPolicy.follow(from: original, to: request("https://cdn.example.com/b", cookie: "HP_LOCALE=en; s=1"))
        #expect(next?.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=en")
    }

    @Test func sameServerKeepsTheSession() {
        let original = request("https://planning.example.com/a", cookie: "HP_LOCALE=en; s=1")
        let next = RedirectPolicy.follow(from: original, to: request("https://planning.example.com/b", cookie: "HP_LOCALE=en; s=1"))
        #expect(next?.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=en; s=1")
    }

    @Test func schemeChangeIsNotFollowed() {
        let original = request("https://planning.example.com/a", cookie: "HP_LOCALE=en")
        #expect(RedirectPolicy.follow(from: original, to: request("http://planning.example.com/a", cookie: "HP_LOCALE=en")) == nil)
    }
}

struct EncodingTests {
    func json(_ value: some Encodable) throws -> JSONObject {
        try #require(try JSONValue.parse(JSONEncoder().encode(value)).objectValue)
    }

    @Test func taskPayloadWritesNulls() throws {
        let object = try json(TaskPayload(projectId: "p", userIds: ["u"], statusId: "s", startDate: "2026-11-05"))
        #expect(object["endDate"] == .null)
        #expect(object["startTime"] == .null)
        #expect(object["link"] == .null)
        #expect(object["title"] == "")
        #expect(object["notes"] == "")
        #expect(object["isMilestone"] == false)
        #expect(object["isLocked"] == nil)
        #expect(object["placeTextLat"] == nil && object["placeTextLng"] == nil)
    }

    @Test func taskPayloadOptionalKeys() throws {
        let object = try json(TaskPayload(projectId: "p", userIds: [], statusId: "s", startDate: "2026-11-05",
                                          clearPlaceCoordinates: true, isLocked: false))
        #expect(object["isLocked"] == false)
        #expect(object["placeTextLat"] == .null && object["placeTextLng"] == .null)
    }

    @Test func deviceUpdateIsOnlyThePushToken() throws {
        #expect(String(decoding: try JSONEncoder().encode(UpdateDeviceRequest(pushToken: nil)), as: UTF8.self) == #"{"pushToken":null}"#)
    }

    @Test func repeatRequestHasNoDayOfWeek() throws {
        let object = try json(RepeatRequest(recurType: "weekly", recurFrequency: 1, recurEndDate: "2026-12-31", recurException: "skip"))
        #expect(object.keys.sorted() == ["recurEndDate", "recurException", "recurFrequency", "recurType"])
    }

    @Test func profileWithoutColor() throws {
        let object = try json(UpdateProfileRequest(name: " Turner ", firstName: " ", phone: "06", mobile: nil, job: nil, color: nil))
        #expect(object["color"] == nil)
        #expect(object["firstName"] == .null)
        #expect(object["name"] == "Turner")
        #expect(object["phone"] == "06")
    }

    @Test func lenientDecoding() throws {
        let task = try JSONDecoder().decode(PlanningTask.self, from: Data(#"{"id":"t","startDate":null,"users":null,"isLocked":null,"extra":1}"#.utf8))
        #expect(task.startDate == "" && task.users.isEmpty && !task.isLocked)
        let user = try JSONDecoder().decode(User.self, from: Data(#"{"id":"u","name":"Turner","active":null}"#.utf8))
        #expect(user.active && user.mobilePushNotifications)
    }

    @Test func displayName() {
        #expect(User(id: "1", name: "Turner", firstName: "Liam").displayName == "Liam Turner")
        #expect(User(id: "1", name: "Liam Turner", firstName: "Liam").displayName == "Liam Turner")
        #expect(User(id: "1", name: "Turner", firstName: " ").displayName == "Turner")
        #expect(User(id: "1", name: "Turner").displayName == "Turner")
    }

    @Test func alertTaskId() {
        #expect(MobileAlert(id: "a", actionUrl: "/tasks?id=t1&x=1").taskId == "t1")
        #expect(MobileAlert(id: "a", actionUrl: "/tasks?id=").taskId == nil)
        #expect(MobileAlert(id: "a").taskId == nil)
    }

    @Test func quota() throws {
        let state = try JSONDecoder().decode(AssistantState.self, from: Data(#"{"enabled":true,"quota":{"enabled":true,"percent":42,"resetsAt":"2026-12-01T00:00:00.000Z"}}"#.utf8))
        #expect(state.quota?.percent == 42 && state.quota?.resetsAt == "2026-12-01T00:00:00.000Z" && state.quota?.blocksQuestions == false)
        #expect(try JSONDecoder().decode(AssistantState.self, from: Data(#"{"enabled":true}"#.utf8)).quota == nil)
        #expect(ChatQuota(percent: 69).level == .success)
        #expect(ChatQuota(percent: 70).level == .warning && ChatQuota(percent: 89).level == .warning)
        #expect(ChatQuota(percent: 90).level == .danger)
        #expect(ChatQuota(enabled: true, reached: true).blocksQuestions)
        #expect(!ChatQuota(enabled: true, unlimited: true, reached: true).blocksQuestions)
        #expect(!ChatQuota(enabled: false, reached: true).blocksQuestions)
    }
}

extension StubbedTests {
    @Suite
    struct ChatTurnRequestTests {
        /// The body of a turn is the one `ChatTurn` builds, `{"messages": [...]}`: wrapped once more, the server
        /// refused every question (422).
        @Test func theBodyGoesAsBuilt() async throws {
            let stream = "data: {\"type\":\"text-delta\",\"delta\":\"Hi\"}\n\ndata: [DONE]\n\n"
            StubProtocol.reset(["/api/ai-chat/conversations/c1/messages": .init(status: 200, body: stream)])
            let client = APIClient(baseURL: "https://planning.example.com",
                                   session: ServerSession(serverURL: "https://planning.example.com", cookieName: "s", cookieValue: "v"),
                                   transport: Transport(protocolClasses: [StubProtocol.self]),
                                   language: { "en" }, onSessionExpired: {}, onSessionRefreshed: { _ in })
            let body = ChatTurn.requestBody([ChatLine(id: "m1", fromUser: true, text: "Hello")])
            var lines: [String] = []
            for try await line in try await client.chatTurn("c1", body: body) { lines.append(line) }
            #expect(lines.contains("data: [DONE]"))

            let request = try #require(StubProtocol.requests.withLock { $0 }.first)
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
            let sent = try #require(request.httpBody ?? request.httpBodyStream.map(Self.read))
            #expect(try JSONValue.parse(sent) == body)
        }

        static func read(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }
}
