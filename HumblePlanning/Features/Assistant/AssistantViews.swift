import SwiftUI
import HumbleCore

/// The conversations with the assistant of the server.
struct AssistantView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var conversations: [Conversation] = []
    @State private var quota: ChatQuota?
    @State private var loaded = false
    @State private var error: String?
    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var deleting: Conversation?

    var body: some View {
        List {
            if let error {
                Banner(text: error, tone: .error).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(conversations) { conversation in
                NavigationLink(value: ConversationRoute(id: conversation.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title.isEmpty ? String(localized: .assistantUntitled) : conversation.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(typeSize > .large ? nil : 2)
                        if let updated = conversation.updatedAt {
                            Text(RelativeDate.text(updated)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("assistant.conversation.\(conversation.id)")
                .swipeActions {
                    Button(String(localized: .delete), systemImage: "trash", role: .destructive) { deleting = conversation }
                    Button(String(localized: .assistantRename), systemImage: "pencil") { startRenaming(conversation) }
                }
                .contextMenu {
                    Button(String(localized: .assistantRename), systemImage: "pencil") { startRenaming(conversation) }
                    Button(String(localized: .delete), systemImage: "trash", role: .destructive) { deleting = conversation }
                }
            }
        }
        .overlay {
            if !loaded {
                ProgressView()
            } else if conversations.isEmpty && error == nil {
                EmptyState(systemImage: "sparkles", title: String(localized: .assistantEmpty), subtitle: String(localized: .assistantEmptyHelp))
            }
        }
        .navigationTitle(String(localized: .tabAssistant))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { QuotaGauge(quota: quota) }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: ConversationRoute(id: nil)) {
                    Label(String(localized: .assistantNew), systemImage: "square.and.pencil")
                }
                .buttonStyle(.glassProminent)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
        .onChange(of: app.repository.blocking) { _, blocking in if blocking == nil { Task { await load() } } }
        .alert(String(localized: .assistantRenameTitle), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: .assistantRenameLabel), text: Binding(get: { newTitle }, set: { newTitle = String($0.prefix(200)) }))
            Button(String(localized: .save)) { rename() }
                .disabled(!renameValid)
            Button(String(localized: .cancel), role: .cancel) {}
        }
        .alert(String(localized: .assistantDeleteTitle), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { conversation in
            Button(String(localized: .delete), role: .destructive) { delete(conversation) }
            Button(String(localized: .cancel), role: .cancel) {}
        } message: { conversation in
            Text(conversation.title.isEmpty ? String(localized: .assistantUntitled) : conversation.title)
        }
    }

    private var renameValid: Bool {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title != renaming?.title
    }

    private func load() async {
        do {
            conversations = try await app.repository.conversations()
            error = nil
        } catch {
            self.error = screenMessage(error)
        }
        quota = await app.repository.assistantQuota()
        loaded = true
    }

    private func startRenaming(_ conversation: Conversation) {
        newTitle = conversation.title
        renaming = conversation
    }

    private func rename() {
        guard let conversation = renaming, renameValid else { return }
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let saved = try await app.repository.renameConversation(conversation.id, title: title)
                if let index = conversations.firstIndex(where: { $0.id == conversation.id }) { conversations[index].title = saved }
            } catch {
                self.error = screenMessage(error)
            }
        }
    }

    private func delete(_ conversation: Conversation) {
        Task {
            do {
                try await app.repository.deleteConversation(conversation.id)
                conversations.removeAll { $0.id == conversation.id }
            } catch {
                self.error = screenMessage(error)
            }
        }
    }
}

struct ConversationRoute: Hashable {
    let id: String?
}

/// A conversation: the answer arrives as it is written; every change waits for approval.
struct ConversationView: View {
    @State private var model: ConversationModel
    @FocusState private var focused: Bool

    init(model: ConversationModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.lines) { line in
                        ChatBubble(line: line, streaming: model.streaming) { approval, approved in
                            model.decide(approval, in: line, approved: approved)
                        }
                        .id(line.id)
                    }
                    if model.working {
                        Label(String(localized: .assistantWorking), systemImage: "wrench.and.screwdriver")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay { placeholder }
            .onChange(of: model.lines.last?.text.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.lines.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: model.working) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .safeAreaBar(edge: .bottom) { inputBar }
        .navigationTitle(model.title ?? String(localized: .assistantNew))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { QuotaGauge(quota: model.quota) } }
        .task { await model.load() }
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.loading {
            ProgressView()
        } else if let error = model.loadError {
            EmptyState(systemImage: "exclamationmark.triangle", title: error) {
                Button(String(localized: .retry)) { Task { await model.load() } }.buttonStyle(.glass)
            }
        } else if model.lines.isEmpty {
            EmptyState(systemImage: "sparkles", title: String(localized: .assistantHello), subtitle: String(localized: .assistantHelloHelp))
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let error = model.error { Banner(text: error, tone: .error) }
            if model.waitingForDecision {
                Text(.assistantDecideFirst).font(.footnote).foregroundStyle(.secondary)
            }
            if model.quotaReached && !model.streaming {
                Banner(text: String(localized: .assistantQuotaReached(Self.date(model.quota?.resetsAt))), tone: .warning)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(String(localized: .assistantPlaceholder), text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.sentences)
                        .focused($focused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        .disabled(model.waitingForDecision || model.loadError != nil)
                        .accessibilityIdentifier("assistant.input")
                    if model.streaming {
                        Button(action: model.stop) {
                            Image(systemName: "stop.fill").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel(String(localized: .assistantStop))
                    } else {
                        Button(action: model.send) {
                            Image(systemName: "arrow.up").font(.headline).frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .disabled(!model.canSend)
                        .accessibilityLabel(String(localized: .assistantSend))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The reset date of the quota, in the device's time zone.
    static func date(_ iso: String?) -> String {
        guard let iso, let date = RelativeDate.parse(iso) else { return "" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// A question, or an answer with its changes to approve.
private struct ChatBubble: View {
    let line: ChatLine
    let streaming: Bool
    let decide: (PendingApproval, Bool) -> Void

    var body: some View {
        VStack(alignment: line.fromUser ? .trailing : .leading, spacing: 8) {
            if line.hasText {
                Group {
                    if line.fromUser {
                        Text(line.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: .rect(cornerRadius: 20))
                    } else {
                        MarkdownText(text: line.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 560, alignment: line.fromUser ? .trailing : .leading)
                // One element per message, saying who wrote it
                .accessibilityElement(children: .combine)
                .accessibilityLabel { label in
                    Text(line.fromUser ? String(localized: .a11YYou) : String(localized: .tabAssistant))
                    label
                }
            }
            ForEach(line.approvals) { approval in
                ApprovalCard(approval: approval, enabled: !streaming) { decide(approval, $0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: line.fromUser ? .trailing : .leading)
    }
}

private struct ApprovalCard: View {
    let approval: PendingApproval
    let enabled: Bool
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // What is asked, read as one element before the two answers
            VStack(alignment: .leading, spacing: 10) {
                Text(.assistantConfirmTitle).font(.caption).foregroundStyle(.secondary)
                Label(approval.readableToolName, systemImage: "pencil.and.list.clipboard").font(.headline)
                if let input = approval.readableInput {
                    Text(input)
                        .font(.footnote.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                }
            }
            .accessibilityElement(children: .combine)
            HStack {
                Button(String(localized: .assistantRefuse), role: .cancel) { decide(false) }
                    .buttonStyle(.glass)
                Spacer()
                Button(String(localized: .assistantApprove), systemImage: "checkmark") { decide(true) }
                    .buttonStyle(.glassProminent)
            }
            .disabled(!enabled)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.accentColor.opacity(0.4)))
        .frame(maxWidth: 560, alignment: .leading)
    }
}

/// The Markdown of the assistant: headings, bullets, bold and code.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Markdown.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let inlines):
                    Text(Self.attributed(inlines)).font(level <= 1 ? .title3.weight(.semibold) : .headline)
                case .bullet(let inlines):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(Self.attributed(inlines))
                    }
                case .paragraph(let inlines):
                    Text(Self.attributed(inlines))
                }
            }
        }
    }

    static func attributed(_ inlines: [MarkdownInline]) -> AttributedString {
        inlines.reduce(into: AttributedString()) { result, inline in
            var run = AttributedString(inline.content)
            switch inline {
            case .text: break
            case .bold: run.inlinePresentationIntent = .stronglyEmphasized
            case .code:
                run.font = .body.monospaced()
                run.backgroundColor = Color(.tertiarySystemFill)
            }
            result += run
        }
    }
}

/// The monthly quota of the assistant, as on the web: a ring that fills up.
struct QuotaGauge: View {
    let quota: ChatQuota?
    @State private var showsDetails = false

    var body: some View {
        if let quota, quota.enabled {
            Button { showsDetails = true } label: {
                ZStack {
                    Circle().stroke(Color(.separator), lineWidth: 2.5)
                    if !quota.unlimited {
                        if quota.percent >= 100 { Circle().fill(Palette.danger.opacity(0.22)) }
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(quota.percent, 0), 100)) / 100)
                            .stroke(color(quota), style: StrokeStyle(lineWidth: 2.5, lineCap: quota.percent >= 100 ? .butt : .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .accessibilityLabel(details(quota).replacingOccurrences(of: "\n", with: " · "))
            .popover(isPresented: $showsDetails) {
                Text(details(quota))
                    .font(.footnote)
                    .padding()
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func color(_ quota: ChatQuota) -> Color {
        switch quota.level {
        case .success: Color(hex: 0x16A34A)
        case .warning: Color(hex: 0xF59E0B)
        case .danger: Palette.danger
        }
    }

    private func details(_ quota: ChatQuota) -> String {
        if quota.unlimited { return String(localized: .assistantQuotaUnlimited) }
        return String(localized: .assistantQuotaUsed(quota.percent)) + "\n" + String(localized: .assistantQuotaReset(ConversationView.date(quota.resetsAt)))
    }
}
