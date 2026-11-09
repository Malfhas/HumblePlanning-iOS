import SwiftUI
import HumbleCore

/// Above the whole app while the server refuses it: update required, maintenance (tried again every
/// 30 seconds), or the app no longer allowed for the account.
struct BlockingView: View {
    let state: BlockingState
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var retrying = false
    @State private var countdown = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .frame(width: 88, height: 88)
                    .glassEffect(.regular, in: .circle)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                controls.padding(.top, 32)
            }
            .frame(maxWidth: 480)
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 600)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground))
        .task(id: state) { await autoRetry() }
    }

    private var icon: String {
        switch state {
        case .upgradeRequired: "arrow.down.app"
        case .maintenance: "wrench.and.screwdriver"
        case .appNotAllowed: "nosign"
        }
    }

    private var title: String {
        switch state {
        case .upgradeRequired: String(localized: .updateTitle)
        case .maintenance: String(localized: .maintenanceTitle)
        case .appNotAllowed: String(localized: .notAllowedTitle)
        }
    }

    private var message: String {
        switch state {
        case .upgradeRequired(let minimum, _):
            String(localized: .updateText(AppInfo.version, minimum.isEmpty ? "?" : minimum))
        case .maintenance(let text): text.isEmpty ? String(localized: .maintenanceText) : text
        case .appNotAllowed(let text): text.isEmpty ? String(localized: .notAllowedText) : text
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            switch state {
            case .maintenance:
                ProgressButton(title: String(localized: .retry), loading: retrying) { retry() }
                ProgressView(value: Double(30 - countdown), total: 30)
                    .padding(.top, 4)
                Text(.maintenanceAuto(countdown))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            case .upgradeRequired(_, let store):
                ProgressButton(title: String(localized: .updateOpenStore), systemImage: "arrow.up.forward.app") {
                    openURL(storeURL(store))
                }
                SecondaryButton(title: String(localized: .retry), enabled: !retrying) { retry() }
            case .appNotAllowed:
                ProgressButton(title: String(localized: .retry), loading: retrying) { retry() }
                SecondaryButton(title: String(localized: .signOut)) { app.signOut() }
            }
        }
    }

    /// The page of the server when it is an App Store link, else the app's own page.
    private func storeURL(_ value: String) -> URL {
        let lower = value.lowercased()
        if lower.hasPrefix("itms-apps://") || lower.hasPrefix("https://apps.apple.com/"), let url = URL(string: value) { return url }
        return AppInfo.storeURL
    }

    private func retry() {
        guard !retrying else { return }
        retrying = true
        Task {
            _ = await app.repository.retryBlocked()
            retrying = false
            countdown = 30
        }
    }

    private func autoRetry() async {
        guard case .maintenance = state else { return }
        countdown = 30
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !retrying else { continue }
            countdown -= 1
            if countdown <= 0 { retry() }
        }
    }
}
