import Foundation

extension Repository {
    /// The monthly quota, nil when unknown (no gauge).
    public func assistantQuota() async -> ChatQuota? {
        try? await call { try await $0.assistantQuota() } ?? nil
    }

    public func conversations() async throws -> [Conversation] {
        try await call { try await $0.conversations() }
    }

    public func conversation(_ id: String) async throws -> ConversationDetail {
        try await call { try await $0.conversation(id) }
    }

    public func createConversation(title: String) async throws -> Conversation {
        try await call { try await $0.createConversation(title: title) }
    }

    public func renameConversation(_ id: String, title: String) async throws -> String {
        let renamed = try await call { try await $0.renameConversation(id, title: title) }
        return renamed.title.isEmpty ? title : renamed.title
    }

    public func deleteConversation(_ id: String) async throws {
        try await call { try await $0.deleteConversation(id) }
    }

    public func stopConversation(_ id: String) async throws {
        try await call { try await $0.stopConversation(id) }
    }

    /// The lines of the answer to `body` (``ChatTurn/requestBody(_:)``). Unlike the Android app, a refusal of the
    /// whole app (update required, maintenance, permission withdrawn) shows the blocking screen here too.
    public func chatTurn(_ conversationId: String, body: JSONValue) async throws -> AsyncThrowingStream<String, any Error> {
        try await call { try await $0.chatTurn(conversationId, body: body) }
    }
}
