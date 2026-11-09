import Foundation

/// A step of the sign-in.
public enum SignInStep: Equatable, Sendable {
    case twoFactor(pendingToken: String)
    case passwordChange
    case twoFactorSetup
    case done
    case failed(SignInError)
}

public enum SignInError: Error, Equatable, Sendable {
    case urlRequired
    case httpsRequired
    case invalidURL
    case fieldsRequired
    case passwordLoginDisabled
    case passwordMismatch
    case notHumblePlanning
    case network
    /// The server's message (empty when the blocking screen already says it).
    case server(String)
}

extension Repository {
    /// The address and identifier filled in on the sign-in screen.
    public var savedServer: String { preferences.server ?? "https://" }
    public var savedLogin: String { preferences.lastLogin }
    public var savedRememberMe: Bool { preferences.rememberMe }

    private func normalized(_ input: String) -> Result<String, SignInError> {
        switch ServerURL.normalize(input) {
        case .ok(let url, _): .success(url)
        case .empty: .failure(.urlRequired)
        case .httpsRequired: .failure(.httpsRequired)
        case .invalid: .failure(.invalidURL)
        }
    }

    private func attempt(_ block: () async throws -> SignInStep) async -> SignInStep {
        // The sign-out of a previous account must be over before a new session exists
        await logoutTask?.value
        do {
            return try await block()
        } catch let error as APIError {
            switch error {
            case .notHumblePlanning: return .failed(.notHumblePlanning)
            case .network: return .failed(.network)
            case .upgradeRequired(let minimum, let store):
                blocking = .upgradeRequired(minimumVersion: minimum, storeURL: store)
                return .failed(.server(""))
            case .maintenance(let message):
                blocking = .maintenance(message)
                return .failed(.server(""))
            case .server(_, _, let message), .appNotAllowed(let message): return .failed(.server(message))
            case .unexpected, .sessionExpired: return .failed(.server(""))
            }
        } catch {
            return .failed(.network)
        }
    }

    public func login(server input: String, identifier: String, password: String, remember: Bool) async -> SignInStep {
        let server: String
        switch normalized(input) {
        case .success(let url): server = url
        case .failure(let error): return .failed(error)
        }
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, !password.isEmpty else { return .failed(.fieldsRequired) }
        return await attempt {
            let client = signInClient(server)
            guard try await client.info().loginEnabled else { return .failed(.passwordLoginDisabled) }
            pendingServer = server
            pendingRemember = remember
            pendingLogin = identifier
            return try await afterSignIn(client.login(identifier: identifier, password: password, device: device))
        }
    }

    public func submitTwoFactor(pendingToken: String, code: String, isBackupCode: Bool) async -> SignInStep {
        guard let server = pendingServer else { return .failed(.urlRequired) }
        return await attempt {
            try await afterSignIn(signInClient(server).loginTwoFactor(pendingToken: pendingToken, code: code, isBackupCode: isBackupCode, device: device))
        }
    }

    /// Signs in with the QR code of the web profile, once the person confirmed the server.
    public func loginWithPairing(server input: String, code: String) async -> SignInStep {
        let server: String
        switch normalized(input) {
        case .success(let url): server = url
        case .failure(let error): return .failed(error)
        }
        return await attempt {
            let client = signInClient(server)
            _ = try await client.info()
            pendingServer = server
            pendingRemember = preferences.rememberMe
            pendingLogin = preferences.lastLogin
            return try await afterSignIn(client.loginPairing(code: code, device: device))
        }
    }

    private func afterSignIn(_ response: MobileLoginResponse) async throws -> SignInStep {
        if response.status == "two_factor_required" { return .twoFactor(pendingToken: response.pendingToken ?? "") }
        guard let session = response.session else { throw APIError.unexpected("no session") }
        guard let server = pendingServer else { throw APIError.unexpected("no server") }
        if preferences.server != server || preferences.userId != session.userId { clearLocalData() }
        preferences.server = server
        saveSession(ServerSession(serverURL: server, cookieName: session.cookieName, cookieValue: session.cookieValue))
        preferences.userId = session.userId
        preferences.rememberMe = pendingRemember
        preferences.lastLogin = pendingRemember ? pendingLogin : ""
        sessionExpired = false
        pendingTwoFactorSetup = response.setupTwoFactorRequired
        if response.forcePasswordChange { return .passwordChange }
        if response.setupTwoFactorRequired { return .twoFactorSetup }
        return try await finishSignIn()
    }

    /// The new password required by an administrator, before anything else.
    public func submitPasswordChange(_ password: String, confirmation: String) async -> SignInStep {
        guard !password.trimmingCharacters(in: .whitespaces).isEmpty, password == confirmation else { return .failed(.passwordMismatch) }
        return await attempt {
            try await api().changeRequiredPassword(password)
            return pendingTwoFactorSetup ? .twoFactorSetup : try await finishSignIn()
        }
    }

    /// After the required steps: the first load, then the settings that follow the account.
    public func completeSignIn() async -> SignInStep {
        await attempt { try await finishSignIn() }
    }

    func finishSignIn() async throws -> SignInStep {
        signInPending = true
        try await loadReferences()
        signInPending = false
        let client = api()
        try? await client.setLocale(language)
        preferences.localeSent = language
        if let token = pushTokenProvider?() {
            try? await client.updateDevice(pushToken: token)
            preferences.pushTokenSent = token
        }
        // Alerts older than the sign-in are history, not news
        if let page = try? await client.alerts(after: ISO8601DateFormatter().string(from: Date())) {
            preferences.alertsAfter = page.serverTime
        }
        onForeground()
        tasksChanged += 1
        return .done
    }

    /// Goes on with a sign-in that the blocking screen interrupted.
    public func resumeSignIn() async -> SignInStep? {
        guard signInPending else { return nil }
        return await completeSignIn()
    }

    /// Leaving the required steps (password, second factor) closes the session that was opened.
    public func abandonSignIn() {
        logout()
    }

    /// The language changed in the settings of iOS: the server follows it.
    public func syncLanguage() {
        guard isLoggedIn, preferences.localeSent != language else { return }
        let language = language
        Task {
            try? await api().setLocale(language)
            preferences.localeSent = language
        }
    }

    // MARK: Sign-out

    /// Closes the session on the server (unless it already ended), then forgets the account's data.
    /// The screens leave at once; the server calls go on with a client that keeps the old session.
    public func logout() {
        if session != nil, !sessionExpired {
            let client = api()
            logoutTask = Task {
                try? await client.updateDevice(pushToken: nil)
                try? await client.logout()
            }
        }
        saveSession(nil)
        sessionExpired = false
        signInPending = false
        disconnectRealtime()
        let scheduler = reminderScheduler
        Task { await scheduler?.cancelAll() }
        clearLocalData()
        if !preferences.rememberMe {
            preferences.server = nil
            preferences.lastLogin = ""
        }
        references = References()
        blocking = nil
        try? FileManager.default.removeItem(at: Self.attachmentsDirectory)
    }

    func clearLocalData() {
        files.deleteAll()
        taskRange = nil
        preferences.clearAccountData()
    }
}
