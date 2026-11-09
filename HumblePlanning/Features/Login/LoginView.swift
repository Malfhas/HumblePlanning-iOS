import SwiftUI
import HumbleCore

/// Sign-in to a server: password and second factor, or the QR code of the web profile.
struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var model: LoginModel?
    @State private var scanning = false

    var body: some View {
        Group {
            if let model {
                LoginForm(model: model, scanning: $scanning)
            } else {
                Color.clear
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if model == nil {
                model = LoginModel(repository: app.repository) { [app] in
                    app.expiredNotice = false
                    app.showsMain = true
                }
                #if DEBUG
                if app.confirmedQR == nil, model?.takeAutoSignIn() == true { model?.submit() }
                #endif
            }
            // A link confirmed while signed in comes with this screen, before onChange watches it
            signInWithConfirmedLink()
        }
        .onChange(of: app.confirmedQR) { signInWithConfirmedLink() }
        .onChange(of: app.repository.blocking) { _, blocking in
            if blocking == nil { model?.resume() }
        }
        .fullScreenCover(isPresented: $scanning) {
            ScannerView { link in
                scanning = false
                app.handle(link)
            }
        }
    }

    private func signInWithConfirmedLink() {
        guard let login = app.confirmedQR, let model else { return }
        app.confirmedQR = nil
        app.expiredNotice = false
        model.signIn(with: login)
    }
}

private struct LoginForm: View {
    @Bindable var model: LoginModel
    @Binding var scanning: Bool
    @Environment(AppModel.self) private var app
    @FocusState private var focus: Field?
    @State private var showsPassword = false

    enum Field { case server, login, password, code, newPassword, confirmation }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(.logoMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .padding(.top, 32)
                    .accessibilityHidden(true)
                Text(verbatim: "Humble Planning")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                VStack(spacing: 14) {
                    if app.expiredNotice {
                        Banner(text: String(localized: .errSession), tone: .warning).accessibilityIdentifier("login.notice")
                    }
                    if let error = model.error { Banner(text: error, tone: .error).accessibilityIdentifier("login.error") }
                    step
                }
                .frame(maxWidth: 460)
                .padding(.top, 28)
                .animation(.snappy, value: model.step)
                Spacer(minLength: 24)
                Text(.version(AppInfo.version))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: model.serverURL) { app.expiredNotice = false; model.error = nil }
        .onChange(of: model.login) { app.expiredNotice = false; model.error = nil }
        .onChange(of: model.password) { if !model.password.isEmpty { app.expiredNotice = false; model.error = nil } }
    }

    private var subtitle: String {
        switch model.step {
        case .credentials: String(localized: .loginSubtitle)
        case .twoFactor: String(localized: .twoFactorSubtitle)
        case .passwordChange: String(localized: .passwordChangeRequired)
        case .twoFactorSetup: String(localized: .twoFactorSetupRequired)
        }
    }

    @ViewBuilder
    private var step: some View {
        switch model.step {
        case .credentials: credentials
        case .twoFactor: twoFactor
        case .passwordChange: passwordChange
        case .twoFactorSetup:
            TwoFactorSetupFlow(finishing: model.loading, onFinished: model.completeTwoFactorSetup)
                .id(model.setupAttempt)
            Button(String(localized: .cancel)) { model.back() }
        }
    }

    private var credentials: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                FieldRow(systemImage: "server.rack") {
                    TextField(String(localized: .loginServer), text: $model.serverURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .focused($focus, equals: .server)
                        .accessibilityIdentifier("login.server")
                        .submitLabel(.next)
                        .onSubmit { focus = .login }
                }
                Divider().padding(.leading, 44)
                FieldRow(systemImage: "person") {
                    TextField(String(localized: .loginIdentifier), text: $model.login)
                        .textContentType(.username)
                        .focused($focus, equals: .login)
                        .accessibilityIdentifier("login.identifier")
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                Divider().padding(.leading, 44)
                FieldRow(systemImage: "lock") {
                    Group {
                        if showsPassword {
                            TextField(String(localized: .loginPassword), text: $model.password)
                        } else {
                            SecureField(String(localized: .loginPassword), text: $model.password)
                        }
                    }
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .accessibilityIdentifier("login.password")
                    .submitLabel(.go)
                    .onSubmit { model.submit() }
                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: .loginShowPassword))
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            Toggle(String(localized: .loginRemember), isOn: $model.remember)
                .padding(.horizontal, 4)
            ProgressButton(title: String(localized: .signIn), loading: model.loading) {
                focus = nil
                model.submit()
            }
            .accessibilityIdentifier("login.signIn")
            HStack {
                VStack { Divider() }
                Text(.or).font(.footnote).foregroundStyle(.secondary)
                VStack { Divider() }
            }
            SecondaryButton(title: String(localized: .loginQr), systemImage: "qrcode.viewfinder", enabled: !model.loading) {
                scanning = true
            }
            Text(.loginQrHelp)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var twoFactor: some View {
        VStack(spacing: 14) {
            Text(model.backupCode ? String(localized: .twoFactorBackupText) : String(localized: .twoFactorText))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            Group {
                if model.backupCode {
                    TextField("ABCD-1234", text: $model.code)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: model.code) { model.code = String(model.code.prefix(20)) }
                } else {
                    TextField(String(localized: .twoFactorCode), text: $model.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .tracking(8)
                        .onChange(of: model.code) { model.code = String(model.code.filter(\.isNumber).prefix(6)) }
                }
            }
            .autocorrectionDisabled()
            .multilineTextAlignment(.center)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .focused($focus, equals: .code)
            .accessibilityIdentifier("login.code")
            .onSubmit { model.submit() }
            ProgressButton(title: String(localized: .twoFactorVerify), loading: model.loading, enabled: model.codeComplete) { model.submit() }
            Button(model.backupCode ? String(localized: .twoFactorUseApp) : String(localized: .twoFactorUseBackup)) {
                model.toggleBackupCode()
                focus = .code
            }
            Button(String(localized: .back), systemImage: "chevron.backward") { model.back() }
        }
        .onAppear { focus = .code }
    }

    private var passwordChange: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                FieldRow(systemImage: "lock") {
                    SecureField(String(localized: .passwordNew), text: $model.newPassword)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .newPassword)
                        .onSubmit { focus = .confirmation }
                }
                Divider().padding(.leading, 44)
                FieldRow(systemImage: "lock") {
                    SecureField(String(localized: .passwordConfirm), text: $model.confirmation)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirmation)
                        .onSubmit { model.submit() }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            ProgressButton(title: String(localized: .passwordChange), loading: model.loading) { model.submit() }
            Button(String(localized: .cancel)) { model.back() }
        }
    }
}

/// An icon and a field, in a grouped box.
struct FieldRow<Content: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
    }
}
