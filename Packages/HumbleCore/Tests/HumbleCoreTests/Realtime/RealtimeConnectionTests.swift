import Foundation
import Testing
@testable import HumbleCore

@Suite struct RealtimeConnectionTests {
    static let open = #"0{"sid":"e1","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#
    static let connected = #"40{"sid":"s1"}"#

    let timing = RealtimeTiming()

    /// A connection that went through the handshake at `at`.
    func connection(connectedAt at: Duration = .zero) -> RealtimeConnection {
        var connection = RealtimeConnection(timing: timing, now: at)
        _ = connection.receive(.text(Self.open), now: at)
        _ = connection.receive(.text(Self.connected), now: at)
        return connection
    }

    @Test func handshakeConnectsTheDefaultNamespace() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        #expect(connection.nextDeadline == .seconds(20))
        #expect(connection.receive(.text(Self.open), now: .seconds(1)) == [.send(.text("40"))])
        #expect(!connection.isConnected)
        #expect(connection.nextDeadline == .seconds(20))
        #expect(connection.receive(.text(Self.connected), now: .seconds(2)) == [.emit(.connected)])
        #expect(connection.isConnected)
        #expect(connection.nextDeadline == .seconds(32))
    }

    @Test func connectWithoutSessionIDIsIgnored() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        _ = connection.receive(.text(Self.open), now: .zero)
        #expect(connection.receive(.text("40"), now: .zero) == [])
        #expect(connection.receive(.text(#"40{}"#), now: .zero) == [])
        #expect(!connection.isConnected)
    }

    @Test func connectBeforeTheOpenPacketIsIgnored() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        #expect(connection.receive(.text(Self.connected), now: .zero) == [])
        #expect(!connection.isConnected)
    }

    @Test func secondOpenPacketIsIgnored() {
        var connection = connection()
        #expect(connection.receive(.text(Self.open), now: .seconds(1)) == [])
    }

    @Test func answersPingsWithPongs() {
        var connection = connection()
        #expect(connection.receive(.text("2"), now: .seconds(25)) == [.send(.text("3"))])
        #expect(connection.receive(.text("2probe"), now: .seconds(26)) == [.send(.text("3probe"))])
    }

    @Test func answersAPingBeforeTheOpenPacket() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        #expect(connection.receive(.text("2"), now: .zero) == [.send(.text("3"))])
        #expect(connection.nextDeadline == .seconds(20))
    }

    // MARK: Ping timeout

    @Test func noPingWithinIntervalPlusTimeoutIsADeadConnection() {
        var connection = connection()
        _ = connection.tick(now: .seconds(30))
        #expect(connection.tick(now: .milliseconds(44_999)) == [])
        #expect(connection.tick(now: .seconds(45)) == [.emit(.disconnected(.pingTimeout)), .finish(.retry(afterConnection: true))])
        #expect(connection.nextDeadline == nil)
        #expect(connection.tick(now: .seconds(90)) == [])
    }

    @Test func eachPingMovesTheDeadline() {
        var connection = connection()
        _ = connection.receive(.text("2"), now: .seconds(25))
        #expect(connection.tick(now: .seconds(46)) == [.send(RealtimeConnection.heartbeatFrame)])
        #expect(connection.tick(now: .milliseconds(69_999)) == [])
        _ = connection.receive(.text("2"), now: .seconds(50))
        #expect(connection.tick(now: .seconds(94)) == [.send(RealtimeConnection.heartbeatFrame)])
        #expect(connection.tick(now: .seconds(95)) == [.emit(.disconnected(.pingTimeout)), .finish(.retry(afterConnection: true))])
    }

    @Test func otherPacketsDoNotMoveTheDeadline() {
        var connection = connection()
        _ = connection.receive(.text("6"), now: .seconds(40))
        _ = connection.receive(.text("3"), now: .seconds(41))
        _ = connection.receive(.text(#"42["task:changed"]"#), now: .seconds(42))
        #expect(connection.tick(now: .seconds(45)).contains(.emit(.disconnected(.pingTimeout))))
    }

    @Test func pingWindowComesFromTheServer() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        _ = connection.receive(.text(#"0{"sid":"e","upgrades":[],"pingInterval":300,"pingTimeout":200}"#), now: .milliseconds(100))
        #expect(connection.nextDeadline == .milliseconds(600))
        #expect(connection.tick(now: .milliseconds(599)) == [])
        #expect(connection.tick(now: .milliseconds(600)) == [.finish(.retry(afterConnection: false))])
    }

    // MARK: Connect timeout

    @Test func connectTimeoutRetriesWithoutEvent() {
        var connection = RealtimeConnection(timing: timing, now: .seconds(3))
        #expect(connection.tick(now: .milliseconds(22_999)) == [])
        #expect(connection.tick(now: .seconds(23)) == [.finish(.retry(afterConnection: false))])
    }

    @Test func connectTimeoutAlsoCoversTheNamespace() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        _ = connection.receive(.text(Self.open), now: .seconds(1))
        _ = connection.receive(.text("2"), now: .seconds(19))
        #expect(connection.tick(now: .seconds(20)) == [.finish(.retry(afterConnection: false))])
    }

    @Test func connectTimeoutEndsOnceConnected() {
        var connection = connection()
        #expect(connection.tick(now: .seconds(20)) == [])
        #expect(connection.isConnected)
    }

    // MARK: Heartbeat

    @Test func sendsTheHeartbeatEveryThirtySecondsWhileConnected() {
        var connection = connection(connectedAt: .seconds(2))
        #expect(RealtimeConnection.heartbeatFrame == .text(#"42["presence:heartbeat"]"#))
        #expect(connection.tick(now: .milliseconds(31_999)) == [])
        #expect(connection.tick(now: .seconds(32)) == [.send(.text(#"42["presence:heartbeat"]"#))])
        #expect(connection.tick(now: .seconds(33)) == [])
        _ = connection.receive(.text("2"), now: .seconds(40))
        #expect(connection.nextDeadline == .seconds(62))
        #expect(connection.tick(now: .seconds(62)) == [.send(RealtimeConnection.heartbeatFrame)])
    }

    @Test func noHeartbeatBeforeConnected() {
        var connection = RealtimeConnection(timing: RealtimeTiming(connectTimeout: .seconds(60)), now: .zero)
        _ = connection.receive(.text(Self.open), now: .zero)
        #expect(connection.tick(now: .seconds(31)) == [])
    }

    // MARK: Events

    @Test func emitsTheEventsOfTheApp() {
        var connection = connection()
        #expect(connection.receive(.text(#"42["task:changed",{"channel":"task:changed"}]"#), now: .seconds(1)) == [.emit(.taskChanged)])
        #expect(connection.receive(.text(#"42["session:revoked",{}]"#), now: .seconds(1)) == [.emit(.sessionRevoked)])
        #expect(connection.receive(.text(#"42["permissions:changed",{}]"#), now: .seconds(1)) == [.emit(.permissionsChanged)])
        #expect(connection.receive(.text(#"42["ai-chat:availability",{}]"#), now: .seconds(1)) == [.emit(.assistantAvailability)])
        #expect(connection.receive(.text(#"42["mobile:alert",{"alertId":"a9"}]"#), now: .seconds(1)) == [.emit(.mobileAlert(alertId: "a9"))])
    }

    @Test func ignoresWhatTheAppDoesNotUse() {
        var connection = connection()
        let ignored = [
            RealtimeFrame.text(#"42["presence:update",[{"userId":"u"}]]"#),
            .text(#"42/admin,["task:changed"]"#),
            .text(#"43["task:changed"]"#),
            .text(#"451-["task:changed",{"_placeholder":true,"num":0}]"#),
            .binary(Data([1, 2, 3])),
            .text("b" + Data([1]).base64EncodedString()),
            .text(#"42["task:changed""#),
            .text("4"),
            .text("42"),
            .text("x"),
            .text(""),
            .text("5"),
            .text("6"),
            .text("3"),
            .text(#"40/admin,{"sid":"x"}"#),
            .text(#"41/admin,"#),
            .text(#"44/admin,{"message":"Invalid session"}"#),
        ]
        for frame in ignored {
            #expect(connection.receive(frame, now: .seconds(1)) == [], "\(frame)")
        }
        #expect(connection.isConnected)
    }

    @Test func eventWithAnAckIDIsStillDelivered() {
        var connection = connection()
        #expect(connection.receive(.text(#"427["task:changed"]"#), now: .seconds(1)) == [.emit(.taskChanged)])
    }

    @Test func noEventBeforeConnected() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        _ = connection.receive(.text(Self.open), now: .zero)
        #expect(connection.receive(.text(#"42["task:changed"]"#), now: .zero) == [])
    }

    // MARK: End of the connection

    @Test(arguments: ["Not authenticated", "Invalid session", "Session expired", "User not found", "Authentication error"])
    func refusedSessionStops(_ message: String) {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        _ = connection.receive(.text(Self.open), now: .zero)
        #expect(connection.receive(.text(#"44{"message":"\#(message)"}"#), now: .zero) == [.emit(.invalidSession(message: message)), .finish(.stop)])
        #expect(connection.nextDeadline == nil)
        #expect(connection.receive(.text(Self.connected), now: .zero) == [])
    }

    @Test func otherRefusalStopsToo() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        _ = connection.receive(.text(Self.open), now: .zero)
        #expect(connection.receive(.text(#"44{"message":"Nope"}"#), now: .zero) == [.emit(.refused(message: "Nope")), .finish(.stop)])
    }

    @Test func serverDisconnectStops() {
        var connection = connection()
        #expect(connection.receive(.text("41"), now: .seconds(1)) == [.emit(.disconnected(.serverDisconnect)), .finish(.stop)])
        #expect(connection.transportClosed() == [])
    }

    @Test func serverDisconnectBeforeConnectedStopsSilently() {
        var connection = RealtimeConnection(timing: timing, now: .zero)
        _ = connection.receive(.text(Self.open), now: .zero)
        #expect(connection.receive(.text("41"), now: .zero) == [.finish(.stop)])
    }

    @Test func engineCloseRetries() {
        var connection = connection()
        #expect(connection.receive(.text("1"), now: .seconds(1)) == [.emit(.disconnected(.transportClosed)), .finish(.retry(afterConnection: true))])
    }

    @Test func lostTransportRetries() {
        var connected = connection()
        #expect(connected.transportClosed() == [.emit(.disconnected(.transportClosed)), .finish(.retry(afterConnection: true))])
        var opening = RealtimeConnection(timing: timing, now: .zero)
        #expect(opening.transportClosed() == [.finish(.retry(afterConnection: false))])
    }

    @Test func cancelStops() {
        var connected = connection()
        #expect(connected.cancel() == [.emit(.disconnected(.client)), .finish(.stop)])
        #expect(connected.cancel() == [])
        var opening = RealtimeConnection(timing: timing, now: .zero)
        #expect(opening.cancel() == [.finish(.stop)])
    }

    @Test func nothingHappensOnceFinished() {
        var connection = connection()
        _ = connection.transportClosed()
        #expect(connection.receive(.text("2"), now: .seconds(1)) == [])
        #expect(connection.receive(.text(#"42["task:changed"]"#), now: .seconds(1)) == [])
        #expect(connection.tick(now: .seconds(100)) == [])
        #expect(connection.cancel() == [])
    }
}
