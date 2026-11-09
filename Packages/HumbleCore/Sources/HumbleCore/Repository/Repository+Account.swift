import Foundation

extension Repository {
    // MARK: Alerts

    /// Fetches the alerts since the cursor (two pages at most, the rest waits for the next time),
    /// lists the new ones and notifies them when `notify` (the test alert is always notified).
    public func syncAlerts(notify: Bool) async throws {
        guard isLoggedIn else { return }
        var after = preferences.alertsAfter.flatMap { $0.isEmpty ? nil : $0 } ?? ISO8601DateFormatter().string(from: Date())
        var received: [MobileAlert] = []
        for _ in 1...2 {
            let page = try await call { [after] in try await $0.alerts(after: after) }
            received += page.alerts
            after = page.serverTime
            if !page.more { break }
        }
        preferences.alertsAfter = after
        let shown = preferences.alertsShown
        var seen = Set(shown)
        let fresh = received.filter { seen.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        preferences.alertsShown = shown + fresh.map(\.id)
        alertsChanged += 1
        for alert in fresh where notify || alert.type == "push_test" {
            await alertPresenter?.show(alert)
        }
    }

    /// The latest alerts, newest first.
    public func alertsHistory() async throws -> [MobileAlert] {
        try await call { try await $0.alerts(after: nil) }.alerts.reversed()
    }

    /// Asks the server to send a test alert; false when no device of the account could be reached.
    public func sendTestAlert() async throws -> Bool {
        let delivered = try await call { try await $0.pushTest() }
        return delivered.map { $0 > 0 } ?? true
    }

    // MARK: Reminders

    /// Schedules the reminders of the next 14 days; false when the server could not be read (the
    /// reminders already scheduled stay).
    @discardableResult
    public func syncReminders(now: Date = Date()) async -> Bool {
        defer { remindersChanged += 1 }
        let offset = ReminderOffset(stored: preferences.reminderOffset)
        guard isLoggedIn, offset != .none else {
            await reminderScheduler?.cancelAll()
            return true
        }
        do {
            let range = PlanningPeriod.reminders(today: CalendarDay(now))
            let all = try await call { try await $0.syncTasks(start: range.lowerBound.iso, end: range.upperBound.iso, since: nil) }.changed
            let me = userId
            let tasks = preferences.reminderAll ? all : all.filter { $0.userIds.contains(me) }
            if references.projects.isEmpty { try? await loadReferences() }
            let references = references
            let reminders = ReminderPlanner.plan(tasks, defaultStart: references.morningStart, offset: offset, now: now,
                                                 timeZone: .current) { ReminderPlanner.label($0, references: references) }
            await reminderScheduler?.schedule(reminders)
            try? files.write(reminders, .reminders)
            preferences.reminderFailed = false
            return true
        } catch {
            preferences.reminderFailed = true
            return false
        }
    }

    public var scheduledReminders: [Reminder] { files.read([Reminder].self, .reminders) ?? [] }

    // MARK: Devices

    /// This device first, then the most recently seen.
    public func devices() async throws -> [Device] {
        try await call { try await $0.devices() }.sorted {
            if $0.current != $1.current { return $0.current }
            return ($0.lastSeenAt ?? "") > ($1.lastSeenAt ?? "")
        }
    }

    public func revokeDevice(_ id: String) async throws {
        try await call { try await $0.deleteDevice(id) }
    }

    /// Sends the push token of this device when it changed.
    public func pushTokenChanged(_ token: String?) {
        guard isLoggedIn, preferences.pushTokenSent != token else { return }
        Task {
            try? await api().updateDevice(pushToken: token)
            preferences.pushTokenSent = token
        }
    }

    // MARK: Profile and security

    public func updateProfile(_ profile: UpdateProfileRequest) async throws {
        replaceUser(try await call { try await $0.updateProfile(profile) })
    }

    public func changePassword(current: String, new: String) async throws {
        try await call { try await $0.changePassword(current: current, new: new) }
    }

    /// The user's own choice for alerts on the phone.
    public func setAlertsEnabled(_ enabled: Bool) async throws {
        try await call { try await $0.setPushPreference(enabled) }
        var user = references.user
        user.mobilePushNotificationsUser = enabled
        replaceUser(user)
    }

    public func enableTwoFactor(password: String) async throws -> TwoFactorSetup {
        try await call { try await $0.enableTwoFactor(password: password) }
    }

    public func verifyTwoFactor(code: String) async throws -> [String] {
        try await call { try await $0.verifyTwoFactor(code: code) }.backupCodes
    }

    public func disableTwoFactor(password: String) async throws {
        try await call { try await $0.disableTwoFactor(password: password) }
        try? await loadReferences()
    }

    // MARK: Images

    /// An avatar of the server, read with the session.
    public func imageData(_ url: URL) async throws -> Data {
        try await api().image(at: url)
    }
}
