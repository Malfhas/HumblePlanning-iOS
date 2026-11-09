import Foundation
import Synchronization
import Testing
@testable import HumbleCore

final class RecordingAlerts: AlertPresenting {
    let shown = Mutex<[String]>([])
    func show(_ alert: MobileAlert) async { shown.withLock { $0.append(alert.id) } }
}

extension StubbedTests {
    @MainActor
    @Suite
    struct RepositoryTests {
        let directory = FileManager.default.temporaryDirectory.appending(path: "hp-repo-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "hp-repo-\(UUID().uuidString)")!

        func repository() -> Repository {
            let secrets = MemorySecretStore()
            return Repository(preferences: Preferences(defaults: defaults), secrets: secrets,
                              files: EncryptedFiles(directory: directory, secrets: secrets), deviceName: "iPhone",
                              transport: Transport(protocolClasses: [StubProtocol.self]))
        }

        static let bootstrap = #"""
        {"user":{"id":"me","name":"Turner","firstName":"Liam","teamId":"t1"},"permissions":["tasks:create","scope:modify_own"],
         "isAdmin":false,"config":{"AM_START":"07:30","MODULE_PLACES":"false"},"assistant":{"available":true},
         "projects":[{"id":"p2","name":"b","group":{"id":"g","name":"G","sortOrder":2}},{"id":"p1","name":"A"},{"id":"p3","name":"old","status":"archived"}],
         "statuses":[{"id":"s2","name":"Done","sortOrder":2},{"id":"s1","name":"Todo","sortOrder":1,"isDefault":true}],
         "users":[{"id":"u2","name":"Zed"}],"teams":null,"holidays":[{"id":"h","date":"2026-11-11","label":"Armistice"}]}
        """#

        static let signedIn: [String: StubProtocol.Answer] = [
            "/api/mobile/info": .init(status: 200, body: #"{"service":"humble-planning","loginEnabled":true}"#),
            "/api/mobile/auth/login": .init(status: 200, body: #"{"status":"authenticated","session":{"userId":"me","cookieName":"better-auth.session_token","cookieValue":"tok.sig"}}"#),
            "/api/mobile/bootstrap": .init(status: 200, body: bootstrap),
            "/api/locale": .init(status: 200, body: #"{"success":true}"#),
            "/api/mobile/alerts": .init(status: 200, body: #"{"serverTime":"2026-11-05T10:00:00.000Z","alerts":[],"more":false}"#),
        ]

        @Test func passwordSignIn() async {
            StubProtocol.reset(Self.signedIn)
            let repository = repository()
            let step = await repository.login(server: "planning.example.com", identifier: " liam ", password: "secret", remember: true)
            #expect(step == .done)
            #expect(repository.isLoggedIn && repository.session?.cookie == "better-auth.session_token=tok.sig")
            #expect(repository.references.projects.map(\.id) == ["p2", "p1"] || repository.references.projects.map(\.id) == ["p1", "p2"])
            #expect(!repository.references.projects.contains { $0.id == "p3" })
            #expect(repository.references.statuses.map(\.id) == ["s1", "s2"])
            #expect(repository.references.users.map(\.id) == ["me", "u2"])
            #expect(repository.references.morningStart == "07:30" && !repository.references.placesEnabled)
            #expect(repository.preferences.lastLogin == "liam" && repository.preferences.userName == "Liam Turner")
            #expect(repository.preferences.alertsAfter == "2026-11-05T10:00:00.000Z")
            let requests = StubProtocol.requests.withLock { $0 }
            let login = requests.first { $0.url?.path() == "/api/mobile/auth/login" }
            #expect(login?.value(forHTTPHeaderField: "Cookie")?.contains("session_token") == false)
            let boot = requests.first { $0.url?.path() == "/api/mobile/bootstrap" }
            #expect(boot?.value(forHTTPHeaderField: "Cookie")?.hasSuffix("better-auth.session_token=tok.sig") == true)
        }

        @Test func signInErrors() async {
            StubProtocol.reset(["/api/mobile/info": .init(status: 200, body: #"{"service":"humble-planning","loginEnabled":false}"#)])
            let repository = repository()
            #expect(await repository.login(server: "", identifier: "a", password: "b", remember: true) == .failed(.urlRequired))
            #expect(await repository.login(server: "http://planning.example.com", identifier: "a", password: "b", remember: true) == .failed(.httpsRequired))
            #expect(await repository.login(server: "planning.example.com", identifier: " ", password: "b", remember: true) == .failed(.fieldsRequired))
            #expect(await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true) == .failed(.passwordLoginDisabled))
            StubProtocol.reset(["/api/mobile/info": .init(status: 200, body: #"{"service":"humble-planning"}"#),
                                "/api/mobile/auth/login": .init(status: 401, body: #"{"error":"Identifiants invalides","code":"auth.errors.invalidCredentials"}"#)])
            #expect(await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true) == .failed(.server("Identifiants invalides")))
            #expect(!repository.isLoggedIn)
        }

        @Test func secondFactor() async {
            var answers = Self.signedIn
            answers["/api/mobile/auth/login"] = .init(status: 200, body: #"{"status":"two_factor_required","pendingToken":"pt"}"#)
            answers["/api/mobile/auth/2fa"] = Self.signedIn["/api/mobile/auth/login"]
            StubProtocol.reset(answers)
            let repository = repository()
            #expect(await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: false) == .twoFactor(pendingToken: "pt"))
            #expect(await repository.submitTwoFactor(pendingToken: "pt", code: " 123456 ", isBackupCode: false) == .done)
            #expect(repository.preferences.lastLogin == "")
        }

        @Test func maintenanceDuringSignInThenResume() async {
            var answers = Self.signedIn
            answers["/api/mobile/bootstrap"] = .init(status: 423, body: #"{"error":"Maintenance","code":"mobile.errors.maintenance"}"#)
            StubProtocol.reset(answers)
            let repository = repository()
            #expect(await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true) == .failed(.server("")))
            #expect(repository.blocking == .maintenance("Maintenance") && repository.signInPending && repository.isLoggedIn)
            StubProtocol.reset(Self.signedIn.merging(["/api/profile": .init(status: 200, body: #"{"id":"me","name":"Turner"}"#)]) { $1 })
            #expect(await repository.retryBlocked())
            #expect(repository.blocking == nil)
            #expect(await repository.resumeSignIn() == .done)
            #expect(!repository.signInPending)
        }

        @Test func offlineAndBlockingFollowTheLastCall() async throws {
            StubProtocol.reset(Self.signedIn)
            let repository = repository()
            _ = await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true)
            StubProtocol.reset(["/api/mobile/bootstrap": .init(status: 503, body: "Service Unavailable")])
            await #expect(throws: APIError.network("HTTP 503")) { try await repository.loadReferences() }
            #expect(repository.offline)
            StubProtocol.reset(["/api/mobile/bootstrap": .init(status: 426, body: #"{"params":{"minimumVersion":"9.0.0","storeUrl":"https://x"}}"#)])
            await #expect(throws: (any Error).self) { try await repository.loadReferences() }
            #expect(repository.blocking == .upgradeRequired(minimumVersion: "9.0.0", storeURL: "https://x"))
            StubProtocol.reset(Self.signedIn)
            try await repository.loadReferences()
            #expect(repository.blocking == nil && !repository.offline)
        }

        @Test func expiredSessionIsFlagged() async throws {
            StubProtocol.reset(Self.signedIn)
            let repository = repository()
            _ = await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true)
            StubProtocol.reset(["/api/mobile/bootstrap": .init(status: 401, body: #"{"error":"x","code":"errors.sessionExpired"}"#)])
            await #expect(throws: APIError.sessionExpired) { try await repository.loadReferences() }
            try await Task.sleep(for: .milliseconds(50))
            #expect(repository.sessionExpired)
            repository.logout()
            #expect(!repository.isLoggedIn && !repository.sessionExpired && repository.references.user.id.isEmpty)
            #expect(repository.preferences.server == "https://planning.example.com")
        }

        @Test func syncMergesChangesAndDropsMissingIds() async throws {
            StubProtocol.reset(Self.signedIn)
            let repository = repository()
            _ = await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true)
            StubProtocol.reset(["/api/mobile/tasks/sync": .init(status: 200, body: #"""
                {"serverTime":"T1","changed":[{"id":"a","startDate":"2026-11-05"},{"id":"b","startDate":"2026-11-06"}],"ids":["a","b"]}
                """#)])
            #expect(try await repository.tasks(start: "2026-11-02", end: "2026-11-22").tasks.count == 2)
            StubProtocol.reset(["/api/mobile/tasks/sync": .init(status: 200, body: #"""
                {"serverTime":"T2","changed":[{"id":"a","title":"new","startDate":"2026-11-05"}],"ids":["a"]}
                """#)])
            let tasks = try await repository.tasks(start: "2026-11-02", end: "2026-11-22").tasks
            #expect(tasks.map(\.id) == ["a"] && tasks.first?.title == "new")
            #expect(StubProtocol.requests.withLock { $0 }.last?.url?.query()?.contains("since=T1") == true)
        }

        @Test func offlineCopyWhenTheNetworkFails() async throws {
            StubProtocol.reset(Self.signedIn)
            let repository = repository()
            _ = await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true)
            StubProtocol.reset(["/api/mobile/tasks/sync": .init(status: 200, body: #"""
                {"serverTime":"T","changed":[{"id":"mine","startDate":"2026-11-05","users":[{"id":"me","name":"T"}]},{"id":"other","startDate":"2026-11-05","users":[{"id":"u2","name":"Z"}]}],"ids":["mine","other"]}
                """#)])
            await repository.refreshOfflineData()
            StubProtocol.reset(["/api/mobile/tasks/sync": .init(status: 502, body: "")])
            let result = try await repository.tasks(start: "2026-11-01", end: "2026-11-30")
            #expect(result.isOffline && result.tasks.map(\.id) == ["mine"] && result.offlineSince != nil)
            #expect(try await repository.tasks(start: "2026-12-01", end: "2026-12-31").tasks.isEmpty)
        }

        @Test func alertsAreNotifiedOnce() async throws {
            StubProtocol.reset(Self.signedIn)
            let repository = repository()
            let presenter = RecordingAlerts()
            repository.alertPresenter = presenter
            _ = await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true)
            let page = #"{"serverTime":"T9","alerts":[{"id":"a1","title":"x"},{"id":"a2","type":"push_test"}],"more":false}"#
            StubProtocol.reset(["/api/mobile/alerts": .init(status: 200, body: page)])
            let changes = repository.alertsChanged
            try await repository.syncAlerts(notify: false)
            #expect(presenter.shown.withLock { $0 } == ["a2"])
            try await repository.syncAlerts(notify: true)
            #expect(presenter.shown.withLock { $0 } == ["a2"])
            #expect(repository.alertsChanged == changes + 1)
            #expect(repository.preferences.alertsAfter == "T9")
        }

        /// The settings show the count of the last planning, whoever started it (opening of the app, background).
        @Test func everyPlanningOfTheRemindersIsAnnounced() async throws {
            StubProtocol.reset(Self.signedIn)
            let repository = repository()
            _ = await repository.login(server: "planning.example.com", identifier: "a", password: "b", remember: true)
            StubProtocol.reset(["/api/mobile/tasks/sync": .init(status: 200, body: #"""
                {"serverTime":"T","changed":[{"id":"mine","startDate":"2026-11-06","startTime":"10:00","users":[{"id":"me","name":"T"}]}],"ids":["mine"]}
                """#)])
            let now = try #require(ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z"))
            let changes = repository.remindersChanged
            #expect(await repository.syncReminders(now: now))
            #expect(repository.remindersChanged == changes + 1 && repository.scheduledReminders.count == 1)
            StubProtocol.reset(["/api/mobile/tasks/sync": .init(status: 502, body: "")])
            #expect(await repository.syncReminders(now: now) == false)
            #expect(repository.remindersChanged == changes + 2 && repository.preferences.reminderFailed)
            #expect(repository.scheduledReminders.count == 1)
        }
    }
}
