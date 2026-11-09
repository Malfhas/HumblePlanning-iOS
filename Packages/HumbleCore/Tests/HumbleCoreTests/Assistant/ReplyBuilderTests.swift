import Testing
@testable import HumbleCore

/// Port of `ReplyBuilderTest`, plus the edge cases of `ReplyBuilder` in `Assistant.kt`.
struct ReplyBuilderTests {
    @Test func textDeltasAreStreamedThenGathered() {
        var builder = ReplyBuilder()
        #expect(builder.accept(["type": "text-delta", "delta": "Hello "]) == .textDelta("Hello "))
        #expect(builder.accept(["type": "text-delta", "delta": "world"]) == .textDelta("world"))
        #expect(builder.parts == [["type": "text", "text": "Hello world"]])
    }

    @Test func unknownEventsAreIgnored() {
        var builder = ReplyBuilder()
        for type in ["start", "start-step", "text-start", "text-end", "tool-input-start", "tool-input-delta", "reasoning-delta", "finish-step", "finish"] {
            #expect(builder.accept(["type": .string(type), "delta": "x", "toolCallId": "c1"]) == nil)
        }
        #expect(builder.accept(["delta": "no type"]) == nil)
        #expect(builder.parts.isEmpty)
    }

    @Test func nothingReceivedMeansNoParts() {
        #expect(ReplyBuilder().parts.isEmpty)
    }

    @Test func aToolIsAnnouncedThenCompleted() {
        var builder = ReplyBuilder()
        #expect(builder.accept(["type": "tool-input-available", "toolCallId": "c1", "toolName": "list_tasks"]) == .toolStarted(name: "list_tasks"))
        #expect(builder.accept(["type": "tool-output-available", "toolCallId": "c1", "output": ["count": 3]]) == nil)
        #expect(builder.parts == [["type": "tool-list_tasks", "toolCallId": "c1", "state": "output-available", "output": ["count": 3]]])
    }

    @Test func anApprovalCarriesTheToolAndItsInput() {
        var builder = ReplyBuilder()
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c1", "toolName": "create_task", "input": ["title": "Visit"]])
        let event = builder.accept(["type": "tool-approval-request", "toolCallId": "c1", "approvalId": "a1"])
        #expect(event == .approvalRequested(PendingApproval(approvalId: "a1", toolCallId: "c1", toolName: "create_task", input: ["title": "Visit"])))
        #expect(builder.parts == [[
            "type": "tool-create_task", "toolCallId": "c1", "state": "approval-requested",
            "input": ["title": "Visit"], "approval": ["id": "a1"],
        ]])
    }

    @Test func anApprovalOfAnUnknownToolIsIgnored() {
        var builder = ReplyBuilder()
        #expect(builder.accept(["type": "tool-approval-request", "toolCallId": "nope", "approvalId": "a1"]) == nil)
        #expect(builder.parts.isEmpty)
    }

    @Test func anErrorEventFails() {
        var builder = ReplyBuilder()
        #expect(builder.accept(["type": "error", "errorText": "quota reached"]) == .failed(message: "quota reached"))
        #expect(builder.accept(["type": "error"]) == .failed(message: ""))
    }

    @Test func toolsComeFirstThenTheWholeText() {
        var builder = ReplyBuilder()
        _ = builder.accept(["type": "text-delta", "delta": "Looking. "])
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c1", "toolName": "list_tasks"])
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c2", "toolName": "list_users"])
        _ = builder.accept(["type": "text-delta", "delta": "Found."])
        #expect(builder.parts.map { $0["type"] } == ["tool-list_tasks", "tool-list_users", "text"])
        #expect(builder.parts.last?["text"] == "Looking. Found.")
    }

    @Test func aToolAnnouncedAgainKeepsItsPlace() {
        var builder = ReplyBuilder()
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c1", "toolName": "first"])
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c2", "toolName": "second"])
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c1", "toolName": "again"])
        #expect(builder.parts.map { $0["type"] } == ["tool-again", "tool-second"])
    }

    @Test func anOutputOfAnUnknownToolIsIgnored() {
        var builder = ReplyBuilder()
        #expect(builder.accept(["type": "tool-output-available", "toolCallId": "nope", "output": 1]) == nil)
        #expect(builder.parts.isEmpty)
    }

    @Test func missingInputAndOutputAddNoKey() {
        var builder = ReplyBuilder()
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c1", "toolName": "ping"])
        let event = builder.accept(["type": "tool-approval-request", "toolCallId": "c1", "approvalId": "a1"])
        #expect(event == .approvalRequested(PendingApproval(approvalId: "a1", toolCallId: "c1", toolName: "ping", input: nil)))
        _ = builder.accept(["type": "tool-output-available", "toolCallId": "c1"])
        #expect(builder.parts == [["type": "tool-ping", "toolCallId": "c1", "state": "output-available", "approval": ["id": "a1"]]])
    }

    @Test func aNullInputIsKept() {
        var builder = ReplyBuilder()
        _ = builder.accept(["type": "tool-input-available", "toolCallId": "c1", "toolName": "ping", "input": nil])
        let event = builder.accept(["type": "tool-approval-request", "toolCallId": "c1", "approvalId": "a1"])
        #expect(event == .approvalRequested(PendingApproval(approvalId: "a1", toolCallId: "c1", toolName: "ping", input: .null)))
        #expect(builder.parts.first?["input"] == .null)
    }

    @Test func missingFieldsAreEmpty() {
        var builder = ReplyBuilder()
        #expect(builder.accept(["type": "text-delta"]) == .textDelta(""))
        #expect(builder.parts.isEmpty)
        #expect(builder.accept(["type": "tool-input-available"]) == .toolStarted(name: ""))
        #expect(builder.parts == [["type": "tool-", "toolCallId": "", "state": "input-available"]])
    }

    @Test func spacesAloneStillMakeATextPart() {
        var builder = ReplyBuilder()
        _ = builder.accept(["type": "text-delta", "delta": " "])
        #expect(builder.parts == [["type": "text", "text": " "]])
    }

    @Test func fieldsThatAreNotTextAreReadAsMissing() {
        var builder = ReplyBuilder()
        #expect(builder.accept(["type": ["text-delta"], "delta": "x"]) == nil)
        #expect(builder.accept(["type": "text-delta", "delta": ["x"]]) == .textDelta(""))
        #expect(builder.accept(["type": "text-delta", "delta": nil]) == .textDelta(""))
        #expect(builder.accept(["type": "tool-input-available", "toolCallId": 7, "toolName": "count"]) == .toolStarted(name: "count"))
        #expect(builder.parts.first?["toolCallId"] == "7")
    }

    @Test func aDecisionAnswersOnlyItsToolCall() {
        let approval = PendingApproval(approvalId: "a1", toolCallId: "c1", toolName: "create_task", input: nil)
        let other = PendingApproval(approvalId: "a2", toolCallId: "c2", toolName: "create_task", input: nil)
        let line = ChatLine(
            id: "l", fromUser: false, text: "",
            approvals: [approval, other],
            parts: [
                ["toolCallId": "c1", "state": "approval-requested"],
                ["toolCallId": "c2", "state": "approval-requested"],
            ]
        )
        let answered = line.withDecision(approval, approved: true)
        #expect(answered.approvals == [other])
        #expect(answered.parts[0] == ["toolCallId": "c1", "state": "approval-responded", "approval": ["id": "a1", "approved": true]])
        #expect(answered.parts[1] == ["toolCallId": "c2", "state": "approval-requested"])
    }

    @Test func aRefusalIsSentAsNotApprovedAndKeepsTheOtherParts() {
        let approval = PendingApproval(approvalId: "a1", toolCallId: "c1", toolName: "create_task", input: ["title": "Visit"])
        let line = ChatLine(
            id: "l", fromUser: false, text: "Shall I?",
            approvals: [approval],
            parts: [
                ["type": "tool-create_task", "toolCallId": "c1", "state": "approval-requested", "input": ["title": "Visit"], "approval": ["id": "a1"]],
                ["type": "text", "text": "Shall I?"],
            ]
        )
        let answered = line.withDecision(approval, approved: false)
        #expect(answered.approvals.isEmpty)
        #expect(answered.parts[0] == [
            "type": "tool-create_task", "toolCallId": "c1", "state": "approval-responded",
            "input": ["title": "Visit"], "approval": ["id": "a1", "approved": false],
        ])
        #expect(answered.parts[1] == ["type": "text", "text": "Shall I?"])
        #expect(answered.id == "l" && answered.text == "Shall I?")
    }

    @Test func historyFallsBackOnTheTextOfALine() {
        let message = ChatLine(id: "u", fromUser: true, text: "Hi").uiMessage
        #expect(message == ["id": "u", "role": "user", "parts": [["type": "text", "text": "Hi"]]])
    }
}
