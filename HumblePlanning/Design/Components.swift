import SwiftUI
import HumbleCore

/// A message above a form or a list.
struct Banner: View {
    enum Tone { case info, warning, error }

    let text: String
    var tone: Tone = .info
    var systemImage: String?

    private var accent: Color {
        switch tone {
        case .info: .secondary
        case .warning: Palette.warning
        case .error: Palette.danger
        }
    }

    private var icon: String {
        systemImage ?? (tone == .info ? "info.circle" : tone == .warning ? "exclamationmark.triangle" : "exclamationmark.circle")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(tone == .info ? .secondary : accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

/// The banner of data read from the phone.
struct OfflineBanner: View {
    let since: Date?

    var body: some View {
        if let since {
            Banner(text: String(localized: .offlineSince(since.formatted(date: .numeric, time: .shortened))), tone: .warning, systemImage: "icloud.slash")
        } else {
            Banner(text: String(localized: .offline), tone: .warning, systemImage: "icloud.slash")
        }
    }
}

/// A full-width button that shows a spinner while its action runs.
struct ProgressButton: View {
    let title: String
    var systemImage: String?
    var loading = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .opacity(loading ? 0 : 1)
                if loading { ProgressView() }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(loading || !enabled)
    }
}

/// A secondary full-width button.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(!enabled)
    }
}

/// The initials of a person on their colour, then their photo once loaded.
struct UserAvatar: View {
    let user: User
    var size: CGFloat = 32
    @Environment(AppModel.self) private var app
    /// Grows with the text size, up to 1.75 times, like the avatars of the system apps.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let background = Color(serverHex: user.color) ?? Color(.secondarySystemFill)
        let size = size * min(scale, 1.75)
        ZStack {
            Circle().fill(background)
            Text(Self.initials(user.displayName))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(user.color == nil ? Color.primary : (contentIsDark(user.color) ? Palette.darkText : .white))
            if let url = avatarURL(server: app.repository.session?.serverURL ?? "", image: user.image) {
                RemoteImage(url: url)
                    .clipShape(.circle)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
        .accessibilityHidden(true)
    }

    /// First letter or digit of the first two words.
    static func initials(_ name: String) -> String {
        name.split(whereSeparator: { $0 == " " || $0 == "-" })
            .prefix(2)
            .compactMap { $0.first { $0.isLetter || $0.isNumber } }
            .map { String($0).uppercased() }
            .joined()
    }
}

/// Text on a colour of the server: dark on light colours, white otherwise.
func contentIsDark(_ hex: String?) -> Bool {
    RGBColor(hex: hex)?.contentColorIsDark ?? false
}

/// An image of the server, read with the session and kept in memory.
struct RemoteImage: View {
    let url: URL
    @Environment(AppModel.self) private var app
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: url) { image = await app.images.image(url, repository: app.repository) }
    }
}

/// A centred icon, title and explanation, for empty lists and errors.
struct EmptyState<Action: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    @ViewBuilder var action: Action

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let subtitle { Text(subtitle) }
        } actions: {
            action
        }
    }
}

extension EmptyState where Action == EmptyView {
    init(systemImage: String, title: String, subtitle: String? = nil) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension APIError {
    /// The text a screen shows for this error (nil for the blocking ones: the overlay says it).
    var screenMessage: String? {
        switch self {
        case .network: String(localized: .errNetwork)
        case .sessionExpired: String(localized: .errSession)
        case .notHumblePlanning: String(localized: .errNotHumble)
        case .unexpected: String(localized: .errUnexpected)
        case .upgradeRequired, .maintenance, .appNotAllowed: nil
        case .server(_, _, let message): message.isEmpty ? String(localized: .errUnexpected) : message
        }
    }
}

/// The text of any error of a screen.
func screenMessage(_ error: any Error) -> String? {
    if error is CancellationError { return nil }
    if let error = error as? APIError { return error.screenMessage }
    return String(localized: .errUnexpected)
}
