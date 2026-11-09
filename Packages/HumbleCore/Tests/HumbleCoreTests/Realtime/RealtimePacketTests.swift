import Foundation
import Testing
@testable import HumbleCore

@Suite struct EnginePacketTests {
    @Test func decodesTheOpenPacket() throws {
        let packet = try EnginePacket.decode(.text(#"0{"sid":"lv_VI97HAXpY6yYWAAAC","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#))
        #expect(packet == .open(EngineHandshake(sid: "lv_VI97HAXpY6yYWAAAC", pingInterval: .seconds(25), pingTimeout: .seconds(20))))
        guard case .open(let handshake) = packet else { return }
        #expect(handshake.pingWindow == .seconds(45))
    }

    @Test(arguments: [
        #"0"#,
        #"0{}"#,
        #"0{"sid":"a","pingInterval":"25000","pingTimeout":20000}"#,
        #"0{"sid":"a","pingInterval":25000}"#,
        #"0{"sid":1,"pingInterval":25000,"pingTimeout":20000}"#,
        #"0{"sid":"a","pingInterval":-1,"pingTimeout":20000}"#,
        #"0{"sid":"a","pingInterval":25000,"pingTimeout":20000"#,
    ])
    func rejectsAnInvalidOpenPacket(_ text: String) {
        #expect(throws: MalformedPacket.self) { try EnginePacket.decode(.text(text)) }
    }

    @Test func decodesEveryPacketType() throws {
        #expect(try EnginePacket.decode(.text("1")) == .close)
        #expect(try EnginePacket.decode(.text("2")) == .ping(""))
        #expect(try EnginePacket.decode(.text("2probe")) == .ping("probe"))
        #expect(try EnginePacket.decode(.text("3")) == .pong(""))
        #expect(try EnginePacket.decode(.text(#"42["task:changed"]"#)) == .message(#"2["task:changed"]"#))
        #expect(try EnginePacket.decode(.text("4")) == .message(""))
        #expect(try EnginePacket.decode(.text("5")) == .upgrade)
        #expect(try EnginePacket.decode(.text("6")) == .noop)
    }

    @Test func keepsUnicodeInMessages() throws {
        #expect(try EnginePacket.decode(.text(#"42["x","é 👋"]"#)) == .message(#"2["x","é 👋"]"#))
    }

    @Test func decodesBinaryMessages() throws {
        let bytes = Data([0, 1, 2, 255])
        #expect(try EnginePacket.decode(.binary(bytes)) == .binary(bytes))
        #expect(try EnginePacket.decode(.text("b" + bytes.base64EncodedString())) == .binary(bytes))
        #expect(throws: MalformedPacket.self) { try EnginePacket.decode(.text("b%%%")) }
    }

    @Test(arguments: ["", "7", "9", "x", " 2"])
    func rejectsUnknownTypes(_ text: String) {
        #expect(throws: MalformedPacket.self) { try EnginePacket.decode(.text(text)) }
    }

    @Test func encodesTheClientPackets() {
        #expect(EnginePacket.pong("").frame == .text("3"))
        #expect(EnginePacket.pong("probe").frame == .text("3probe"))
        #expect(EnginePacket.message("0").frame == .text("40"))
        #expect(EnginePacket.close.frame == .text("1"))
        #expect(EnginePacket.ping("").frame == .text("2"))
        #expect(EnginePacket.upgrade.frame == .text("5"))
        #expect(EnginePacket.noop.frame == .text("6"))
        #expect(EnginePacket.binary(Data([7])).frame == .binary(Data([7])))
    }

    @Test func roundTripsTheHandshake() throws {
        let handshake = EngineHandshake(sid: "abc", pingInterval: .milliseconds(1500), pingTimeout: .milliseconds(250))
        #expect(try EnginePacket.decode(EnginePacket.open(handshake).frame) == .open(handshake))
    }
}

@Suite struct SocketPacketTests {
    @Test func decodesConnectPackets() throws {
        #expect(try SocketPacket.decode("0") == SocketPacket(.connect))
        #expect(try SocketPacket.decode(#"0{"sid":"oSO0OpakmFMwnIMiAAAC"}"#) == SocketPacket(.connect, data: ["sid": "oSO0OpakmFMwnIMiAAAC"]))
        #expect(try SocketPacket.decode(#"0/admin,{"sid":"x"}"#) == SocketPacket(.connect, namespace: "/admin", data: ["sid": "x"]))
        #expect(try SocketPacket.decode("0/admin,") == SocketPacket(.connect, namespace: "/admin"))
        #expect(try SocketPacket.decode("0/admin") == SocketPacket(.connect, namespace: "/admin"))
    }

    @Test func decodesConnectErrors() throws {
        let object = try SocketPacket.decode(#"4{"message":"Invalid session"}"#)
        #expect(object == SocketPacket(.connectError, data: ["message": "Invalid session"]))
        #expect(object.errorMessage == "Invalid session")
        #expect(try SocketPacket.decode(#"4{"message":"Not authenticated","data":{"code":1}}"#).errorMessage == "Not authenticated")
        #expect(try SocketPacket.decode(#"4"Session expired""#).errorMessage == "Session expired")
        #expect(try SocketPacket.decode(#"4{}"#).errorMessage == nil)
        #expect(SocketPacket(.event, data: ["x"]).errorMessage == nil)
    }

    @Test func decodesDisconnect() throws {
        #expect(try SocketPacket.decode("1") == SocketPacket(.disconnect))
        #expect(try SocketPacket.decode("1/admin,") == SocketPacket(.disconnect, namespace: "/admin"))
    }

    @Test func decodesEvents() throws {
        let packet = try SocketPacket.decode(#"2["task:changed",{"channel":"task:changed","taskId":"t1","count":2}]"#)
        #expect(packet.kind == .event)
        #expect(packet.namespace == "/")
        #expect(packet.ackID == nil)
        let event = try #require(packet.event)
        #expect(event.name == "task:changed")
        #expect(event.arguments == [["channel": "task:changed", "taskId": "t1", "count": 2]])
        #expect(try SocketPacket.decode(#"2["session:revoked"]"#).event?.arguments == [])
    }

    @Test func keepsTheOrderOfObjectKeys() throws {
        let packet = try SocketPacket.decode(#"2["x",{"b":1,"a":2}]"#)
        #expect(packet.event?.arguments.first?.objectValue?.keys == ["b", "a"])
    }

    @Test func decodesAckIDsAndNamespaces() throws {
        let packet = try SocketPacket.decode(#"2/admin,13["hello",1]"#)
        #expect(packet == SocketPacket(.event, namespace: "/admin", ackID: 13, data: ["hello", 1]))
        #expect(try SocketPacket.decode(#"212["x"]"#) == SocketPacket(.event, ackID: 12, data: ["x"]))
        #expect(try SocketPacket.decode(#"37["ok"]"#) == SocketPacket(.ack, ackID: 7, data: ["ok"]))
        #expect(try SocketPacket.decode(#"2[1,"x"]"#).event == nil)
    }

    @Test func decodesBinaryPacketsWithoutTheirAttachments() throws {
        let event = try SocketPacket.decode(#"51-["upload",{"_placeholder":true,"num":0}]"#)
        #expect(event.kind == .binaryEvent)
        #expect(event.attachments == 1)
        #expect(event.event == nil)
        let ack = try SocketPacket.decode(#"62-/admin,4[{"_placeholder":true,"num":0},{"_placeholder":true,"num":1}]"#)
        #expect(ack.kind == .binaryAck)
        #expect(ack.attachments == 2)
        #expect(ack.namespace == "/admin")
        #expect(ack.ackID == 4)
    }

    @Test func acceptsPacketsWithoutPayload() throws {
        #expect(try SocketPacket.decode("2") == SocketPacket(.event))
        #expect(try SocketPacket.decode("2").event == nil)
        #expect(try SocketPacket.decode("4") == SocketPacket(.connectError))
        #expect(try SocketPacket.decode("3") == SocketPacket(.ack))
    }

    @Test(arguments: [
        "", "7", "9", "a", "/", "-1",
        "2{}", #"2"x""#, "2[]", #"2[{}]"#, #"2["connect"]"#, #"2["disconnect",1]"#, #"2["x""#,
        #"0"x""#, "0[]", "1{}", "4[]", "4 1", "3{}",
        #"5["x"]"#, #"50-["x"]"#, #"5-["x"]"#, #"51["x"]"#, #"5x-["x"]"#,
        #"299999999999999999999999["x"]"#,
    ])
    func rejectsInvalidPackets(_ text: String) {
        #expect(throws: MalformedPacket.self) { try SocketPacket.decode(text) }
    }

    @Test func encodesClientPackets() {
        #expect(SocketPacket(.connect).encoded == "0")
        #expect(SocketPacket(.connect, data: ["token": "x"]).encoded == #"0{"token":"x"}"#)
        #expect(SocketPacket(.connect, namespace: "/admin").encoded == "0/admin,")
        #expect(SocketPacket(.disconnect).encoded == "1")
        #expect(SocketPacket.event("presence:heartbeat").encoded == #"2["presence:heartbeat"]"#)
        #expect(SocketPacket.event("x", 1, "é\n").encoded == #"2["x",1,"é\n"]"#)
        #expect(SocketPacket(.event, namespace: "/admin", ackID: 3, data: ["x"]).encoded == #"2/admin,3["x"]"#)
        #expect(SocketPacket(.binaryEvent, attachments: 1, data: ["x", ["_placeholder": true, "num": 0]]).encoded
            == #"51-["x",{"_placeholder":true,"num":0}]"#)
    }

    @Test(arguments: [
        SocketPacket(.connect),
        SocketPacket(.connect, data: ["sid": "x"]),
        SocketPacket(.disconnect, namespace: "/n"),
        SocketPacket(.event, data: ["a", ["b": [1, 2.5, true, nil]]]),
        SocketPacket(.event, namespace: "/n", ackID: 42, data: ["a"]),
        SocketPacket(.ack, ackID: 0, data: []),
        SocketPacket(.connectError, data: ["message": "Invalid session"]),
        SocketPacket(.binaryAck, namespace: "/n", ackID: 5, attachments: 3, data: [1]),
    ])
    func roundTrips(_ packet: SocketPacket) throws {
        #expect(try SocketPacket.decode(packet.encoded) == packet)
    }
}
