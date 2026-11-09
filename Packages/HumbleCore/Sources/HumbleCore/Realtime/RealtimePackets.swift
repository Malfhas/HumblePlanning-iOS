import Foundation

/// One WebSocket message.
enum RealtimeFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// A frame that is not a valid Engine.IO or Socket.IO packet.
struct MalformedPacket: Error, Equatable {}

/// Engine.IO v4 packet. Over WebSocket each message carries exactly one packet: the
/// record separator of the polling payloads never appears.
enum EnginePacket: Sendable, Equatable {
    case open(EngineHandshake)
    case close
    case ping(String)
    case pong(String)
    case message(String)
    case upgrade
    case noop
    /// A binary message, or a `b<base64>` text one: Socket.IO attachments, which this server never sends.
    case binary(Data)

    static func decode(_ frame: RealtimeFrame) throws(MalformedPacket) -> EnginePacket {
        let text: String
        switch frame {
        case .binary(let data): return .binary(data)
        case .text(let value): text = value
        }
        guard let type = text.first else { throw MalformedPacket() }
        let data = String(text.dropFirst())
        switch type {
        case "0": return .open(try EngineHandshake(json: data))
        case "1": return .close
        case "2": return .ping(data)
        case "3": return .pong(data)
        case "4": return .message(data)
        case "5": return .upgrade
        case "6": return .noop
        case "b":
            guard let bytes = Data(base64Encoded: data) else { throw MalformedPacket() }
            return .binary(bytes)
        default: throw MalformedPacket()
        }
    }

    var frame: RealtimeFrame {
        switch self {
        case .open(let handshake): .text("0" + handshake.json)
        case .close: .text("1")
        case .ping(let data): .text("2" + data)
        case .pong(let data): .text("3" + data)
        case .message(let data): .text("4" + data)
        case .upgrade: .text("5")
        case .noop: .text("6")
        case .binary(let data): .binary(data)
        }
    }
}

/// Payload of the Engine.IO open packet: `{"sid":…,"upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":…}`.
struct EngineHandshake: Sendable, Equatable {
    var sid: String
    /// The server pings this often…
    var pingInterval: Duration
    /// …and closes when no pong comes back within this.
    var pingTimeout: Duration

    /// Without a ping for this long, the connection is dead.
    var pingWindow: Duration { pingInterval + pingTimeout }

    init(sid: String, pingInterval: Duration, pingTimeout: Duration) {
        self.sid = sid
        self.pingInterval = pingInterval
        self.pingTimeout = pingTimeout
    }

    init(json text: String) throws(MalformedPacket) {
        guard let value = try? JSONValue.parse(text),
              let sid = value["sid"]?.stringValue,
              case .number(let interval)? = value["pingInterval"], interval.isFinite, interval >= 0,
              case .number(let timeout)? = value["pingTimeout"], timeout.isFinite, timeout >= 0
        else { throw MalformedPacket() }
        self.init(sid: sid, pingInterval: .milliseconds(interval), pingTimeout: .milliseconds(timeout))
    }

    var json: String {
        let value: JSONValue = [
            "sid": .string(sid),
            "upgrades": [],
            "pingInterval": .number(pingInterval.milliseconds),
            "pingTimeout": .number(pingTimeout.milliseconds),
        ]
        return value.serialized
    }
}

/// Socket.IO v5 packet, the text of an Engine.IO message:
/// `<type>[<attachments>-][<namespace>,][<ack id>][<JSON>]`, the namespace only when it is not `/`.
struct SocketPacket: Sendable, Equatable {
    enum Kind: Int, Sendable {
        case connect, disconnect, event, ack, connectError, binaryEvent, binaryAck

        var isBinary: Bool { self == .binaryEvent || self == .binaryAck }
    }

    /// Event names the protocol keeps for itself: never valid in an event packet.
    static let reservedEvents: Set<String> = ["connect", "connect_error", "disconnect", "disconnecting", "newListener", "removeListener"]

    var kind: Kind
    var namespace: String
    var ackID: Int?
    /// Binary packets only: how many binary messages follow.
    var attachments: Int
    var data: JSONValue?

    init(_ kind: Kind, namespace: String = "/", ackID: Int? = nil, attachments: Int = 0, data: JSONValue? = nil) {
        self.kind = kind
        self.namespace = namespace
        self.ackID = ackID
        self.attachments = attachments
        self.data = data
    }

    static func event(_ name: String, _ arguments: JSONValue...) -> SocketPacket {
        SocketPacket(.event, data: .array([.string(name)] + arguments))
    }

    /// Name and arguments of an event packet.
    var event: (name: String, arguments: [JSONValue])? {
        guard kind == .event, case .array(let values)? = data, case .string(let name)? = values.first else { return nil }
        return (name, Array(values.dropFirst()))
    }

    /// The message of a connect error: `{"message":…}`, or a bare string (protocol v4 servers).
    var errorMessage: String? {
        guard kind == .connectError else { return nil }
        return data?.stringValue ?? data?["message"]?.stringValue
    }

    var encoded: String {
        var text = String(kind.rawValue)
        if kind.isBinary { text += "\(attachments)-" }
        if namespace != "/" { text += namespace + "," }
        if let ackID { text += String(ackID) }
        if let data { text += data.serialized }
        return text
    }

    /// Same reading and checks as `socket.io-parser` (`decodeString`, `isPayloadValid`).
    static func decode(_ text: String) throws(MalformedPacket) -> SocketPacket {
        let bytes = Array(text.utf8)
        guard let first = bytes.first, first >= UInt8(ascii: "0"),
              let kind = Kind(rawValue: Int(first - UInt8(ascii: "0")))
        else { throw MalformedPacket() }
        var index = 1

        func digits() -> Int? {
            let start = index
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
            return index > start ? Int(String(decoding: bytes[start..<index], as: UTF8.self)) : nil
        }

        var attachments = 0
        if kind.isBinary {
            guard let count = digits(), count >= 1, index < bytes.count, bytes[index] == UInt8(ascii: "-") else { throw MalformedPacket() }
            attachments = count
            index += 1
        }

        var namespace = "/"
        if index < bytes.count, bytes[index] == UInt8(ascii: "/") {
            let start = index
            while index < bytes.count, bytes[index] != UInt8(ascii: ",") { index += 1 }
            namespace = String(decoding: bytes[start..<index], as: UTF8.self)
            if index < bytes.count { index += 1 }
        }

        let idStart = index
        let ackID = digits()
        if index > idStart, ackID == nil { throw MalformedPacket() }

        var data: JSONValue?
        if index < bytes.count {
            guard let payload = try? JSONValue.parse(Data(bytes[index...])) else { throw MalformedPacket() }
            data = payload
        }

        let packet = SocketPacket(kind, namespace: namespace, ackID: ackID, attachments: attachments, data: data)
        guard packet.hasValidPayload else { throw MalformedPacket() }
        return packet
    }

    /// Like the parser, only a payload that is present is checked.
    private var hasValidPayload: Bool {
        guard let data else { return true }
        switch kind {
        case .connect:
            return data.objectValue != nil
        case .disconnect:
            return false
        case .connectError:
            return data.stringValue != nil || data.objectValue != nil
        case .event, .binaryEvent:
            guard case .array(let values) = data else { return false }
            switch values.first {
            case .number?: return true
            case .string(let name)?: return !Self.reservedEvents.contains(name)
            default: return false
            }
        case .ack, .binaryAck:
            guard case .array = data else { return false }
            return true
        }
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
