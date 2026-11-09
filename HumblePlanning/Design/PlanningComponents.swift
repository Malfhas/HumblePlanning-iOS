import SwiftUI
import HumbleCore

/// A colour of the server as a small dot (grey when it has none).
struct ColorDot: View {
    let hex: String?
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Color(serverHex: hex) ?? Color(.separator))
            .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
            .frame(width: size, height: size)
    }
}

/// The status of a task: a neutral pill with its colour dot.
struct StatusChip: View {
    let status: TaskStatus

    var body: some View {
        HStack(spacing: 6) {
            ColorDot(hex: status.color, size: 8)
            Text(status.name).lineLimit(2)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }
}

/// Side by side, or one under the other with the accessibility text sizes, where a line has no room left.
struct AdaptiveStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}

/// "Holiday" with its label, under a day title.
struct HolidayLabel: View {
    let holiday: Holiday

    var body: some View {
        Label(holiday.shownLabel ?? String(localized: .holiday), systemImage: "party.popper")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            // The icon says "holiday" on screen: VoiceOver says it in words
            .accessibilityLabel([String(localized: .holiday), holiday.shownLabel].compactMap { $0 }.joined(separator: ", "))
    }
}

extension Text {
    /// Bold, italic, struck or underlined as the status asks.
    func styled(by status: TaskStatus?) -> Text {
        guard let status else { return self }
        var text = self
        if status.bold { text = text.bold() }
        if status.italic { text = text.italic() }
        if status.strikethrough { text = text.strikethrough() }
        if status.underline { text = text.underline() }
        return text
    }
}

/// One task in a list: project colour, title, time and place, people and status.
struct TaskCard: View {
    let task: PlanningTask
    /// The day the card is shown for: a task over several days says which of its days it is.
    var day: CalendarDay?
    var compact = false
    var showsPeople = false
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("card_title") private var cardTitle = "project"

    private var references: References { app.repository.references }
    private var mode: CardTitleMode { CardTitleMode(rawValue: cardTitle) ?? .project }

    var body: some View {
        let status = task.statusOf(references)
        let subtitle = task.cardSubtitle(references, mode: mode)
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(serverHex: task.projectOf(references)?.color) ?? Color(.separator))
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(task.cardTitle(references, mode: mode))
                        .styled(by: status)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : typeSize > .large ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // The markers after the title, as on the web: the milestone last
                    Group {
                        if task.isLocked { Image(systemName: "lock.fill").accessibilityLabel(String(localized: .a11YLocked)) }
                        if task.isRecurring { Image(systemName: "repeat").accessibilityLabel(String(localized: .a11YRecurring)) }
                        if task.hasAttachments { Image(systemName: "paperclip").accessibilityLabel(String(localized: .a11YAttachments)) }
                        if task.hasNotes { Image(systemName: "text.alignleft").accessibilityLabel(String(localized: .a11YNotes)) }
                        if task.isMilestone {
                            Image(systemName: "flag.fill").foregroundStyle(Palette.danger).accessibilityLabel(String(localized: .milestone))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if !compact, !subtitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                }
                // Side by side when they fit, else one under the other, wrapping
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { meta.lineLimit(1) }
                    VStack(alignment: .leading, spacing: 4) { meta.lineLimit(lines) }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
                if (showsPeople && !task.users.isEmpty) || status != nil {
                    AdaptiveStack(spacing: 8) {
                        if showsPeople && !task.users.isEmpty { PeopleStack(users: task.users) }
                        if let status { StatusChip(status: status) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 10 : 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.5)))
        .contentShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    /// Two lines each, as many as needed with the accessibility sizes.
    private var lines: Int? { typeSize.isAccessibilitySize ? nil : 2 }

    /// Time (and which day of the task) and place.
    @ViewBuilder private var meta: some View {
        Label(timeLabel, systemImage: "clock").accessibilityLabel(spokenTimeLabel)
        if let place = task.placeLabel {
            Label(place, systemImage: "mappin.and.ellipse")
        }
    }

    private var timeLabel: String {
        var label = task.timeRange ?? String(localized: .allDay)
        if let day, let position = task.dayPosition(on: day) {
            label += " · " + String(localized: .dayXOfY(position.index, position.total))
        }
        return label
    }

    /// "day 2 of 3" rather than "2/3", which VoiceOver reads as a fraction.
    private var spokenTimeLabel: String {
        var label = task.timeRange ?? String(localized: .allDay)
        if let day, let position = task.dayPosition(on: day) {
            label += ", " + String(localized: .a11YDayXOfY(position.index, position.total))
        }
        return label
    }
}

/// Icon and text with a small gap, for the meta line of a card.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// One person with their name, or up to three overlapping avatars and "+N".
struct PeopleStack: View {
    let users: [User]

    var body: some View {
        Group {
            if users.count == 1, let user = users.first {
                HStack(spacing: 6) {
                    UserAvatar(user: user, size: 20)
                    Text(user.displayName).font(.caption.weight(.medium)).lineLimit(1)
                }
            } else {
                HStack(spacing: -6) {
                    ForEach(users.prefix(3)) { UserAvatar(user: $0, size: 22) }
                    if users.count > 3 {
                        Text("+\(users.count - 3)").font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.leading, 10)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(users.map(\.displayName).joined(separator: ", "))
    }
}

/// How the task form opens.
enum TaskFormRoute: Identifiable, Hashable {
    case create(date: CalendarDay?, userId: String?)
    case edit(id: String)
    case duplicate(id: String)

    var id: String {
        switch self {
        case .create(let date, let userId): "create-\(date?.iso ?? "")-\(userId ?? "")"
        case .edit(let id): "edit-\(id)"
        case .duplicate(let id): "duplicate-\(id)"
        }
    }
}
