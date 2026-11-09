import SwiftUI
import HumbleCore

/// The state of the sign-in screen and its steps.
@MainActor
@Observable
final class LoginModel {
    enum Step: Int { case credentials, twoFactor, passwordChange, twoFactorSetup }

    var serverURL: String
    var login: String
    var password = ""
    var remember: Bool
    var code = ""
    var backupCode = false
    var newPassword = ""
    var confirmation = ""
    private(set) var pendingToken = ""
    private(set) var step = Step.credentials
    /// Each forced setup starts again from its first stage.
    private(set) var setupAttempt = 0
    private(set) var loading = false
    var error: String?

    private let repository: Repository
    private let onDone: () -> Void

    init(repository: Repository, onDone: @escaping () -> Void) {
        self.repository = repository
        self.onDone = onDone
        serverURL = repository.savedServer
        login = repository.savedLogin
        remember = repository.savedRememberMe
        #if DEBUG
        // Development only: `-HPServer <url> -HPLogin <id> -HPPassword <password> -HPAutoSignIn YES`
        let arguments = UserDefaults.standard
        if let server = arguments.string(forKey: "HPServer") { serverURL = server }
        if let login = arguments.string(forKey: "HPLogin") { self.login = login }
        if let password = arguments.string(forKey: "HPPassword") { self.password = password }
        #endif
    }

    #if DEBUG
    private static var autoSignInUsed = false

    /// `-HPAutoSignIn YES` signs in once per launch: after a sign-out, the form waits.
    func takeAutoSignIn() -> Bool {
        guard UserDefaults.standard.bool(forKey: "HPAutoSignIn"), !Self.autoSignInUsed else { return false }
        Self.autoSignInUsed = true
        return true
    }
    #endif

    var codeComplete: Bool {
        backupCode ? !code.trimmingCharacters(in: .whitespaces).isEmpty : code.count == 6
    }

    func submit() {
        guard !loading else { return }
        switch step {
        case .credentials:
            run { await $0.login(server: self.serverURL, identifier: self.login, password: self.password, remember: self.remember) }
        case .twoFactor:
            guard codeComplete else { return }
            run { await $0.submitTwoFactor(pendingToken: self.pendingToken, code: self.code, isBackupCode: self.backupCode) }
        case .passwordChange:
            run { await $0.submitPasswordChange(self.newPassword, confirmation: self.confirmation) }
        case .twoFactorSetup:
            break
        }
    }

    func signIn(with qr: QRLogin) {
        guard !loading else { return }
        serverURL = qr.serverURL
        step = .credentials
        run { await $0.loginWithPairing(server: qr.serverURL, code: qr.code) }
    }

    func completeTwoFactorSetup() {
        run { await $0.completeSignIn() }
    }

    /// A sign-in stopped by the blocking screen goes on once it is gone.
    func resume() {
        guard repository.signInPending, !loading else { return }
        run { await $0.resumeSignIn() ?? .done }
    }

    func back() {
        if step == .passwordChange || step == .twoFactorSetup { repository.abandonSignIn() }
        step = .credentials
        password = ""
        code = ""
        backupCode = false
        newPassword = ""
        confirmation = ""
        error = nil
    }

    func toggleBackupCode() {
        backupCode.toggle()
        code = ""
    }

    private func run(_ action: @escaping (Repository) async -> SignInStep) {
        loading = true
        error = nil
        Task {
            let result = await action(repository)
            loading = false
            apply(result)
        }
    }

    private func apply(_ result: SignInStep) {
        switch result {
        case .done:
            password = ""
            code = ""
            newPassword = ""
            confirmation = ""
            onDone()
        case .twoFactor(let token):
            pendingToken = token
            code = ""
            password = ""
            backupCode = false
            step = .twoFactor
        case .passwordChange:
            password = ""
            setupAttempt += 1
            step = .passwordChange
        case .twoFactorSetup:
            password = ""
            newPassword = ""
            confirmation = ""
            setupAttempt += 1
            step = .twoFactorSetup
        case .failed(let failure):
            if step == .twoFactor { code = "" }
            error = Self.message(failure)
        }
    }

    static func message(_ error: SignInError) -> String? {
        switch error {
        case .urlRequired: String(localized: .errUrlRequired)
        case .httpsRequired: String(localized: .errHttps)
        case .invalidURL: String(localized: .errUrlInvalid)
        case .fieldsRequired: String(localized: .errFields)
        case .passwordLoginDisabled: String(localized: .errPasswordLoginDisabled)
        case .passwordMismatch: String(localized: .passwordMismatch)
        case .notHumblePlanning: String(localized: .errNotHumble)
        case .network: String(localized: .errNetwork)
        case .server(let message): message.isEmpty ? nil : message
        }
    }
}
