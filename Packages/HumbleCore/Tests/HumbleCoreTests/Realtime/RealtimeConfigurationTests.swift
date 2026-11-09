import Foundation
import Testing
@testable import HumbleCore

@Suite struct RealtimeEventMappingTests {
    @Test(arguments: [
        ("task:changed", RealtimeEvent.taskChanged),
        ("session:revoked", .sessionRevoked),
        ("permissions:changed", .permissionsChanged),
        ("ai-chat:availability", .assistantAvailability),
    ])
    func mapsServerEvents(_ name: String, _ expected: RealtimeEvent) {
        #expect(RealtimeEvent(serverEvent: name, arguments: [["channel": .string(name)]]) == expected)
        #expect(RealtimeEvent(serverEvent: name, arguments: []) == expected)
    }

    @Test func readsTheAlertID() {
        #expect(RealtimeEvent(serverEvent: "mobile:alert", arguments: [["alertId": "a1", "channel": "mobile:alert"]]) == .mobileAlert(alertId: "a1"))
        #expect(RealtimeEvent(serverEvent: "mobile:alert", arguments: [["alertId": 42]]) == .mobileAlert(alertId: "42"))
        #expect(RealtimeEvent(serverEvent: "mobile:alert", arguments: [["alertId": nil]]) == .mobileAlert(alertId: nil))
        #expect(RealtimeEvent(serverEvent: "mobile:alert", arguments: ["a1"]) == .mobileAlert(alertId: nil))
        #expect(RealtimeEvent(serverEvent: "mobile:alert", arguments: []) == .mobileAlert(alertId: nil))
    }

    @Test(arguments: ["presence:update", "presence:heartbeat", "connect", "Task:Changed", ""])
    func ignoresOtherEvents(_ name: String) {
        #expect(RealtimeEvent(serverEvent: name, arguments: []) == nil)
    }

    @Test(arguments: ["Not authenticated", "Invalid session", "Session expired", "User not found", "Authentication error"])
    func sessionRefusalsAreInvalidSessions(_ message: String) {
        #expect(RealtimeEvent(refusal: message) == .invalidSession(message: message))
    }

    @Test(arguments: ["", "invalid session", "Too many connections"])
    func otherRefusalsAreReportedAsSuch(_ message: String) {
        #expect(RealtimeEvent(refusal: message) == .refused(message: message))
    }
}

@Suite struct RealtimeEndpointTests {
    @Test(arguments: [
        ("https://planning.example.com", "wss://planning.example.com/socket.io/?EIO=4&transport=websocket"),
        ("HTTPS://planning.example.com/", "wss://planning.example.com/socket.io/?EIO=4&transport=websocket"),
        ("https://planning.example.com:8443", "wss://planning.example.com:8443/socket.io/?EIO=4&transport=websocket"),
        ("https://example.com/planning", "wss://example.com/socket.io/?EIO=4&transport=websocket"),
        ("https://example.com/planning/?a=1#top", "wss://example.com/socket.io/?EIO=4&transport=websocket"),
        ("https://user:secret@example.com", "wss://example.com/socket.io/?EIO=4&transport=websocket"),
        ("http://localhost:3001", "ws://localhost:3001/socket.io/?EIO=4&transport=websocket"),
        ("http://10.0.2.2", "ws://10.0.2.2/socket.io/?EIO=4&transport=websocket"),
        ("https://[::1]:8443", "wss://[::1]:8443/socket.io/?EIO=4&transport=websocket"),
    ])
    func buildsTheWebSocketURL(_ server: String, _ expected: String) throws {
        let url = try #require(URL(string: server))
        #expect(RealtimeEndpoint.url(for: url)?.absoluteString == expected)
    }

    @Test(arguments: ["ftp://example.com", "wss://example.com", "file:///tmp/x", "example.com"])
    func refusesOtherSchemes(_ server: String) throws {
        let url = try #require(URL(string: server))
        #expect(RealtimeEndpoint.url(for: url) == nil)
    }

    @Test func sendsTheHeadersOfTheApp() throws {
        let credentials = RealtimeCredentials(
            serverURL: URL(string: "https://planning.example.com")!,
            cookieName: "__Secure-better-auth.session_token",
            cookieValue: "abc.def%2B",
            language: "fr",
            appVersion: "1.2.3",
            userAgent: "HumblePlanning-iOS/1.2.3"
        )
        let request = try #require(RealtimeEndpoint.request(for: credentials))
        #expect(request.url?.absoluteString == "wss://planning.example.com/socket.io/?EIO=4&transport=websocket")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=fr; __Secure-better-auth.session_token=abc.def%2B")
        #expect(request.value(forHTTPHeaderField: "X-App-Version") == "1.2.3")
        #expect(request.value(forHTTPHeaderField: "X-App-Platform") == "ios")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "HumblePlanning-iOS/1.2.3")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "fr")
        #expect(request.value(forHTTPHeaderField: "Origin") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpShouldHandleCookies == false)
        #expect(Set(request.allHTTPHeaderFields?.keys.map { $0.lowercased() } ?? []) == ["cookie", "x-app-version", "x-app-platform", "user-agent", "accept-language"])
    }

    @Test func defaultsToTheIdentityOfTheApp() throws {
        let credentials = RealtimeCredentials(serverURL: URL(string: "https://x.example")!, cookieName: "n", cookieValue: "v", language: "en")
        let request = try #require(RealtimeEndpoint.request(for: credentials))
        #expect(request.value(forHTTPHeaderField: "X-App-Version") == AppInfo.version)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == AppInfo.userAgent)
    }

    @Test func sendsOnlyTheLocaleWithoutSessionCookie() throws {
        let credentials = RealtimeCredentials(serverURL: URL(string: "https://x.example")!, cookieName: "", cookieValue: "", language: "de")
        #expect(RealtimeEndpoint.request(for: credentials)?.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=de")
    }

    @Test func hasNoRequestForAnUnusableServer() {
        let credentials = RealtimeCredentials(serverURL: URL(string: "ftp://x.example")!, cookieName: "n", cookieValue: "v", language: "en")
        #expect(RealtimeEndpoint.request(for: credentials) == nil)
    }
}

@Suite struct RealtimeBackoffTests {
    let timing = RealtimeTiming()

    @Test func doublesUpToTheMaximumWithoutRandomization() {
        var timing = timing
        timing.randomizationFactor = 0
        let delays = (0..<8).map { timing.reconnectDelay(attempt: $0, random: 0.73) }
        #expect(delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(10), .seconds(10), .seconds(10), .seconds(10)])
    }

    /// The values of the Socket.IO clients' `Backoff` (`ms ± floor(rand × jitter × ms)`, sign from `floor(rand × 10)`).
    @Test(arguments: [
        (0, 0.0, 1000.0),
        (0, 0.45, 775.0),
        (0, 0.5, 1250.0),
        (0, 0.99, 1495.0),
        (1, 0.3, 2300.0),
        (1, 0.15, 2150.0),
        (2, 0.2, 3600.0),
        (3, 0.95, 10000.0),
        (3, 0.05, 7800.0),
        (4, 0.0, 10000.0),
        (4, 0.4, 10000.0),
    ])
    func randomizesLikeTheSocketIOClients(_ attempt: Int, _ random: Double, _ milliseconds: Double) {
        #expect(timing.reconnectDelay(attempt: attempt, random: random) == .milliseconds(milliseconds))
    }

    @Test func staysWithinHalfAndTheMaximum() {
        for attempt in 0..<12 {
            let nominal = min(1000 * pow(2, Double(attempt)), 10_000)
            for step in 0..<100 {
                let delay = timing.reconnectDelay(attempt: attempt, random: Double(step) / 100).milliseconds
                #expect(delay >= nominal / 2 && delay <= 10_000)
            }
        }
    }

    @Test func survivesHugeAndNegativeAttempts() {
        #expect(timing.reconnectDelay(attempt: .max, random: 0) == .seconds(10))
        #expect(timing.reconnectDelay(attempt: 5000, random: 0.999) == .seconds(10))
        #expect(timing.reconnectDelay(attempt: -3, random: 0) == .seconds(1))
    }
}
