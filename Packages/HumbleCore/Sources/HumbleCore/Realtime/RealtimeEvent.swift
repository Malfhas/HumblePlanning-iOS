import Foundation

/// What the real-time connection tells the app. The server only says that something changed: the
/// screens then reload. Every `connected` is followed by exactly one `disconnected` before the next one.
public enum RealtimeEvent: Sendable, Equatable {
    /// The session was accepted, also after each reconnection: reload to catch up with what changed meanwhile.
    case connected
    /// A connection that was `connected` ended.
    case disconnected(RealtimeDisconnectReason)
    /// The handshake was refused with a session message (`Not authenticated`, `Invalid session`,
    /// `Session expired`, `User not found`, `Authentication error`): probe `GET /api/profile`, only a
    /// 401 there ends the session. Not retried until the next `connect` or `reconnect`.
    case invalidSession(message: String)
    /// The handshake was refused with another message. Not retried either.
    case refused(message: String)
    /// `task:changed`: reload the tasks.
    case taskChanged
    /// `session:revoked`, sent to every session of the user when one of them ends: probe `GET /api/profile`.
    case sessionRevoked
    /// `permissions:changed`: reload the reference data.
    case permissionsChanged
    /// `ai-chat:availability`: reload the reference data.
    case assistantAvailability
    /// `mobile:alert` `{alertId}`: read the alerts.
    case mobileAlert(alertId: String?)
}

public enum RealtimeDisconnectReason: Sendable, Equatable {
    /// The WebSocket closed or failed: reconnecting.
    case transportClosed
    /// No ping from the server within `pingInterval + pingTimeout`: reconnecting.
    case pingTimeout
    /// The server ended the connection (`41`: ended session, shutdown): not retried, like the Socket.IO clients.
    case serverDisconnect
    /// `disconnect()`, or `connect()` replacing the connection.
    case client
}

extension RealtimeEvent {
    /// Connect errors of the server's handshake middleware about the session.
    static let sessionRefusals: Set<String> = ["Not authenticated", "Invalid session", "Session expired", "User not found", "Authentication error"]

    /// The event for a refused handshake.
    init(refusal message: String) {
        self = Self.sessionRefusals.contains(message) ? .invalidSession(message: message) : .refused(message: message)
    }

    /// The app's event for a server event, nil for the others (`presence:update`…).
    init?(serverEvent name: String, arguments: [JSONValue]) {
        switch name {
        case "task:changed": self = .taskChanged
        case "session:revoked": self = .sessionRevoked
        case "permissions:changed": self = .permissionsChanged
        case "ai-chat:availability": self = .assistantAvailability
        case "mobile:alert":
            let alertId: String? = switch arguments.first?["alertId"] {
            case .string(let value)?: value
            case .number(let value)?: JSONValue.format(value)
            default: nil
            }
            self = .mobileAlert(alertId: alertId)
        default: return nil
        }
    }
}
