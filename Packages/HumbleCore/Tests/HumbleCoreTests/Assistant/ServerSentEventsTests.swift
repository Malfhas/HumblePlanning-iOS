import Foundation
import Testing
@testable import HumbleCore

/// The read loop of `AssistantStream.turn`, line by line and byte by byte.
struct ServerSentEventsTests {
    @Test func onlyDataLinesCount() {
        #expect(SSELine.parse("") == nil)
        #expect(SSELine.parse("   ") == nil)
        #expect(SSELine.parse(": keep-alive") == nil)
        #expect(SSELine.parse("event: message") == nil)
        #expect(SSELine.parse("id: 4") == nil)
        #expect(SSELine.parse("Data: {\"type\":\"start\"}") == nil)
        #expect(SSELine.parse(" data: {\"type\":\"start\"}") == nil)
    }

    @Test func aDataLineHoldsAnEvent() {
        #expect(SSELine.parse("data: {\"type\":\"text-delta\",\"delta\":\"Hi\"}") == .event(["type": "text-delta", "delta": "Hi"]))
        #expect(SSELine.parse("data:{\"type\":\"start\"}") == .event(["type": "start"]))
        #expect(SSELine.parse("data: \t{\"type\":\"start\"}  \r") == .event(["type": "start"]))
    }

    @Test func doneEndsTheStream() {
        #expect(SSELine.parse("data: [DONE]") == .done)
        #expect(SSELine.parse("data:[DONE]") == .done)
        #expect(SSELine.parse("data:   [DONE]  ") == .done)
        #expect(SSELine.parse("data: [done]") == nil)
    }

    @Test func unparsableDataIsSkipped() {
        #expect(SSELine.parse("data:") == nil)
        #expect(SSELine.parse("data: not json") == nil)
        #expect(SSELine.parse("data: {\"type\":") == nil)
        #expect(SSELine.parse("data: 42") == nil)
        #expect(SSELine.parse("data: [1, 2]") == nil)
        #expect(SSELine.parse("data: \"text\"") == nil)
    }

    @Test func aWholeTurnGivesItsEventsThenItsParts() async throws {
        let body = """
            data: {"type":"start"}

            data: {"type":"start-step"}

            data: {"type":"text-start","id":"t1"}

            data: {"type":"text-delta","id":"t1","delta":"Let me "}

            data: {"type":"text-delta","id":"t1","delta":"check.\u{2028}"}

            : comment
            data: not json

            data: {"type":"tool-input-available","toolCallId":"c1","toolName":"create_task","input":{"title":"Visit"}}

            data: {"type":"tool-approval-request","toolCallId":"c1","approvalId":"a1"}

            data: {"type":"finish"}

            data: [DONE]

            data: {"type":"text-delta","delta":"after done"}

            """
        let events = try await turnEvents(Data(body.utf8))
        #expect(events == [
            .textDelta("Let me "),
            .textDelta("check.\u{2028}"),
            .toolStarted(name: "create_task"),
            .approvalRequested(PendingApproval(approvalId: "a1", toolCallId: "c1", toolName: "create_task", input: ["title": "Visit"])),
            .finished(parts: [
                ["type": "tool-create_task", "toolCallId": "c1", "state": "approval-requested", "input": ["title": "Visit"], "approval": ["id": "a1"]],
                ["type": "text", "text": "Let me check.\u{2028}"],
            ]),
        ])
    }

    @Test func aBodyWithoutDoneStillFinishes() async throws {
        let events = try await turnEvents(Data("data: {\"type\":\"text-delta\",\"delta\":\"Hi\"}".utf8))
        #expect(events == [.textDelta("Hi"), .finished(parts: [["type": "text", "text": "Hi"]])])
        #expect(try await turnEvents(Data()) == [.finished(parts: [])])
    }

    @Test func linesAreSplitOnLineFeedsOnly() async throws {
        let body = "a\nb\r\n\nc\rd\n\u{2028}e\u{85}f\r\n\r\nlast"
        #expect(try await lines(Data(body.utf8)) == ["a", "b", "", "c\rd", "\u{2028}e\u{85}f", "", "last"])
    }

    @Test func aFinalLineFeedMakesNoEmptyLine() async throws {
        #expect(try await lines(Data("a\n".utf8)) == ["a"])
        #expect(try await lines(Data("a\n\n".utf8)) == ["a", ""])
        #expect(try await lines(Data("\n".utf8)) == [""])
        #expect(try await lines(Data()) == [])
        #expect(try await lines(Data("a\r".utf8)) == ["a\r"])
    }

    @Test func multiByteCharactersAndBadBytes() async throws {
        #expect(try await lines(Data("é🙂\n".utf8)) == ["é🙂"])
        #expect(try await lines(Data([0x61, 0xFF, 0x62, 0x0A])) == ["a\u{FFFD}b"])
    }

    @Test func aReadErrorIsPassedOn() async throws {
        let failing = AsyncThrowingStream<UInt8, any Error> { continuation in
            for byte in "data: x\nda".utf8 { continuation.yield(byte) }
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }
        var iterator = failing.sseLines.makeAsyncIterator()
        #expect(try await iterator.next() == "data: x")
        do {
            _ = try await iterator.next()
            Issue.record("the read error was swallowed")
        } catch {
            #expect((error as? URLError)?.code == .networkConnectionLost)
        }
    }

    // MARK: - Helpers

    private func bytes(_ data: Data) -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            for byte in data { continuation.yield(byte) }
            continuation.finish()
        }
    }

    private func lines(_ data: Data) async throws -> [String] {
        var lines: [String] = []
        for try await line in bytes(data).sseLines { lines.append(line) }
        return lines
    }

    /// What the network layer does with a turn's body.
    private func turnEvents(_ data: Data) async throws -> [ChatEvent] {
        var builder = ReplyBuilder()
        var events: [ChatEvent] = []
        reading: for try await line in bytes(data).sseLines {
            switch SSELine.parse(line) {
            case nil: continue
            case .done: break reading
            case .event(let event): if let shown = builder.accept(event) { events.append(shown) }
            }
        }
        events.append(.finished(parts: builder.parts))
        return events
    }
}
