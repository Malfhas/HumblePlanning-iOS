import Foundation

/// The monthly quota of the assistant (`GET /api/ai-chat/access`).
public struct ChatQuota: Codable, Sendable, Hashable {
    @DefaultFalse public var enabled: Bool
    @DefaultFalse public var unlimited: Bool
    /// 0…100
    @DefaultZero public var percent: Int
    @DefaultFalse public var reached: Bool
    /// ISO date-time
    @DefaultEmptyString public var resetsAt: String

    public init(enabled: Bool = false, unlimited: Bool = false, percent: Int = 0, reached: Bool = false, resetsAt: String = "") {
        self.enabled = enabled
        self.unlimited = unlimited
        self.percent = percent
        self.reached = reached
        self.resetsAt = resetsAt
    }

    /// Questions are refused until the reset.
    public var blocksQuestions: Bool { enabled && reached && !unlimited }

    public enum Level: Sendable { case success, warning, danger }

    /// Colour of the gauge, as on the web.
    public var level: Level { percent >= 90 ? .danger : percent >= 70 ? .warning : .success }
}

struct AssistantState: Codable {
    var quota: ChatQuota?
}

public struct Conversation: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var title: String
    @DefaultFalse public var pinned: Bool
    public var updatedAt: String?
    public var projectId: String?
}

public struct ConversationMessage: Codable, Sendable, Hashable {
    @DefaultEmptyString public var id: String
    /// `USER`, `ASSISTANT`…
    @DefaultEmptyString public var role: String
    @DefaultEmptyString public var content: String
    public var status: String?
    public var error: String?
}

public struct ConversationDetail: Codable, Sendable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var title: String
    @DefaultEmpty<ConversationMessage> public var messages: [ConversationMessage]
}

struct NewConversationRequest: Encodable {
    var title: String?
    var projectId: String?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(projectId, forKey: .projectId)
    }

    enum CodingKeys: String, CodingKey { case title, projectId }
}
