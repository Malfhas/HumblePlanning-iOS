import SwiftUI
import HumbleCore

/// One conversation with the assistant: its lines, the answer being streamed, the changes waiting
/// for approval, the quota.
@MainActor
@Observable
final class ConversationModel {
    private(set) var conversationId: String?
    private(set) var title: String?
    private(set) var lines: [ChatLine] = []
    private(set) var quota: ChatQuota?
    private(set) var loading = false
    private(set) var loadError: String?
    private(set) var streaming = false
    /// A tool of the server is running.
    private(set) var working = false
    var error: String?
    var draft = ""

    private let repository: Repository
    private var turn: Task<Void, Never>?

    init(repository: Repository, conversationId: String?) {
        self.repository = repository
        self.conversationId = conversationId
    }

    var waitingForDecision: Bool { lines.contains { !$0.approvals.isEmpty } }
    var quotaReached: Bool { quota?.blocksQuestions == true }
    var canSend: Bool {
        ChatTurn.question(fromDraft: draft) != nil && !streaming && !waitingForDecision && !loading && loadError == nil
    }

    func load() async {
        quota = await repository.assistantQuota()
        guard let conversationId else { return }
        loading = true
        loadError = nil
        do {
            let detail = try await repository.conversation(conversationId)
            title = detail.title
            lines = ChatTurn.lines(from: detail.messages)
        } catch {
            loadError = screenMessage(error)
        }
        loading = false
    }

    func send() {
        guard let message = ChatTurn.question(fromDraft: draft), !streaming, !waitingForDecision, !quotaReached else { return }
        streaming = true
        error = nil
        turn = Task {
            if conversationId == nil {
                do {
                    let created = try await repository.createConversation(title: ChatTurn.title(forQuestion: message))
                    conversationId = created.id
                    title = ChatTurn.title(forQuestion: message)
                } catch {
                    streaming = false
                    self.error = screenMessage(error)
                    quota = await repository.assistantQuota()
                    return
                }
            }
            draft = ""
            lines.append(.user(message))
            await runTurn(resumedLineId: nil)
        }
    }

    /// Approves or refuses a change the assistant prepared; the answer goes on once every change of
    /// the same answer is decided.
    func decide(_ approval: PendingApproval, in line: ChatLine, approved: Bool) {
        guard conversationId != nil, !streaming, let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let answered = lines[index].withDecision(approval, approved: approved)
        lines[index] = answered
        error = nil
        guard answered.approvals.isEmpty else { return }
        streaming = true
        turn = Task { await runTurn(resumedLineId: answered.id) }
    }

    /// Asks the server to stop, and stops reading 3 seconds later; what was received stays.
    func stop() {
        guard let conversationId else {
            turn?.cancel()
            return
        }
        guard let running = turn else { return }
        Task {
            try? await repository.stopConversation(conversationId)
            try? await Task.sleep(for: .seconds(3))
            running.cancel()
        }
    }

    private func runTurn(resumedLineId: String?) async {
        guard let conversationId else { return }
        let body = ChatTurn.requestBody(ChatTurn.history(lines, resumedLineId: resumedLineId))
        let reply = ChatLine.newReply()
        lines.append(reply)
        var builder = ReplyBuilder()
        do {
            let stream = try await repository.chatTurn(conversationId, body: body)
            reading: for try await raw in stream {
                switch SSELine.parse(raw) {
                case nil: continue
                case .done: break reading
                case .event(let event):
                    if let chatEvent = builder.accept(event) { apply(chatEvent, to: reply.id) }
                }
            }
            apply(.finished(parts: builder.parts), to: reply.id)
        } catch is CancellationError {
            // Stopped: what was received stays
        } catch {
            self.error = screenMessage(error) ?? String(localized: .errNetwork)
        }
        streaming = false
        working = false
        if let index = lines.firstIndex(where: { $0.id == reply.id }), !lines[index].hasText, lines[index].approvals.isEmpty {
            lines.remove(at: index)
        }
        turn = nil
        quota = await repository.assistantQuota()
        if quotaReached { error = nil }
    }

    private func apply(_ event: ChatEvent, to id: String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .textDelta(let delta):
            lines[index].text += delta
            working = false
        case .toolStarted:
            working = true
        case .approvalRequested(let approval):
            lines[index].approvals.append(approval)
            working = false
        case .finished(let parts):
            lines[index].parts = parts
        case .failed(let message):
            error = message.isEmpty ? String(localized: .errNetwork) : message
        }
    }
}
