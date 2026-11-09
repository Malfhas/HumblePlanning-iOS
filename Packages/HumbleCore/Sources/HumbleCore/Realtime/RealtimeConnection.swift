import Foundation

/// The protocol of one connection attempt, without I/O nor clock: fed the frames received and the
/// time elapsed since the attempt started, it answers with the frames to send, the events to emit and
/// the end of the attempt.
struct RealtimeConnection {
    enum Action: Equatable {
        case send(RealtimeFrame)
        case emit(RealtimeEvent)
        case finish(Outcome)
    }

    enum Outcome: Equatable {
        /// Lost (or timed out): try again after a back-off delay, reset when the attempt had connected.
        case retry(afterConnection: Bool)
        /// Refused, ended by the server or by the client: no new attempt.
        case stop
    }

    private enum Phase { case opening, connecting, connected, finished }

    static let connectFrame = EnginePacket.message(SocketPacket(.connect).encoded).frame
    static let heartbeatFrame = EnginePacket.message(SocketPacket.event("presence:heartbeat").encoded).frame

    private let timing: RealtimeTiming
    private var phase = Phase.opening
    private let connectDeadline: Duration
    private var pingWindow: Duration?
    private var pingDeadline: Duration?
    private var heartbeatDue: Duration?

    init(timing: RealtimeTiming, now: Duration) {
        self.timing = timing
        connectDeadline = now + timing.connectTimeout
    }

    var isConnected: Bool { phase == .connected }

    /// When `tick(now:)` has something to check next; nil once finished.
    var nextDeadline: Duration? {
        switch phase {
        case .opening, .connecting: [connectDeadline, pingDeadline].compactMap(\.self).min()
        case .connected: [pingDeadline, heartbeatDue].compactMap(\.self).min()
        case .finished: nil
        }
    }

    /// Malformed frames, binary messages and packets of other namespaces are ignored.
    mutating func receive(_ frame: RealtimeFrame, now: Duration) -> [Action] {
        guard phase != .finished, let packet = try? EnginePacket.decode(frame) else { return [] }
        switch packet {
        case .open(let handshake):
            guard phase == .opening else { return [] }
            phase = .connecting
            pingWindow = handshake.pingWindow
            pingDeadline = now + handshake.pingWindow
            return [.send(Self.connectFrame)]
        case .ping(let data):
            if let pingWindow { pingDeadline = now + pingWindow }
            return [.send(EnginePacket.pong(data).frame)]
        case .message(let text):
            guard let packet = try? SocketPacket.decode(text), packet.namespace == "/" else { return [] }
            return receive(packet, now: now)
        case .close:
            return end(.transportClosed)
        case .pong, .upgrade, .noop, .binary:
            return []
        }
    }

    private mutating func receive(_ packet: SocketPacket, now: Duration) -> [Action] {
        switch packet.kind {
        case .connect:
            guard phase == .connecting, packet.data?["sid"]?.stringValue != nil else { return [] }
            phase = .connected
            heartbeatDue = now + timing.heartbeatInterval
            return [.emit(.connected)]
        case .connectError:
            return [.emit(RealtimeEvent(refusal: packet.errorMessage ?? ""))] + end(.serverDisconnect)
        case .disconnect:
            return end(.serverDisconnect)
        case .event:
            guard phase == .connected, let (name, arguments) = packet.event,
                  let event = RealtimeEvent(serverEvent: name, arguments: arguments)
            else { return [] }
            return [.emit(event)]
        case .ack, .binaryEvent, .binaryAck:
            return []
        }
    }

    /// Checks the deadlines: connect timeout, ping timeout, heartbeat.
    mutating func tick(now: Duration) -> [Action] {
        switch phase {
        case .finished:
            return []
        case .opening, .connecting:
            if now >= connectDeadline {
                phase = .finished
                return [.finish(.retry(afterConnection: false))]
            }
        case .connected:
            break
        }
        if let pingDeadline, now >= pingDeadline { return end(.pingTimeout) }
        if phase == .connected, let heartbeatDue, now >= heartbeatDue {
            self.heartbeatDue = now + timing.heartbeatInterval
            return [.send(Self.heartbeatFrame)]
        }
        return []
    }

    /// The WebSocket closed or failed.
    mutating func transportClosed() -> [Action] {
        phase == .finished ? [] : end(.transportClosed)
    }

    /// The client stops the connection.
    mutating func cancel() -> [Action] {
        phase == .finished ? [] : end(.client)
    }

    private mutating func end(_ reason: RealtimeDisconnectReason) -> [Action] {
        let wasConnected = phase == .connected
        phase = .finished
        let outcome: Outcome = switch reason {
        case .transportClosed, .pingTimeout: .retry(afterConnection: wasConnected)
        case .serverDisconnect, .client: .stop
        }
        return (wasConnected ? [.emit(.disconnected(reason))] : []) + [.finish(outcome)]
    }
}
