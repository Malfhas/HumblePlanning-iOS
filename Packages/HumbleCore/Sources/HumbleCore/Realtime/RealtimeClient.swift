import Foundation
import Synchronization

/// The Socket.IO connection of the app in the foreground (Socket.IO v5 over Engine.IO v4, WebSocket
/// only). Connect it when the app comes to the foreground or signs in, disconnect it in the background
/// and at sign-out: an idle socket would show the user as present, and push takes over there.
///
/// Lost connections are retried without limit, after 1 s doubling up to 10 s (randomized by half);
/// a refused handshake or a disconnection by the server is not retried.
public actor RealtimeClient {
    private let hub = RealtimeEventHub()
    private let runner: RealtimeRunner
    private var credentials: RealtimeCredentials?
    /// The latest connection loop, kept once cancelled so that the next one waits for its end.
    private var loop: Task<Void, Never>?

    /// `session` is an ephemeral one without cookie storage when nil.
    public init(session: URLSession? = nil, timing: RealtimeTiming = RealtimeTiming()) {
        self.init(transport: URLSessionRealtimeTransport(session: session), timing: timing)
    }

    init(transport: any RealtimeTransport, timing: RealtimeTiming, random: @escaping @Sendable () -> Double = { .random(in: 0..<1) }) {
        runner = RealtimeRunner(transport: transport, hub: hub, timing: timing, random: random)
    }

    deinit {
        loop?.cancel()
        hub.finish()
    }

    /// A new stream of the events, for as many subscribers as needed; the oldest events beyond `limit` are dropped.
    public nonisolated func events(bufferingNewest limit: Int = 32) -> AsyncStream<RealtimeEvent> {
        hub.stream(bufferingNewest: limit)
    }

    /// A connection is wanted: between `connect` and `disconnect`, even while refused or reconnecting.
    public var isActive: Bool { credentials != nil }

    /// Closes the current connection, then connects with these credentials. Does nothing but close
    /// when the server URL is neither `https` nor `http`.
    public func connect(_ credentials: RealtimeCredentials) {
        self.credentials = credentials
        let previous = loop
        previous?.cancel()
        let runner = runner
        let request = RealtimeEndpoint.request(for: credentials)
        // Detached: the loop never holds the client, which stops it when released.
        loop = Task.detached {
            await previous?.value
            guard let request, !Task.isCancelled else { return }
            await runner.run(request)
        }
    }

    /// Connects again at once if a connection is wanted (the network changed: the old one could take a
    /// minute to notice), with fresh credentials when given; does nothing otherwise.
    public func reconnect(_ credentials: RealtimeCredentials? = nil) {
        guard let current = self.credentials else { return }
        connect(credentials ?? current)
    }

    /// Stops everything, no reconnection; returns once the WebSocket is closed.
    public func disconnect() async {
        credentials = nil
        let current = loop
        current?.cancel()
        await current?.value
    }
}

/// The reconnection loop of one `connect`.
struct RealtimeRunner: Sendable {
    let transport: any RealtimeTransport
    let hub: RealtimeEventHub
    let timing: RealtimeTiming
    let random: @Sendable () -> Double

    func run(_ request: URLRequest) async {
        var attempt = 0
        while !Task.isCancelled {
            switch await connectOnce(request) {
            case .stop:
                return
            case .retry(let afterConnection):
                if afterConnection { attempt = 0 }
                let delay = timing.reconnectDelay(attempt: attempt, random: random())
                attempt += 1
                do { try await Task.sleep(for: delay) } catch { return }
            }
        }
    }

    private enum Input: Sendable {
        case frame(RealtimeFrame)
        case closed
        case tick
    }

    private func connectOnce(_ request: URLRequest) async -> RealtimeConnection.Outcome {
        let socket = transport.open(request)
        let (inputs, feed) = AsyncStream.makeStream(of: Input.self)
        let receiver = Task {
            do {
                while !Task.isCancelled { feed.yield(.frame(try await socket.receive())) }
            } catch {
                feed.yield(.closed)
            }
        }
        defer {
            receiver.cancel()
            socket.close()
            feed.finish()
        }
        let clock = ContinuousClock()
        let start = clock.now

        func arm(_ deadline: Duration?) -> Task<Void, Never>? {
            guard let deadline else { return nil }
            return Task {
                do {
                    try await clock.sleep(until: start.advanced(by: deadline))
                    feed.yield(.tick)
                } catch {}
            }
        }

        // Closing on cancellation makes a pending send fail at once.
        return await withTaskCancellationHandler {
            var connection = RealtimeConnection(timing: timing, now: .zero)
            var timer = arm(connection.nextDeadline)
            defer { timer?.cancel() }
            for await input in inputs {
                guard !Task.isCancelled else { break }
                let now = start.duration(to: clock.now)
                let actions = switch input {
                case .frame(let frame): connection.receive(frame, now: now)
                case .closed: connection.transportClosed()
                case .tick: connection.tick(now: now)
                }
                for action in actions {
                    switch action {
                    case .send(let frame): try? await socket.send(frame)
                    case .emit(let event): hub.yield(event)
                    case .finish(let outcome): return outcome
                    }
                }
                timer?.cancel()
                timer = arm(connection.nextDeadline)
            }
            for case .emit(let event) in connection.cancel() { hub.yield(event) }
            return .stop
        } onCancel: {
            socket.close()
        }
    }
}

/// Fans the events out to every subscriber.
final class RealtimeEventHub: Sendable {
    private struct State {
        var nextID = 0
        var subscribers: [Int: AsyncStream<RealtimeEvent>.Continuation] = [:]
        var finished = false
    }

    private let state = Mutex(State())

    func stream(bufferingNewest limit: Int) -> AsyncStream<RealtimeEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeEvent.self, bufferingPolicy: .bufferingNewest(max(limit, 1)))
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        let added = state.withLock { state in
            guard !state.finished else { return false }
            state.subscribers[id] = continuation
            return true
        }
        if !added { continuation.finish() }
        return stream
    }

    func yield(_ event: RealtimeEvent) {
        for subscriber in state.withLock({ Array($0.subscribers.values) }) { subscriber.yield(event) }
    }

    func finish() {
        let subscribers = state.withLock { state in
            state.finished = true
            defer { state.subscribers.removeAll() }
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers { subscriber.finish() }
    }
}
