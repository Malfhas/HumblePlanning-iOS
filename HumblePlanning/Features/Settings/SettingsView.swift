import SwiftUI
import UserNotifications
import HumbleCore

/// Display, alerts, reminders, security, devices, about, sign-out.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("card_title") private var cardTitle = "project"
    @AppStorage("reminder_offset") private var reminderOffset = ReminderOffset.fifteenMinutes.rawValue
    @AppStorage("reminder_all") private var reminderAll = false

    @State private var notificationsAllowed: Bool?
    @State private var alertsError: String?
    @State private var testResult: Bool?
    @State private var sendingTest = false
    @State private var syncingReminders = false
    @State private var remindersCount = 0
    @State private var securityNotice: String?
    @State private var devices: [Device] = []
    @State private var devicesLoading = true
    @State private var devicesError: String?
    @State private var showsAllDevices = false
    @State private var sheet: Sheet?
    @State private var revoking: Device?
    @State private var confirmsSignOut = false

    enum Sheet: Identifiable {
        case profile, password, disableTwoFactor, enableTwoFactor
        var id: Self { self }
    }

    private var repository: Repository { app.repository }
    private var user: User { repository.references.user }

    var body: some View {
        @Bindable var app = app
        Form {
            profile
            display
            if repository.references.alertsSettingVisible { alerts }
            reminders
            security
            devicesSection
            about
            Section {
                Button(String(localized: .signOut), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmsSignOut = true
                }
                .accessibilityIdentifier("settings.signOut")
            }
        }
        .navigationTitle(String(localized: .tabSettings))
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await readPermission() } } }
        .onChange(of: repository.blocking) { _, blocking in if blocking == nil { Task { await loadDevices() } } }
        // The reminders are also planned elsewhere (opening of the app, background refresh)
        .onChange(of: repository.remindersChanged) { remindersCount = repository.scheduledReminders.count }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .profile: ProfileSheet()
            case .password: PasswordSheet { securityNotice = String(localized: .securityPasswordChanged) }
            case .disableTwoFactor: DisableTwoFactorSheet { securityNotice = String(localized: .twoFactorDisabled) }
            case .enableTwoFactor: TwoFactorSetupSheet()
            }
        }
        .alert(String(localized: .devicesRevokeTitle), isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
               presenting: revoking) { device in
            Button(String(localized: .devicesRevoke), role: .destructive) { revoke(device) }
            Button(String(localized: .cancel), role: .cancel) {}
        } message: { device in
            Text(.devicesRevokeText(device.label))
        }
        .alert(String(localized: .signOut), isPresented: $confirmsSignOut) {
            Button(String(localized: .signOut), role: .destructive) { app.signOut() }
            Button(String(localized: .cancel), role: .cancel) {}
        } message: {
            Text(.signOutConfirm)
        }
    }

    // MARK: Sections

    private var profile: some View {
        Section {
            Button { sheet = .profile } label: {
                HStack(spacing: 14) {
                    // The avatar above the name with the accessibility sizes, where the name needs the width
                    AdaptiveStack(spacing: 14) {
                        UserAvatar(user: user, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            if let email = user.email, !email.isEmpty {
                                Text(email).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(serverLabel).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Image(systemName: "pencil").foregroundStyle(.secondary).accessibilityLabel(String(localized: .profileEdit))
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var serverLabel: String {
        (repository.session?.serverURL ?? "").replacingOccurrences(of: "https://", with: "")
    }

    private var display: some View {
        @Bindable var app = app
        return Section(String(localized: .settingsDisplay)) {
            Picker(String(localized: .settingsTheme), selection: $app.theme) {
                Text(.themeSystem).tag(AppTheme.system)
                Text(.themeLight).tag(AppTheme.light)
                Text(.themeDark).tag(AppTheme.dark)
            }
            Picker(String(localized: .settingsCardTitle), selection: $cardTitle) {
                Text(.cardTitleProject).tag("project")
                Text(.cardTitleTask).tag("title")
            }
            // The language of an app is chosen in the settings of iOS
            Button {
                openURL(URL(string: UIApplication.openSettingsURLString)!)
            } label: {
                LabeledContent(String(localized: .settingsLanguage), value: Locale.current.localizedString(forLanguageCode: AppLanguage.effective)?.capitalized ?? "")
            }
            .foregroundStyle(.primary)
        }
    }

    private var alerts: some View {
        Section(String(localized: .settingsAlerts)) {
            if let alertsError { Banner(text: alertsError, tone: .error) }
            if let testResult {
                Banner(text: testResult ? String(localized: .alertsTestSent) : String(localized: .alertsTestNotDelivered),
                       tone: testResult ? .info : .warning, systemImage: testResult ? "checkmark.circle" : nil)
            }
            Toggle(isOn: Binding(get: { user.mobilePushNotifications && user.mobilePushNotificationsUser }, set: { setAlerts($0) })) {
                Text(.alertsOnPhone)
                Text(user.mobilePushNotifications ? String(localized: .alertsOnPhoneHelp) : String(localized: .alertsOffByAdmin))
            }
            .disabled(!user.mobilePushNotifications)
            permissionRow
            Button {
                sendTest()
            } label: {
                HStack {
                    Label(String(localized: .alertsSendTest), systemImage: "paperplane")
                    if sendingTest { Spacer(); ProgressView() }
                }
            }
            .disabled(sendingTest)
        }
    }

    private var permissionRow: some View {
        HStack {
            Label(String(localized: .permNotifications), systemImage: "bell.badge")
            Spacer()
            if notificationsAllowed == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
                    .accessibilityLabel(String(localized: .permGranted))
            } else if notificationsAllowed == false {
                Button {
                    allowNotifications()
                } label: {
                    Label(String(localized: .permAllow), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.warning)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var reminders: some View {
        Section(String(localized: .settingsReminders)) {
            Picker(String(localized: .reminderDelay), selection: $reminderOffset) {
                ForEach(ReminderOffset.allCases, id: \.rawValue) { offset in
                    Text(Self.label(offset)).tag(offset.rawValue)
                }
            }
            .onChange(of: reminderOffset) { remindersChanged() }
            Picker(String(localized: .reminderFor), selection: $reminderAll) {
                Text(.reminderMyTasks).tag(false)
                Text(.reminderAllTasks).tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: reminderAll) { remindersChanged() }
            if ReminderOffset(stored: reminderOffset) != .none {
                permissionRow
                HStack {
                    if repository.preferences.reminderFailed {
                        Text(.reminderFailed).foregroundStyle(Palette.danger)
                    } else {
                        Text(.remindersScheduled(remindersCount)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if syncingReminders {
                        ProgressView()
                    } else {
                        Button(String(localized: .reminderSync), systemImage: "arrow.triangle.2.circlepath") { syncReminders() }
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                }
                .font(.footnote)
            }
        }
    }

    static func label(_ offset: ReminderOffset) -> String {
        switch offset {
        case .none: String(localized: .reminderNever)
        case .fiveMinutes: String(localized: .reminder5Min)
        case .fifteenMinutes: String(localized: .reminder15Min)
        case .thirtyMinutes: String(localized: .reminder30Min)
        case .oneHour: String(localized: .reminder1H)
        case .fourHours: String(localized: .reminder4H)
        case .oneDay: String(localized: .reminder1D)
        }
    }

    private var security: some View {
        Section(String(localized: .settingsSecurity)) {
            if let securityNotice { Banner(text: securityNotice, systemImage: "checkmark.circle") }
            Button(String(localized: .passwordChange), systemImage: "key") { securityNotice = nil; sheet = .password }
                .foregroundStyle(.primary)
            if !user.twoFactorEnabled {
                Button(String(localized: .twoFactorEnable), systemImage: "lock.shield") { securityNotice = nil; sheet = .enableTwoFactor }
                    .foregroundStyle(.primary)
            } else if user.forceTwoFactor {
                LabeledContent {
                    Text(.twoFactorOn)
                } label: {
                    Label(String(localized: .twoFactorTitle), systemImage: "lock.shield")
                }
            } else {
                Button { securityNotice = nil; sheet = .disableTwoFactor } label: {
                    LabeledContent {
                        Text(.twoFactorOn)
                    } label: {
                        Label(String(localized: .twoFactorDisable), systemImage: "lock.shield")
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var devicesSection: some View {
        Section(String(localized: .settingsDevices)) {
            if let devicesError { Banner(text: devicesError, tone: .error) }
            if devicesLoading && devices.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if devices.isEmpty {
                Text(.devicesNone).foregroundStyle(.secondary)
            }
            ForEach(showsAllDevices ? devices : Array(devices.prefix(3))) { device in
                DeviceRow(device: device) { revoking = device }
            }
            if devices.count > 3 {
                Button(showsAllDevices ? String(localized: .devicesShowLess) : String(localized: .devicesShowAll(devices.count))) {
                    withAnimation { showsAllDevices.toggle() }
                }
            }
        }
    }

    private var about: some View {
        Section(String(localized: .settingsAbout)) {
            LabeledContent(String(localized: .aboutAppVersion), value: AppInfo.version)
            LabeledContent(String(localized: .aboutLicense), value: "AGPL-3.0-or-later")
            Link(destination: AppInfo.sourceURL) { Label(String(localized: .aboutSource), systemImage: "chevron.left.forwardslash.chevron.right") }
            Link(destination: AppInfo.websiteURL) { Label(String(localized: .aboutWebsite), systemImage: "globe") }
            if let server = repository.session?.serverURL, let privacy = URL(string: server + "/privacy") {
                Link(destination: privacy) { Label(String(localized: .aboutPrivacy), systemImage: "hand.raised") }
            }
        }
    }

    // MARK: Actions

    private func refresh() async {
        remindersCount = repository.scheduledReminders.count
        // Reading the permission can take seconds (first launch after install): the devices do not wait for it
        Task { await readPermission() }
        await loadDevices()
    }

    private func readPermission() async {
        notificationsAllowed = await app.notifications.isAuthorized
    }

    private func allowNotifications() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = await app.notifications.requestAuthorization()
                await readPermission()
                syncReminders()
            } else {
                openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
            }
        }
    }

    private func setAlerts(_ enabled: Bool) {
        alertsError = nil
        Task {
            do { try await repository.setAlertsEnabled(enabled) } catch { alertsError = screenMessage(error) }
        }
    }

    private func sendTest() {
        sendingTest = true
        alertsError = nil
        testResult = nil
        Task {
            do { testResult = try await repository.sendTestAlert() } catch { alertsError = screenMessage(error) }
            sendingTest = false
        }
    }

    private func remindersChanged() {
        repository.preferences.reminderOffset = reminderOffset
        repository.preferences.reminderAll = reminderAll
        Task {
            if ReminderOffset(stored: reminderOffset) != .none, notificationsAllowed != true {
                _ = await app.notifications.requestAuthorization()
                await readPermission()
            }
            syncReminders()
        }
    }

    private func syncReminders() {
        syncingReminders = true
        Task {
            await repository.syncReminders()
            remindersCount = repository.scheduledReminders.count
            syncingReminders = false
        }
    }

    private func loadDevices() async {
        devicesLoading = true
        do {
            devices = try await repository.devices()
            devicesError = nil
        } catch {
            devicesError = screenMessage(error)
        }
        devicesLoading = false
    }

    private func revoke(_ device: Device) {
        Task {
            do {
                try await repository.revokeDevice(device.id)
                devices.removeAll { $0.id == device.id }
            } catch {
                devicesError = screenMessage(error)
            }
        }
    }
}

private struct DeviceRow: View {
    let device: Device
    let onRevoke: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.platform == "ios" ? "iphone" : "smartphone")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.label).lineLimit(2)
                Text(details).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !device.current {
                Button(role: .destructive, action: onRevoke) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: .devicesRevokeLabel(device.label)))
            }
        }
    }

    private var details: String {
        var parts: [String] = []
        if device.current { parts.append(String(localized: .devicesCurrent)) }
        if let version = device.appVersion, !version.isEmpty { parts.append(version) }
        if let seen = device.lastSeenAt { parts.append(RelativeDate.text(seen)) }
        return parts.joined(separator: " · ")
    }
}
