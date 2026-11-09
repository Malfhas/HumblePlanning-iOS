import Foundation

/// What a turn's stream means for the screen.
public enum ChatEvent: Sendable, Hashable {
    /// More text of the answer.
    case textDelta(String)
    /// A tool runs on the server: `name` is its technical name.
    case toolStarted(name: String)
    /// A write waits for the user's decision: the turn stops there.
    case approvalRequested(PendingApproval)
    /// An `error` event (the stream goes on), or a failed request or read (the stream is over, with no
    /// ``finished(parts:)``). A blank message means the network.
    case failed(message: String)
    /// End of the stream: the parts of the answer, to keep on its line for the history.
    case finished(parts: [JSONObject])
}

/// Rebuilds the assistant message from the events of its stream (AI SDK UI message stream).
///
/// Fields that should be text but are arrays or objects are read as missing (the Android app throws).
public struct ReplyBuilder: Sendable {
    private var text = ""
    private var toolCallIds: [String] = []
    private var tools: [String: JSONObject] = [:]

    public init() {}

    /// Takes one event of the stream; returns what the screen must show of it, if anything.
    public mutating func accept(_ event: JSONObject) -> ChatEvent? {
        func field(_ name: String) -> String? { event[name]?.content }
        switch field("type") {
        case "text-delta":
            let delta = field("delta") ?? ""
            text += delta
            return .textDelta(delta)
        case "tool-input-available":
            let id = field("toolCallId") ?? ""
            let name = field("toolName") ?? ""
            var part: JSONObject = ["type": .string("tool-\(name)"), "toolCallId": .string(id), "state": "input-available"]
            if let input = event["input"] { part["input"] = input }
            if tools[id] == nil { toolCallIds.append(id) }
            tools[id] = part
            return .toolStarted(name: name)
        case "tool-approval-request":
            let id = field("toolCallId") ?? ""
            guard var part = tools[id] else { return nil }
            let approvalId = field("approvalId") ?? ""
            part["state"] = "approval-requested"
            part["approval"] = .object(["id": .string(approvalId)])
            tools[id] = part
            let type = part["type"]?.content ?? ""
            let name = type.dropping(prefix: "tool-") ?? type
            return .approvalRequested(PendingApproval(approvalId: approvalId, toolCallId: id, toolName: name, input: part["input"]))
        case "tool-output-available":
            let id = field("toolCallId") ?? ""
            guard var part = tools[id] else { return nil }
            part["state"] = "output-available"
            if let output = event["output"] { part["output"] = output }
            tools[id] = part
            return nil
        case "error":
            return .failed(message: field("errorText") ?? "")
        default:
            return nil
        }
    }

    /// The tool parts in the order they were announced, then the whole text as one part if there is any:
    /// how text and tool calls were interleaved is not kept.
    public var parts: [JSONObject] {
        var parts = toolCallIds.compactMap { tools[$0] }
        if !text.isEmpty { parts.append(["type": "text", "text": .string(text)]) }
        return parts
    }
}
