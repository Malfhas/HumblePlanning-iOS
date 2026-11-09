import Foundation

/// A write the assistant wants to run: the turn waits for the user's decision.
public struct PendingApproval: Sendable, Hashable, Identifiable {
    public var approvalId: String
    public var toolCallId: String
    /// Technical name (`create_task`); ``readableToolName`` is the one to show.
    public var toolName: String
    public var input: JSONValue?

    public var id: String { approvalId }

    public init(approvalId: String, toolCallId: String, toolName: String, input: JSONValue?) {
        self.approvalId = approvalId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
    }
}

/// One message of a conversation on screen.
public struct ChatLine: Sendable, Hashable, Identifiable {
    public var id: String
    public var fromUser: Bool
    public var text: String
    public var approvals: [PendingApproval]
    /// Parts as the server sent them (AI SDK UI message parts): sent back with the history, tool calls and
    /// approvals included.
    public var parts: [JSONObject]

    public init(id: String, fromUser: Bool, text: String, approvals: [PendingApproval] = [], parts: [JSONObject] = []) {
        self.id = id
        self.fromUser = fromUser
        self.text = text
        self.approvals = approvals
        self.parts = parts
    }

    /// A question of the user, as it goes into the history.
    public static func user(_ text: String) -> ChatLine {
        ChatLine(id: newId(), fromUser: true, text: text)
    }

    /// The empty assistant line that receives the answer of a turn.
    public static func newReply() -> ChatLine {
        ChatLine(id: newId(), fromUser: false, text: "")
    }

    /// Random ids written like the Android app's (`UUID.randomUUID()`, lower case).
    static func newId() -> String { UUID().uuidString.lowercased() }

    /// False for a blank text: no bubble, and an answer ending so with no approval is removed.
    public var hasText: Bool { !text.isKotlinBlank }

    /// The same line with this tool call answered (`approval-responded`, as the web chat sends it); its
    /// other approvals stay pending.
    public func withDecision(_ approval: PendingApproval, approved: Bool) -> ChatLine {
        var answered = self
        answered.approvals.removeAll { $0.approvalId == approval.approvalId }
        answered.parts = parts.map { part in
            guard part["toolCallId"]?.content == approval.toolCallId else { return part }
            var part = part
            part["state"] = .string("approval-responded")
            part["approval"] = .object(["id": .string(approval.approvalId), "approved": .bool(approved)])
            return part
        }
        return answered
    }

    /// The line as a UI message of the history: its parts, or its text alone.
    public var uiMessage: JSONValue {
        let parts = parts.isEmpty ? [["type": "text", "text": .string(text)]] : parts
        return .object([
            "id": .string(id),
            "role": .string(fromUser ? "user" : "assistant"),
            "parts": .array(parts.map(JSONValue.object)),
        ])
    }
}

/// The rules of a conversation turn: question, title, history sent back, opening of a saved conversation.
public enum ChatTurn {
    /// The question to send for this draft (trimmed), nil when it is blank.
    public static func question(fromDraft draft: String) -> String? {
        let message = draft.kotlinTrimmed
        return message.isEmpty ? nil : message
    }

    /// Title of a conversation born from its first question: its first 60 characters.
    ///
    /// Counted in UTF-16 units like Kotlin's `take(60)` (the server limits titles to 200 of them), but
    /// never cutting a character in two: an emoji across the limit is left out rather than split.
    public static func title(forQuestion question: String) -> String {
        var units = 0
        var end = question.startIndex
        for character in question {
            units += character.utf16.count
            guard units <= 60 else { break }
            end = question.index(after: end)
        }
        return String(question[..<end])
    }

    /// The lines of a saved conversation: user and assistant messages with a text, as text only (past
    /// tool calls are not shown).
    public static func lines(from messages: [ConversationMessage]) -> [ChatLine] {
        messages
            .filter { !$0.content.isKotlinBlank && ($0.role == "USER" || $0.role == "ASSISTANT") }
            .map { ChatLine(id: $0.id.isEmpty ? ChatLine.newId() : $0.id, fromUser: $0.role == "USER", text: $0.content) }
    }

    /// History sent with a turn: answers as text, only the line being resumed after a decision keeps its
    /// tool calls and decisions. An answer without text is left out (unless it is the resumed one).
    public static func history(_ lines: [ChatLine], resumedLineId: String?) -> [ChatLine] {
        lines
            .filter { $0.fromUser || $0.hasText || $0.id == resumedLineId }
            .map { line in
                guard line.id != resumedLineId else { return line }
                var textOnly = line
                textOnly.parts = []
                textOnly.approvals = []
                return textOnly
            }
    }

    /// Body of `POST /api/ai-chat/conversations/{id}/messages`: `{"messages": [UI message…]}`, nothing else
    /// (model, reasoning and scope are the server's defaults).
    public static func requestBody(_ history: [ChatLine]) -> JSONValue {
        .object(["messages": .array(history.map(\.uiMessage))])
    }
}
