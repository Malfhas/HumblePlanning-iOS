import Foundation
import Testing
@testable import HumbleCore

private enum LiveServer {
    static let environment = ProcessInfo.processInfo.environment
    static let url = environment["HP_REALTIME_URL"].flatMap(URL.init(string:))
    static let cookie: (name: String, value: String)? = environment["HP_REALTIME_COOKIE"].flatMap { text in
        guard let separator = text.firstIndex(of: "=") else { return nil }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }
}

/// Against a real server, only when `HP_REALTIME_URL` is set (the server's base URL). With
/// `HP_REALTIME_COOKIE=<name>=<value>` (a live session cookie), also checks an accepted session.
@Suite(.enabled(if: LiveServer.url != nil, "HP_REALTIME_URL is not set"), .serialized)
struct RealtimeIntegrationTests {
    func credentials(name: String, value: String) throws -> RealtimeCredentials {
        RealtimeCredentials(serverURL: try #require(LiveServer.url), cookieName: name, cookieValue: value, language: "en")
    }

    @Test func refusesAnUnknownSession() async throws {
        let client = RealtimeClient()
        let events = EventRecorder(client.events())
        await client.connect(try credentials(name: "better-auth.session_token", value: "unknown-token.signature"))
        #expect(try await events.next(within: .seconds(20)) == .invalidSession(message: "Invalid session"))
        await client.disconnect()
    }

    @Test func refusesAMissingSession() async throws {
        let client = RealtimeClient()
        let events = EventRecorder(client.events())
        await client.connect(try credentials(name: "", value: ""))
        #expect(try await events.next(within: .seconds(20)) == .invalidSession(message: "Not authenticated"))
        await client.disconnect()
    }

    @Test(.enabled(if: LiveServer.cookie != nil, "HP_REALTIME_COOKIE is not set"))
    func acceptsALiveSession() async throws {
        let cookie = try #require(LiveServer.cookie)
        let client = RealtimeClient(timing: RealtimeTiming(heartbeatInterval: .seconds(1)))
        let events = EventRecorder(client.events())
        await client.connect(try credentials(name: cookie.name, value: cookie.value))
        #expect(try await events.next(within: .seconds(20)) == .connected)
        try await Task.sleep(for: .seconds(3))
        #expect(!events.pending().contains { if case .disconnected = $0 { true } else { false } })
        await client.disconnect()
        #expect(try await events.next() == .disconnected(.client))
    }
}
