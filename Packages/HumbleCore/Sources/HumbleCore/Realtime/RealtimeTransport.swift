import Foundation

/// Opens WebSocket connections (a fake one in the tests).
protocol RealtimeTransport: Sendable {
    /// Starts connecting at once; a failure surfaces through `receive()`.
    func open(_ request: URLRequest) -> any RealtimeSocket
}

/// One WebSocket connection.
protocol RealtimeSocket: Sendable {
    func send(_ frame: RealtimeFrame) async throws
    /// The next message; throws once the connection is closed or has failed.
    func receive() async throws -> RealtimeFrame
    /// Closes the connection (idempotent): a pending `receive()` then throws.
    func close()
}

/// WebSocket over `URLSessionWebSocketTask`.
final class URLSessionRealtimeTransport: RealtimeTransport {
    private let session: URLSession
    private let ownsSession: Bool

    /// Without a session, an ephemeral one that never stores nor adds cookies: the handshake carries its own `Cookie`.
    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            ownsSession = false
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
            ownsSession = true
        }
    }

    deinit {
        if ownsSession { session.invalidateAndCancel() }
    }

    func open(_ request: URLRequest) -> any RealtimeSocket {
        let task = session.webSocketTask(with: request)
        task.resume()
        return Socket(task: task)
    }

    private struct Socket: RealtimeSocket {
        let task: URLSessionWebSocketTask

        func send(_ frame: RealtimeFrame) async throws {
            switch frame {
            case .text(let text): try await task.send(.string(text))
            case .binary(let data): try await task.send(.data(data))
            }
        }

        func receive() async throws -> RealtimeFrame {
            switch try await task.receive() {
            case .string(let text): return .text(text)
            case .data(let data): return .binary(data)
            @unknown default: return .binary(Data())
            }
        }

        func close() {
            task.cancel(with: .normalClosure, reason: nil)
        }
    }
}
