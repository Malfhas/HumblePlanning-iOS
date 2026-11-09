import Foundation
import Synchronization
import Testing
@testable import HumbleCore

@Suite struct RealtimeClientTests {
    let transport = FakeTransport()

    func client(_ timing: RealtimeTiming = .test) -> RealtimeClient {
        RealtimeClient(transport: transport, timing: timing, random: { 0 })
    }

    @Test func connectsWithTheSessionCookie() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        #expect(socket.request.url?.absoluteString == "wss://planning.example.com/socket.io/?EIO=4&transport=websocket")
        #expect(socket.request.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=fr; __Secure-better-auth.session_token=token.signature")
        #expect(socket.request.value(forHTTPHeaderField: "X-App-Version") == "1.0.0")
        #expect(socket.request.value(forHTTPHeaderField: "User-Agent") == "HumblePlanning-iOS/1.0.0")
        #expect(socket.request.value(forHTTPHeaderField: "Accept-Language") == "fr")
        #expect(socket.request.value(forHTTPHeaderField: "Origin") == nil)
        try await socket.accept()
        #expect(try await events.next() == .connected)
        #expect(await client.isActive)
        await client.disconnect()
        #expect(try await events.next() == .disconnected(.client))
        #expect(socket.isClosed)
        #expect(await !client.isActive)
    }

    @Test func deliversTheServerEvents() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        try await socket.accept()
        #expect(try await events.next() == .connected)
        socket.push(#"42["presence:update",[]]"#)
        socket.push(#"42["task:changed",{"channel":"task:changed"}]"#)
        socket.push(.binary(Data([1, 2])))
        socket.push(#"42["session:revoked",{}]"#)
        socket.push("not a packet")
        socket.push(#"42["permissions:changed",{}]"#)
        socket.push(#"42["ai-chat:availability",{}]"#)
        socket.push(#"42["mobile:alert",{"alertId":"a1","channel":"mobile:alert"}]"#)
        #expect(try await events.next() == .taskChanged)
        #expect(try await events.next() == .sessionRevoked)
        #expect(try await events.next() == .permissionsChanged)
        #expect(try await events.next() == .assistantAvailability)
        #expect(try await events.next() == .mobileAlert(alertId: "a1"))
        await client.disconnect()
    }

    @Test func answersPingsAndStaysConnected() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        try await socket.accept(pingInterval: 150, pingTimeout: 150)
        #expect(try await events.next() == .connected)
        for _ in 0..<10 {
            socket.push("2")
            #expect(try await socket.nextSent() == .text("3"))
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(events.pending() == [])
        #expect(transport.openCount == 1)
        await client.disconnect()
    }

    @Test func sendsThePresenceHeartbeat() async throws {
        var timing = RealtimeTiming.test
        timing.heartbeatInterval = .milliseconds(40)
        let client = client(timing)
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        try await socket.accept()
        #expect(try await events.next() == .connected)
        #expect(try await socket.nextSent() == .text(#"42["presence:heartbeat"]"#))
        #expect(try await socket.nextSent() == .text(#"42["presence:heartbeat"]"#))
        await client.disconnect()
    }

    @Test func refusedSessionIsNotRetried() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        socket.push(#"0{"sid":"e","upgrades":[],"pingInterval":25000,"pingTimeout":20000}"#)
        #expect(try await socket.nextSent() == .text("40"))
        socket.push(#"44{"message":"Session expired"}"#)
        #expect(try await events.next() == .invalidSession(message: "Session expired"))
        try await Task.sleep(for: .milliseconds(150))
        #expect(transport.openCount == 1)
        #expect(socket.isClosed)
        #expect(events.pending() == [])
        #expect(await client.isActive)

        await client.reconnect()
        let second = try await transport.nextSocket()
        try await second.accept()
        #expect(try await events.next() == .connected)
        await client.disconnect()
    }

    @Test func serverDisconnectIsNotRetried() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        try await socket.accept()
        #expect(try await events.next() == .connected)
        socket.push("41")
        #expect(try await events.next() == .disconnected(.serverDisconnect))
        try await Task.sleep(for: .milliseconds(150))
        #expect(transport.openCount == 1)
        #expect(socket.isClosed)
        await client.disconnect()
        #expect(events.pending() == [])
    }

    @Test func lostConnectionIsRetried() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let first = try await transport.nextSocket()
        try await first.accept()
        #expect(try await events.next() == .connected)
        first.drop()
        #expect(try await events.next() == .disconnected(.transportClosed))
        let second = try await transport.nextSocket()
        #expect(second.request == first.request)
        try await second.accept()
        #expect(try await events.next() == .connected)
        #expect(transport.log == ["open 1", "close 1", "open 2"])
        await client.disconnect()
    }

    @Test func failedAttemptsAreRetriedWithoutEvents() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        for _ in 0..<3 { try await transport.nextSocket().drop() }
        let socket = try await transport.nextSocket()
        try await socket.accept()
        #expect(try await events.next() == .connected)
        #expect(transport.openCount == 4)
        await client.disconnect()
    }

    @Test func pingTimeoutReconnects() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let first = try await transport.nextSocket()
        try await first.accept(pingInterval: 40, pingTimeout: 40)
        #expect(try await events.next() == .connected)
        #expect(try await events.next() == .disconnected(.pingTimeout))
        #expect(first.isClosed)
        let second = try await transport.nextSocket()
        try await second.accept()
        #expect(try await events.next() == .connected)
        await client.disconnect()
    }

    @Test func connectTimeoutReconnects() async throws {
        var timing = RealtimeTiming.test
        timing.connectTimeout = .milliseconds(50)
        let client = client(timing)
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let first = try await transport.nextSocket()
        let second = try await transport.nextSocket()
        #expect(first.isClosed)
        #expect(events.pending() == [])
        try await second.accept()
        #expect(try await events.next() == .connected)
        await client.disconnect()
    }

    @Test func disconnectStopsReconnecting() async throws {
        var timing = RealtimeTiming.test
        timing.reconnectDelay = .milliseconds(200)
        timing.reconnectDelayMax = .milliseconds(200)
        let client = client(timing)
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        try await socket.accept()
        #expect(try await events.next() == .connected)
        socket.drop()
        #expect(try await events.next() == .disconnected(.transportClosed))
        await client.disconnect()
        await client.reconnect()
        try await Task.sleep(for: .milliseconds(400))
        #expect(transport.openCount == 1)
        #expect(events.pending() == [])
    }

    @Test func disconnectDoesNotWaitForAStalledSend() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let socket = try await transport.nextSocket()
        try await socket.accept()
        #expect(try await events.next() == .connected)
        socket.stallSends()
        socket.push("2")
        try await Task.sleep(for: .milliseconds(50))
        // Unstructured, so that a regression fails instead of hanging the run.
        let finished = Mutex(false)
        Task {
            await client.disconnect()
            finished.withLock { $0 = true }
        }
        for _ in 0..<100 where !finished.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(finished.withLock { $0 })
        #expect(socket.isClosed)
        #expect(try await events.next(within: .milliseconds(100)) == .disconnected(.client))
    }

    @Test func reconnectDoesNothingWhenNotWanted() async throws {
        let client = client()
        await client.reconnect()
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.openCount == 0)
        #expect(await !client.isActive)
    }

    @Test func connectClosesThePreviousSocketFirst() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        await client.connect(.test)
        let first = try await transport.nextSocket()
        try await first.accept()
        #expect(try await events.next() == .connected)

        var other = RealtimeCredentials.test
        other.cookieValue = "other.token"
        await client.connect(other)
        #expect(try await events.next() == .disconnected(.client))
        let second = try await transport.nextSocket()
        #expect(transport.log == ["open 1", "close 1", "open 2"])
        #expect(second.request.value(forHTTPHeaderField: "Cookie") == "HP_LOCALE=fr; __Secure-better-auth.session_token=other.token")
        try await second.accept()
        #expect(try await events.next() == .connected)
        await client.disconnect()
        #expect(try await events.next() == .disconnected(.client))
    }

    @Test func burstOfConnectsEndsWithOneSocket() async throws {
        let client = client()
        let events = EventRecorder(client.events())
        for value in ["a", "b", "c", "d"] {
            var credentials = RealtimeCredentials.test
            credentials.cookieValue = value
            await client.connect(credentials)
        }
        let socket = try await transport.nextSocket()
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.openCount == 1)
        #expect(socket.request.value(forHTTPHeaderField: "Cookie")?.hasSuffix("=d") == true)
        try await socket.accept()
        #expect(try await events.next() == .connected)
        await client.disconnect()
    }

    @Test func reconnectUsesFreshCredentials() async throws {
        let client = client()
        await client.connect(.test)
        let first = try await transport.nextSocket()
        var fresh = RealtimeCredentials.test
        fresh.cookieValue = "fresh.token"
        await client.reconnect(fresh)
        let second = try await transport.nextSocket()
        #expect(first.isClosed)
        #expect(second.request.value(forHTTPHeaderField: "Cookie")?.hasSuffix("=fresh.token") == true)
        await client.reconnect()
        let third = try await transport.nextSocket()
        #expect(third.request == second.request)
        await client.disconnect()
    }

    @Test func everySubscriberGetsTheEvents() async throws {
        let client = client()
        let first = EventRecorder(client.events())
        let second = EventRecorder(client.events())
        await client.connect(.test)
        try await transport.nextSocket().accept()
        #expect(try await first.next() == .connected)
        #expect(try await second.next() == .connected)
        await client.disconnect()
    }

    @Test func unusableServerURLOpensNothing() async throws {
        let client = client()
        var credentials = RealtimeCredentials.test
        credentials.serverURL = URL(string: "ftp://planning.example.com")!
        await client.connect(credentials)
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.openCount == 0)
        await client.disconnect()
    }

    @Test func releasingTheClientClosesTheSocket() async throws {
        var client: RealtimeClient? = client()
        let events = EventRecorder(client!.events())
        await client!.connect(.test)
        let socket = try await transport.nextSocket()
        try await socket.accept()
        #expect(try await events.next() == .connected)
        client = nil
        try await withTimeout {
            while !socket.isClosed { try await Task.sleep(for: .milliseconds(5)) }
        }
        await #expect(throws: QueueClosed.self) { try await events.next() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.openCount == 1)
    }
}
