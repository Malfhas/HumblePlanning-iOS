import Foundation
import Testing
@testable import HumbleCore

/// Port of `ConversationHelpersTest` (history, tool names, tool inputs), plus the turn rules of
/// `ConversationViewModel` and `AssistantStream`.
struct ConversationHelpersTests {
    private let toolPart: JSONObject = ["type": "tool-x", "state": "approval-responded"]

    // MARK: - History

    @Test func onlyTheResumedLineKeepsItsToolCalls() {
        let history = ChatTurn.history(
            [
                ChatLine(id: "u", fromUser: true, text: "Hi"),
                ChatLine(id: "a1", fromUser: false, text: "Done", parts: [toolPart]),
                ChatLine(id: "a2", fromUser: false, text: "", parts: [toolPart]),
            ],
            resumedLineId: "a2"
        )
        #expect(history.map(\.id) == ["u", "a1", "a2"])
        #expect(history[1].parts.isEmpty)
        #expect(history[2].parts == [toolPart])
    }

    @Test func answersWithoutTextAreLeftOutOfANewTurn() {
        let history = ChatTurn.history(
            [
                ChatLine(id: "a", fromUser: false, text: "", parts: [toolPart]),
                ChatLine(id: "b", fromUser: false, text: " \n\t\u{00A0}"),
                ChatLine(id: "u", fromUser: true, text: "Next"),
            ],
            resumedLineId: nil
        )
        #expect(history.map(\.id) == ["u"])
    }

    @Test func approvalsDoNotGoOut() {
        let approval = PendingApproval(approvalId: "a", toolCallId: "c", toolName: "t", input: nil)
        let history = ChatTurn.history([ChatLine(id: "a", fromUser: false, text: "x", approvals: [approval])], resumedLineId: nil)
        #expect(history.count == 1)
        #expect(history[0].approvals.isEmpty)
    }

    @Test func theResumedLineKeepsItsApprovalsAndUserLinesTheirText() {
        let approval = PendingApproval(approvalId: "a", toolCallId: "c", toolName: "t", input: nil)
        let resumed = ChatLine(id: "r", fromUser: false, text: "", approvals: [approval], parts: [toolPart])
        let history = ChatTurn.history([ChatLine(id: "u", fromUser: true, text: ""), resumed], resumedLineId: "r")
        #expect(history == [ChatLine(id: "u", fromUser: true, text: ""), resumed])
    }

    @Test func theRequestBodyHoldsTheMessagesOnly() {
        let history = [
            ChatLine(id: "u", fromUser: true, text: "Create a visit"),
            ChatLine(id: "a", fromUser: false, text: "Shall I?", parts: [
                ["type": "tool-create_task", "toolCallId": "c1", "state": "approval-responded", "approval": ["id": "a1", "approved": true]],
                ["type": "text", "text": "Shall I?"],
            ]),
        ]
        #expect(ChatTurn.requestBody(history).serialized == """
            {"messages":[{"id":"u","role":"user","parts":[{"type":"text","text":"Create a visit"}]},\
            {"id":"a","role":"assistant","parts":[{"type":"tool-create_task","toolCallId":"c1","state":"approval-responded",\
            "approval":{"id":"a1","approved":true}},{"type":"text","text":"Shall I?"}]}]}
            """)
    }

    // MARK: - Question, title, opening

    @Test func aQuestionIsTheTrimmedDraft() {
        #expect(ChatTurn.question(fromDraft: "  Is Liam free?\n") == "Is Liam free?")
        #expect(ChatTurn.question(fromDraft: "\u{00A0}Hi\u{2003}") == "Hi")
        #expect(ChatTurn.question(fromDraft: " \n\t") == nil)
        #expect(ChatTurn.question(fromDraft: "") == nil)
    }

    @Test func theTitleIsTheStartOfTheFirstQuestion() {
        let long = String(repeating: "a", count: 59) + "bc"
        #expect(ChatTurn.title(forQuestion: long) == String(repeating: "a", count: 59) + "b")
        #expect(ChatTurn.title(forQuestion: "Is Liam Turner available this week?") == "Is Liam Turner available this week?")
        #expect(ChatTurn.title(forQuestion: "") == "")
    }

    @Test func theTitleNeverCutsACharacter() {
        let start = String(repeating: "a", count: 59)
        #expect(ChatTurn.title(forQuestion: start + "🙂") == start)
        #expect(ChatTurn.title(forQuestion: start + "é" + "z") == start + "é")
        let families = String(repeating: "👨‍👩‍👧", count: 10)
        #expect(ChatTurn.title(forQuestion: families) == String(repeating: "👨‍👩‍👧", count: 7))
        #expect(ChatTurn.title(forQuestion: families).utf16.count <= 60)
    }

    @Test func aSavedConversationOpensAsTextLines() throws {
        let json = """
            {"id":"conv","title":"Visit","messages":[
              {"id":"m1","role":"USER","content":"Hi"},
              {"id":"m2","role":"ASSISTANT","content":"  Hello  ","status":"DONE"},
              {"id":"m3","role":"ASSISTANT","content":" \\n "},
              {"id":"m4","role":"SYSTEM","content":"rules"},
              {"id":"m5","role":"user","content":"lower case role"},
              {"id":"m6","role":"TOOL","content":"{}"},
              {"role":"USER","content":"no id"},
              {"id":null,"role":"ASSISTANT","content":null}
            ]}
            """
        let detail = try JSONDecoder().decode(ConversationDetail.self, from: Data(json.utf8))
        let lines = ChatTurn.lines(from: detail.messages)
        #expect(lines.count == 3)
        #expect(lines[0] == ChatLine(id: "m1", fromUser: true, text: "Hi"))
        #expect(lines[1] == ChatLine(id: "m2", fromUser: false, text: "  Hello  "))
        #expect(lines[2].fromUser && lines[2].text == "no id" && lines[2].parts.isEmpty)
        #expect(UUID(uuidString: lines[2].id) != nil)
        #expect(lines[2].id == lines[2].id.lowercased())
    }

    @Test func newLinesHaveFreshIds() {
        let question = ChatLine.user("Hi")
        let reply = ChatLine.newReply()
        #expect(question.fromUser && question.text == "Hi" && question.parts.isEmpty && question.approvals.isEmpty)
        #expect(!reply.fromUser && reply.text.isEmpty)
        #expect(question.id != reply.id)
        #expect(UUID(uuidString: reply.id) != nil && reply.id == reply.id.lowercased())
    }

    @Test func aBlankTextIsNoText() {
        #expect(!ChatLine(id: "a", fromUser: false, text: "").hasText)
        #expect(!ChatLine(id: "a", fromUser: false, text: " \n\u{2028}").hasText)
        #expect(ChatLine(id: "a", fromUser: false, text: " x ").hasText)
    }

    // MARK: - Tool calls for people

    @Test func toolNamesForPeople() {
        #expect(ToolCallText.readableToolName("create_task") == "Create task")
        #expect(ToolCallText.readableToolName("createTask") == "Create task")
        #expect(ToolCallText.readableToolName("create-task") == "Create task")
        #expect(ToolCallText.readableToolName("listTasksByUser") == "List tasks by user")
        #expect(ToolCallText.readableToolName("get2Tasks") == "Get2 tasks")
        #expect(ToolCallText.readableToolName("_list_tasks_") == "List tasks")
        #expect(ToolCallText.readableToolName("HTTPRequest") == "Httprequest")
        #expect(ToolCallText.readableToolName("éTask") == "Étask")
        #expect(ToolCallText.readableToolName("__") == "")
        #expect(ToolCallText.readableToolName("") == "")
    }

    @Test func jsonForPeople() {
        let input: JSONValue = [
            "title": "Visit",
            "count": 2,
            "nothing": nil,
            "users": ["Ann", "Bob"],
            "place": ["city": "Lyon"],
        ]
        #expect(ToolCallText.readableJSON(input) == """
            title: Visit
            count: 2
            users:
              - Ann
              - Bob
            place:
              city: Lyon
            """)
        #expect(ToolCallText.readableJSON(nil) == "")
    }

    @Test func jsonForPeopleEdgeCases() {
        #expect(ToolCallText.readableJSON(.null) == "")
        #expect(ToolCallText.readableJSON("text") == "text")
        #expect(ToolCallText.readableJSON(2.5) == "2.5")
        #expect(ToolCallText.readableJSON(true) == "true")
        #expect(ToolCallText.readableJSON([:]) == "")
        #expect(ToolCallText.readableJSON([]) == "")
        #expect(ToolCallText.readableJSON([1, nil, false]) == "- 1\n- \n- false")
        #expect(ToolCallText.readableJSON(["empty": [:], "next": 1]) == "empty:\n\nnext: 1")
        #expect(ToolCallText.readableJSON(["tasks": [["title": "A", "done": false], ["title": "B"]]]) == """
            tasks:
              -
                title: A
                done: false
              -
                title: B
            """)
        #expect(ToolCallText.readableJSON([["x", ["y"]]]) == "-\n  - x\n  -\n    - y")
        #expect(ToolCallText.readableJSON(["b": 1, "a": 2]) == "b: 1\na: 2")
    }

    @Test func theApprovalCardShowsItsToolAndItsInput() {
        let approval = PendingApproval(approvalId: "a1", toolCallId: "c1", toolName: "createTask", input: ["title": "Visit"])
        #expect(approval.readableToolName == "Create task")
        #expect(approval.readableInput == "title: Visit")
        #expect(PendingApproval(approvalId: "a", toolCallId: "c", toolName: "t", input: nil).readableInput == nil)
        #expect(PendingApproval(approvalId: "a", toolCallId: "c", toolName: "t", input: ["x": nil]).readableInput == nil)
        #expect(PendingApproval(approvalId: "a", toolCallId: "c", toolName: "t", input: " ").readableInput == nil)
    }
}
