import Foundation
import Synchronization
@testable import HumbleCore

struct QueueClosed: Error {}
struct TimedOut: Error {}

/// An unbounded queue with one consumer at a time; `next()` throws once closed and drained, or when cancelled.
final class AsyncQueue<Element: Sendable>: Sendable {
    private struct State {
        var items: [Element] = []
        var waiter: CheckedContinuation<Element, any Error>?
        var closed = false
    }

    private let state = Mutex(State())

    func push(_ element: Element) {
        let waiter = state.withLock { state -> CheckedContinuation<Element, any Error>? in
            guard !state.closed else { return nil }
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.items.append(element)
            return nil
        }
        waiter?.resume(returning: element)
    }

    func close() {
        let waiter = state.withLock { state in
            state.closed = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(throwing: QueueClosed())
    }

    func next() async throws -> Element {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Element, any Error>) in
                let immediate = state.withLock { state -> Result<Element, any Error>? in
                    if !state.items.isEmpty { return .success(state.items.removeFirst()) }
                    if state.closed { return .failure(QueueClosed()) }
                    if Task.isCancelled { return .failure(CancellationError()) }
                    state.waiter = continuation
                    return nil
                }
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            let waiter = state.withLock { state in
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    /// The elements already queued.
    func drain() -> [Element] {
        state.withLock { state in
            defer { state.items.removeAll() }
            return state.items
        }
    }
}

func withTimeout<T: Sendable>(_ limit: Duration = .seconds(5), _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw TimedOut()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

/// The server side of one fake WebSocket.
final class FakeSocket: RealtimeSocket {
    let index: Int
    let request: URLRequest
    private let inbound = AsyncQueue<RealtimeFrame>()
    private let outbound = AsyncQueue<RealtimeFrame>()
    private let closed = Mutex(false)
    private let stalled = Mutex(false)
    private let closeWaiters = Mutex([CheckedContinuation<Void, Never>]())
    private let record: @Sendable (String) -> Void

    init(index: Int, request: URLRequest, record: @escaping @Sendable (String) -> Void) {
        self.index = index
        self.request = request
        self.record = record
    }

    var isClosed: Bool { closed.withLock { $0 } }

    // MARK: RealtimeSocket (the client side)

    func send(_ frame: RealtimeFrame) async throws {
        guard !isClosed else { throw QueueClosed() }
        if stalled.withLock({ $0 }) {
            await waitUntilClosed()
            throw QueueClosed()
        }
        outbound.push(frame)
    }

    func receive() async throws -> RealtimeFrame {
        try await inbound.next()
    }

    func close() {
        let first = closed.withLock { closed in
            defer { closed = true }
            return !closed
        }
        guard first else { return }
        record("close \(index)")
        inbound.close()
        outbound.close()
        for waiter in closeWaiters.withLock({ waiters in defer { waiters.removeAll() }; return waiters }) { waiter.resume() }
    }

    // MARK: Server side

    func push(_ text: String) { inbound.push(.text(text)) }
    func push(_ frame: RealtimeFrame) { inbound.push(frame) }

    /// The connection breaks: the client's pending `receive()` fails.
    func drop() { inbound.close() }

    /// From now on, `send` hangs until the socket is closed, ignoring cancellation.
    func stallSends() { stalled.withLock { $0 = true } }

    private func waitUntilClosed() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = closeWaiters.withLock { waiters in
                guard !isClosed else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    /// The next frame the client sent.
    func nextSent(within limit: Duration = .seconds(5)) async throws -> RealtimeFrame {
        try await withTimeout(limit) { try await self.outbound.next() }
    }

    /// Plays the server side of the handshake up to the namespace connection.
    func accept(pingInterval: Int = 25_000, pingTimeout: Int = 20_000) async throws {
        push(#"0{"sid":"e\#(index)","upgrades":[],"pingInterval":\#(pingInterval),"pingTimeout":\#(pingTimeout),"maxPayload":1000000}"#)
        guard try await nextSent() == .text("40") else { throw QueueClosed() }
        push(#"40{"sid":"s\#(index)"}"#)
    }
}

final class FakeTransport: RealtimeTransport {
    private let sockets = AsyncQueue<FakeSocket>()
    private let state = Mutex((count: 0, log: [String]()))

    func open(_ request: URLRequest) -> any RealtimeSocket {
        let index = state.withLock { state in
            state.count += 1
            state.log.append("open \(state.count)")
            return state.count
        }
        let socket = FakeSocket(index: index, request: request) { [weak self] line in
            self?.state.withLock { $0.log.append(line) }
        }
        sockets.push(socket)
        return socket
    }

    var openCount: Int { state.withLock { $0.count } }
    var log: [String] { state.withLock { $0.log } }

    func nextSocket(within limit: Duration = .seconds(5)) async throws -> FakeSocket {
        try await withTimeout(limit) { try await self.sockets.next() }
    }
}

/// Collects the events of a client.
final class EventRecorder: Sendable {
    private let queue = AsyncQueue<RealtimeEvent>()
    private let task: Task<Void, Never>

    init(_ events: AsyncStream<RealtimeEvent>) {
        let queue = queue
        task = Task {
            for await event in events { queue.push(event) }
            queue.close()
        }
    }

    deinit { task.cancel() }

    func next(within limit: Duration = .seconds(5)) async throws -> RealtimeEvent {
        try await withTimeout(limit) { try await self.queue.next() }
    }

    /// The events received so far and not read yet.
    func pending() -> [RealtimeEvent] { queue.drain() }
}

extension RealtimeTiming {
    /// Fast reconnections, no randomization, nothing else due during a test.
    static let test = RealtimeTiming(
        connectTimeout: .seconds(30),
        heartbeatInterval: .seconds(300),
        reconnectDelay: .milliseconds(5),
        reconnectDelayMax: .milliseconds(20),
        randomizationFactor: 0
    )
}

extension RealtimeCredentials {
    static let test = RealtimeCredentials(
        serverURL: URL(string: "https://planning.example.com")!,
        cookieName: "__Secure-better-auth.session_token",
        cookieValue: "token.signature",
        language: "fr",
        appVersion: "1.0.0",
        userAgent: "HumblePlanning-iOS/1.0.0"
    )
}
