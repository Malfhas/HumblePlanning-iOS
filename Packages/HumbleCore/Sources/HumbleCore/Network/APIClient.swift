import Foundation
import Synchronization

/// The REST client of one server. Every request carries the app version and the language; the
/// session cookie goes only to its own server, never with the sign-in calls, and is refreshed when
/// the server extends it.
public final class APIClient: Sendable {
    public let baseURL: String
    private let session: Mutex<ServerSession?>
    private let language: @Sendable () -> String
    private let onSessionExpired: @Sendable () -> Void
    private let onSessionRefreshed: @Sendable (ServerSession) -> Void
    private let transport: Transport

    public init(baseURL: String, session: ServerSession?, transport: Transport = .shared,
                language: @escaping @Sendable () -> String,
                onSessionExpired: @escaping @Sendable () -> Void = {},
                onSessionRefreshed: @escaping @Sendable (ServerSession) -> Void = { _ in }) {
        self.baseURL = baseURL
        self.session = Mutex(session)
        self.transport = transport
        self.language = language
        self.onSessionExpired = onSessionExpired
        self.onSessionRefreshed = onSessionRefreshed
    }

    public var currentSession: ServerSession? { session.withLock { $0 } }

    // MARK: Requests

    enum Body {
        case none
        case json(Data)
        case empty
    }

    func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Body = .none, withSession: Bool = true) throws -> URLRequest {
        #if DEBUG
        // Every call builds its request here: none leaves while the network is simulated off
        if Transport.simulatesOffline { throw APIError.network("simulated offline") }
        #endif
        guard var components = URLComponents(string: baseURL + path) else { throw APIError.unexpected("bad url") }
        if !query.isEmpty { components.queryItems = query }
        // `+` in an ISO date-time must not read as a space
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw APIError.unexpected("bad url") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let language = language()
        request.setValue(AppInfo.version, forHTTPHeaderField: "X-App-Version")
        // The server answers as to Android without it (store page, push)
        request.setValue(AppInfo.platform, forHTTPHeaderField: "X-App-Platform")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(language, forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var cookies = ["HP_LOCALE=\(language)"]
        if withSession, let session = currentSession, session.belongs(to: url) { cookies.append(session.cookie) }
        request.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        switch body {
        case .none: break
        case .empty: request.httpBody = Data()
        case .json(let data):
            request.httpBody = data
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func json(_ value: some Encodable) throws -> Body {
        do { return .json(try JSONEncoder().encode(value)) } catch { throw APIError.unexpected("encoding") }
    }

    /// Runs a request and gives the body of a 2xx answer; any other answer is an `APIError`.
    func data(_ request: URLRequest, on session: URLSession? = nil) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (session ?? transport.api).data(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }
        return try check(response, data: data, request: request)
    }

    func check(_ response: URLResponse, data: Data, request: URLRequest) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw APIError.unexpected("no HTTP response") }
        refreshSession(from: http, request: request)
        guard (200..<300).contains(http.statusCode) else {
            let failure = APIError.failure(status: http.statusCode, path: request.url?.path() ?? "", body: data)
            if failure == .sessionExpired { onSessionExpired() }
            throw failure
        }
        return data
    }

    static func mapTransportError(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        if let urlError = error as? URLError, urlError.code == .cancelled { return CancellationError() }
        return APIError.network(error.localizedDescription)
    }

    func decode<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let body = try await data(request)
        do {
            return try JSONDecoder().decode(T.self, from: body)
        } catch {
            throw APIError.unexpected(String(decoding: body.prefix(300), as: UTF8.self))
        }
    }

    /// For answers that are read and dropped: they must still be JSON.
    func send(_ request: URLRequest) async throws {
        let body = try await data(request)
        guard (try? JSONValue.parse(body)) != nil else { throw APIError.unexpected(String(decoding: body.prefix(300), as: UTF8.self)) }
    }

    /// Better Auth re-issues the cookie when it extends the session.
    private func refreshSession(from response: HTTPURLResponse, request: URLRequest) {
        guard let url = request.url, let current = currentSession,
              request.value(forHTTPHeaderField: "Cookie")?.contains(current.cookie) == true else { return }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let key = field.key as? String, let value = field.value as? String { result[key] = value }
        }
        guard let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).first(where: { $0.name == current.cookieName }),
              !cookie.value.isEmpty, cookie.value != current.cookieValue else { return }
        let updated = ServerSession(serverURL: current.serverURL, cookieName: current.cookieName, cookieValue: cookie.value)
        session.withLock { $0 = updated }
        onSessionRefreshed(updated)
    }
}

// MARK: - Routes

extension APIClient {
    // Sign-in (never with a session)

    /// Also checks that the address is a Humble Planning server.
    public func info() async throws -> MobileInfo {
        do {
            let info = try await decode(MobileInfo.self, request("GET", "/api/mobile/info", withSession: false))
            guard info.service == "humble-planning" else { throw APIError.notHumblePlanning }
            return info
        } catch let error as APIError {
            switch error {
            case .unexpected: throw APIError.notHumblePlanning
            case .server(404, _, _): throw APIError.notHumblePlanning
            default: throw error
            }
        }
    }

    public func login(identifier: String, password: String, device: DeviceInfo) async throws -> MobileLoginResponse {
        let body = MobileLoginRequest(identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines), password: password, device: device)
        return try await decode(MobileLoginResponse.self, request("POST", "/api/mobile/auth/login", body: Self.json(body), withSession: false))
    }

    public func loginTwoFactor(pendingToken: String, code: String, isBackupCode: Bool, device: DeviceInfo) async throws -> MobileLoginResponse {
        let body = MobileTwoFactorRequest(pendingToken: pendingToken, code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                                          isBackupCode: isBackupCode, device: device)
        return try await decode(MobileLoginResponse.self, request("POST", "/api/mobile/auth/2fa", body: Self.json(body), withSession: false))
    }

    public func loginPairing(code: String, device: DeviceInfo) async throws -> MobileLoginResponse {
        let body = MobilePairingRequest(code: code, device: device)
        return try await decode(MobileLoginResponse.self, request("POST", "/api/mobile/auth/pairing", body: Self.json(body), withSession: false))
    }

    public func logout() async throws {
        try await send(request("POST", "/api/mobile/auth/logout", body: .empty))
    }

    public func changeRequiredPassword(_ password: String) async throws {
        try await send(request("POST", "/api/auth/change-password", body: Self.json(["password": password])))
    }

    // Second factor

    public func enableTwoFactor(password: String) async throws -> TwoFactorSetup {
        try await decode(TwoFactorSetup.self, request("POST", "/api/profile/2fa/enable", body: Self.json(["password": password])))
    }

    public func verifyTwoFactor(code: String) async throws -> BackupCodes {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await decode(BackupCodes.self, request("POST", "/api/profile/2fa/verify", body: Self.json(["code": code])))
    }

    public func disableTwoFactor(password: String) async throws {
        try await send(request("POST", "/api/profile/2fa/disable", body: Self.json(["password": password])))
    }

    // Data

    public func bootstrap() async throws -> Bootstrap {
        try await decode(Bootstrap.self, request("GET", "/api/mobile/bootstrap"))
    }

    public func syncTasks(start: String, end: String, since: String?) async throws -> TaskSync {
        var query = [URLQueryItem(name: "startDate", value: start), URLQueryItem(name: "endDate", value: end)]
        if let since { query.append(URLQueryItem(name: "since", value: since)) }
        return try await decode(TaskSync.self, request("GET", "/api/mobile/tasks/sync", query: query))
    }

    public func task(_ id: String) async throws -> PlanningTask {
        try await decode(PlanningTask.self, request("GET", "/api/tasks/\(Self.segment(id))"))
    }

    public func createTask(_ payload: TaskPayload) async throws -> PlanningTask {
        try await decode(PlanningTask.self, request("POST", "/api/tasks", body: Self.json(payload)))
    }

    public func updateTask(_ id: String, _ payload: TaskPayload, applyToAll: Bool) async throws -> PlanningTask {
        let query = applyToAll ? [URLQueryItem(name: "applyToAll", value: "true")] : []
        return try await decode(PlanningTask.self, request("PUT", "/api/tasks/\(Self.segment(id))", query: query, body: Self.json(payload)))
    }

    public func deleteTask(_ id: String, scope: DeleteScope) async throws {
        try await send(request("DELETE", "/api/tasks/\(Self.segment(id))", query: [URLQueryItem(name: "scope", value: scope.rawValue)]))
    }

    public func removeUser(_ userId: String, from taskId: String) async throws {
        try await send(request("DELETE", "/api/tasks/\(Self.segment(taskId))/users/\(Self.segment(userId))",
                               query: [URLQueryItem(name: "scope", value: DeleteScope.single.rawValue)]))
    }

    public func repeatTask(_ id: String, _ rule: RepeatRequest) async throws {
        try await send(request("POST", "/api/tasks/\(Self.segment(id))/repeat", body: Self.json(rule)))
    }

    /// Streams the file from disk: it is never held in memory.
    public func uploadFile(taskId: String, file: URL, name: String, contentType: String) async throws {
        var request = try request("POST", "/api/tasks/\(Self.segment(taskId))/files")
        let boundary = "HumblePlanning-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try MultipartFile.write(file: file, field: "file", name: name, contentType: contentType, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: body) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.api.upload(for: request, fromFile: body)
        } catch {
            throw Self.mapTransportError(error)
        }
        _ = try check(response, data: data, request: request)
    }

    public func deleteFile(taskId: String, fileId: String) async throws {
        try await send(request("DELETE", "/api/tasks/\(Self.segment(taskId))/files", query: [URLQueryItem(name: "fileId", value: fileId)]))
    }

    /// Downloads an attachment to `destination` (replaced).
    public func downloadFile(taskId: String, name: String, to destination: URL) async throws {
        let request = try request("GET", "/api/files/tasks/\(Self.segment(taskId))/\(Self.segment(name))")
        let location: URL
        let response: URLResponse
        do {
            (location, response) = try await transport.api.download(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = (try? Data(contentsOf: location)) ?? Data()
            _ = try check(response, data: body, request: request)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: location, to: destination)
    }

    /// An image of the server (avatars), with the session.
    public func image(at url: URL) async throws -> Data {
        guard let session = currentSession, session.belongs(to: url) else { throw APIError.unexpected("other server") }
        var request = try request("GET", "")
        request.url = url
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return try await data(request)
    }

    // Alerts and devices

    /// Without `after`: the latest alerts (history).
    public func alerts(after: String?) async throws -> AlertsPage {
        let query = after.map { [URLQueryItem(name: "after", value: $0)] } ?? []
        return try await decode(AlertsPage.self, request("GET", "/api/mobile/alerts", query: query))
    }

    public func updateDevice(pushToken: String?) async throws {
        try await send(request("PUT", "/api/mobile/devices/current", body: Self.json(UpdateDeviceRequest(pushToken: pushToken))))
    }

    public func devices() async throws -> [Device] {
        try await decode([Device].self, request("GET", "/api/mobile/devices"))
    }

    public func deleteDevice(_ id: String) async throws {
        try await send(request("DELETE", "/api/mobile/devices/\(Self.segment(id))"))
    }

    /// Number of the user's devices reached by push (missing = delivered).
    public func pushTest() async throws -> Int? {
        try await decode(PushTestResult.self, request("POST", "/api/mobile/devices/current/push-test", body: .empty)).delivered
    }

    // Profile

    public func profile() async throws -> User {
        try await decode(User.self, request("GET", "/api/profile"))
    }

    public func updateProfile(_ profile: UpdateProfileRequest) async throws -> User {
        try await decode(User.self, request("PUT", "/api/profile", body: Self.json(profile)))
    }

    public func changePassword(current: String, new: String) async throws {
        try await send(request("PUT", "/api/profile/password", body: Self.json(["currentPassword": current, "newPassword": new])))
    }

    public func setPushPreference(_ enabled: Bool) async throws {
        try await send(request("PUT", "/api/profile/preferences", body: Self.json(["mobilePushNotifications": enabled])))
    }

    /// `auto` follows the browser on the web; the app sends its own language.
    public func setLocale(_ preference: String) async throws {
        try await send(request("POST", "/api/locale", body: Self.json(["preference": preference.isEmpty ? "auto" : preference])))
    }

    // Assistant

    public func assistantQuota() async throws -> ChatQuota? {
        try await decode(AssistantState.self, request("GET", "/api/ai-chat/access")).quota
    }

    public func conversations() async throws -> [Conversation] {
        try await decode([Conversation].self, request("GET", "/api/ai-chat/conversations"))
    }

    public func conversation(_ id: String) async throws -> ConversationDetail {
        try await decode(ConversationDetail.self, request("GET", "/api/ai-chat/conversations/\(Self.segment(id))"))
    }

    public func createConversation(title: String) async throws -> Conversation {
        try await decode(Conversation.self, request("POST", "/api/ai-chat/conversations",
                                                     body: Self.json(NewConversationRequest(title: title, projectId: nil))))
    }

    public func renameConversation(_ id: String, title: String) async throws -> Conversation {
        try await decode(Conversation.self, request("PATCH", "/api/ai-chat/conversations/\(Self.segment(id))", body: Self.json(["title": title])))
    }

    public func deleteConversation(_ id: String) async throws {
        try await send(request("DELETE", "/api/ai-chat/conversations/\(Self.segment(id))"))
    }

    public func stopConversation(_ id: String) async throws {
        _ = try await data(request("POST", "/api/ai-chat/conversations/\(Self.segment(id))/stop", body: .empty))
    }

    /// The lines of the answer stream (server-sent events). A refusal before the stream starts is an `APIError`.
    /// `body` is sent as is: ``ChatTurn/requestBody(_:)``.
    public func chatTurn(_ conversationId: String, body: JSONValue) async throws -> AsyncThrowingStream<String, any Error> {
        var request = try request("POST", "/api/ai-chat/conversations/\(Self.segment(conversationId))/messages", body: .json(body.serializedData))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await transport.stream.bytes(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            _ = try check(response, data: body, request: request)
        }
        if let http = response as? HTTPURLResponse { refreshSession(from: http, request: request) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.sseLines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapTransportError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Helpers

    /// One path segment, percent-encoded.
    static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }
}

/// A multipart/form-data body with one file, written to a temporary file by chunks.
enum MultipartFile {
    static func write(file: URL, field: String, name: String, contentType: String, boundary: String) throws -> URL {
        let output = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: output.path(), contents: nil)
        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }
        let quoted = name.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        try writer.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(quoted)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
            try writer.write(contentsOf: chunk)
        }
        try writer.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return output
    }
}
