import SwiftUI
import HumbleCore

/// Sign-in or the main screen, the blocking screen above everything, and the confirmation of
/// sign-in links.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let repository = app.repository
        ZStack {
            if app.showsMain {
                MainTabs()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
            if let blocking = repository.blocking {
                BlockingView(state: blocking)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: repository.blocking)
        .animation(.easeInOut(duration: 0.25), value: app.showsMain)
        .onChange(of: repository.sessionExpired) { _, expired in
            guard expired else { return }
            app.signOut()
            app.expiredNotice = true
        }
        .alert(String(localized: .qrInvalidTitle), isPresented: invalidLink) {
            Button(String(localized: .close), role: .cancel) { app.qrLogin = nil }
        } message: {
            Text(.qrInvalidText)
        }
        .alert(String(localized: .qrConfirmTitle), isPresented: validLink) {
            Button(String(localized: .signIn)) { confirmLink() }
            Button(String(localized: .cancel), role: .cancel) { app.qrLogin = nil }
        } message: {
            if let host = app.qrLogin.flatMap({ ServerURL.hostOf($0.serverURL) }) {
                Text(confirmationText(host: host, signedIn: repository.isLoggedIn))
            }
        }
    }

    private var invalidLink: Binding<Bool> {
        Binding(get: { app.qrLogin != nil && ServerURL.hostOf(app.qrLogin!.serverURL) == nil },
                set: { if !$0 { app.qrLogin = nil } })
    }

    private var validLink: Binding<Bool> {
        Binding(get: { app.qrLogin.flatMap { ServerURL.hostOf($0.serverURL) } != nil },
                set: { if !$0 { app.qrLogin = nil } })
    }

    private func confirmationText(host: String, signedIn: Bool) -> String {
        var text = String(localized: .qrConfirmText) + "\n" + host
        if signedIn { text += "\n\n" + String(localized: .qrConfirmSignedIn) }
        return text + "\n\n" + String(localized: .qrConfirmWarning)
    }

    /// Nothing reaches the server of a link before this confirmation.
    private func confirmLink() {
        guard let login = app.qrLogin else { return }
        app.qrLogin = nil
        if app.repository.isLoggedIn { app.signOut() }
        app.confirmedQR = login
    }
}
