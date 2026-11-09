import Foundation
import Observation

/// The only entry point of the screens: the session, the reference data, every call to the server
/// with its effects on the whole app (offline banner, blocking screen, end of session), the offline
/// copy, alerts and reminders.
@MainActor
@Observable
public final class Repository {
    // MARK: State observed by the screens

    public internal(set) var references: References
    /// Bumped when tasks may have changed (a write, real time, network back, blocking cleared).
    public internal(set) var tasksChanged = 0
    /// Bumped when new alerts arrived, or the blocking screen cleared.
    public internal(set) var alertsChanged = 0
    /// Bumped after every planning of the reminders, done or failed: their count and state may have changed.
    public internal(set) var remindersChanged = 0
    public internal(set) var offline = false
    public internal(set) var blocking: BlockingState?
    /// The server ended the session: the screens sign out and say so.
    public internal(set) var sessionExpired = false
    /// Sign-in opened the session but its first load was stopped by the blocking screen.
    public internal(set) var signInPending = false
    public internal(set) var session: ServerSession?

    public var isLoggedIn: Bool { session != nil }
    public var userId: String { references.user.id.isEmpty ? (preferences.userId ?? "") : references.user.id }
    public var access: Access { Access(references) }

    // MARK: Dependencies

    public let preferences: Preferences
    let sessions: SessionStore
    let files: EncryptedFiles
    let transport: Transport
    let deviceName: String
    public var reminderScheduler: (any ReminderScheduling)?
    public var alertPresenter: (any AlertPresenting)?
    /// The token of this device for push, when the server can use it.
    public var pushTokenProvider: (@MainActor () -> String?)?

    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored let realtime = RealtimeClient()
    /// Connections and disconnections of the real time, one after the other in the order asked.
    @ObservationIgnored private var realtimeQueue: Task<Void, Never>?
    @ObservationIgnored var logoutTask: Task<Void, Never>?
    @ObservationIgnored var taskRange: (start: String, end: String, serverTime: String, tasks: [String: PlanningTask])?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    // Sign-in in progress
    @ObservationIgnored var pendingServer: String?
    @ObservationIgnored var pendingRemember = true
    @ObservationIgnored var pendingLogin = ""
    @ObservationIgnored var pendingTwoFactorSetup = false

    public init(preferences: Preferences, secrets: any SecretStore, files: EncryptedFiles, deviceName: String, transport: Transport = .shared) {
        self.preferences = preferences
        sessions = SessionStore(secrets: secrets)
        self.files = files
        self.transport = transport
        self.deviceName = deviceName
        session = sessions.load()
        references = files.read(References.self, .references) ?? References()
        let events = realtime.events()
        Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
    }

    // MARK: Calls

    var language: String { AppLanguage.effective }

    var device: DeviceInfo {
        DeviceInfo(name: String(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)), locale: language)
    }

    /// The client of the signed-in server.
    func api() -> APIClient {
        if let client, client.currentSession == session, let session, client.baseURL == session.serverURL { return client }
        let new = APIClient(
            baseURL: session?.serverURL ?? preferences.server ?? "", session: session, transport: transport,
            language: { AppLanguage.effective },
            onSessionExpired: { [weak self] in Task { @MainActor in self?.markSessionExpired() } },
            onSessionRefreshed: { [weak self] updated in Task { @MainActor in self?.sessionRefreshed(updated) } }
        )
        client = new
        return new
    }

    /// A client for a server being tried at sign-in, without session.
    func signInClient(_ server: String) -> APIClient {
        APIClient(baseURL: server, session: nil, transport: transport, language: { AppLanguage.effective })
    }

    /// Every authenticated call: a success clears the offline state and the blocking screen; a refusal
    /// of the whole app shows the blocking screen; a network failure shows the offline state.
    public func call<T>(_ block: (APIClient) async throws -> T) async throws -> T {
        do {
            let result = try await block(api())
            blocking = nil
            offline = false
            return result
        } catch let error as APIError {
            switch error {
            case .network: offline = true
            case .upgradeRequired(let minimum, let store): blocking = .upgradeRequired(minimumVersion: minimum, storeURL: store)
            case .maintenance(let message): blocking = .maintenance(message)
            case .appNotAllowed(let message): if isLoggedIn { blocking = .appNotAllowed(message) }
            default: break
            }
            throw error
        }
    }

    private func markSessionExpired() {
        if isLoggedIn { sessionExpired = true }
    }

    private func sessionRefreshed(_ updated: ServerSession) {
        guard session?.serverURL == updated.serverURL, session?.cookieName == updated.cookieName else { return }
        session = updated
        sessions.save(updated)
        reconnectRealtime()
    }

    func saveSession(_ new: ServerSession?) {
        session = new
        sessions.save(new)
        client = nil
    }

    // MARK: Reference data

    public func loadReferences() async throws {
        let boot = try await call { try await $0.bootstrap() }
        let loaded = References(boot)
        preferences.userName = loaded.user.displayName
        references = loaded
        try? files.write(loaded, .references)
    }

    func replaceUser(_ user: User) {
        references.user = user
        preferences.userName = user.displayName
        try? files.write(references, .references)
    }

    // MARK: Changes

    func tasksDidChange() { tasksChanged += 1 }

    /// Several changes within 400 ms make one reload.
    func remoteTasksChanged() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.tasksChanged += 1
        }
    }

    // MARK: Blocking screen

    /// Asks the server again; true when the blocking screen is gone.
    public func retryBlocked() async -> Bool {
        do {
            if isLoggedIn {
                _ = try await call { try await $0.profile() }
            } else if let server = pendingServer ?? preferences.server {
                let info = try await signInClient(server).info()
                if !info.maintenance && !AppInfo.isOlder(AppInfo.version, than: info.minimumAppVersion) { blocking = nil }
            }
        } catch {
            return false
        }
        guard blocking == nil else { return false }
        tasksChanged += 1
        alertsChanged += 1
        return true
    }

    // MARK: Network and foreground

    public func networkChanged(available: Bool) {
        transport.networkChanged()
        if !available {
            offline = true
            return
        }
        reconnectRealtime()
        if offline {
            offline = false
            if isLoggedIn { tasksChanged += 1 }
        }
    }

    public func onForeground() {
        connectRealtime()
        guard isLoggedIn else { return }
        Task { try? await syncAlerts(notify: false) }
    }

    public func onBackground() {
        disconnectRealtime()
    }

    // MARK: Real time

    private var realtimeCredentials: RealtimeCredentials? {
        guard let session, let url = URL(string: session.serverURL) else { return nil }
        return RealtimeCredentials(serverURL: url, cookieName: session.cookieName, cookieValue: session.cookieValue, language: language)
    }

    private func enqueueRealtime(_ work: @escaping @Sendable (RealtimeClient) async -> Void) {
        let previous = realtimeQueue
        let realtime = realtime
        realtimeQueue = Task {
            await previous?.value
            await work(realtime)
        }
    }

    func connectRealtime() {
        guard let credentials = realtimeCredentials else { return }
        enqueueRealtime { await $0.connect(credentials) }
    }

    /// Only when the real time is wanted (app in the foreground).
    func reconnectRealtime() {
        guard let credentials = realtimeCredentials else { return }
        enqueueRealtime { await $0.reconnect(credentials) }
    }

    func disconnectRealtime() {
        enqueueRealtime { await $0.disconnect() }
    }

    private func handle(_ event: RealtimeEvent) {
        guard isLoggedIn else { return }
        switch event {
        case .connected, .taskChanged:
            // Catches up with the changes made while disconnected
            remoteTasksChanged()
        case .invalidSession, .sessionRevoked:
            // Sent to every session of the user when one ends: only a refusal of this one ends it
            let client = api()
            Task { _ = try? await client.profile() }
        case .permissionsChanged, .assistantAvailability:
            Task { try? await loadReferences() }
        case .mobileAlert:
            Task { try? await syncAlerts(notify: false) }
        case .refused, .disconnected:
            break
        }
    }
}
