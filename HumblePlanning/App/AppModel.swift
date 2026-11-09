import Network
import SwiftUI
import UIKit
import UserNotifications
import HumbleCore

/// Everything the screens share: the repository, the actions waiting for the right moment (a link to
/// confirm, a task to open), notifications, the network and the images of the server.
@MainActor
@Observable
final class AppModel {
    let repository: Repository
    let notifications: Notifications
    let images = ImageCache()
    /// A sign-in link waiting for confirmation.
    var qrLogin: QRLogin?
    /// A confirmed sign-in link, handed to the sign-in screen.
    var confirmedQR: QRLogin?
    /// A task to open (tapped notification), once signed in.
    var openTaskId: String?
    /// The task form, above any screen.
    var formRoute: TaskFormRoute?
    /// The sign-in screen says the session ended.
    var expiredNotice = false
    /// The main screen, once signed in (the session exists before the steps a sign-in may require).
    var showsMain: Bool

    var theme: AppTheme {
        didSet { repository.preferences.theme = theme.rawValue }
    }

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        #if DEBUG
        DebugReset.runIfAsked()
        DebugSwitches.applyLaunchArguments()
        #endif
        let secrets = KeychainStore()
        let preferences = Preferences()
        repository = Repository(preferences: preferences, secrets: secrets, files: .standard(secrets: secrets),
                                deviceName: Self.deviceName)
        notifications = Notifications()
        theme = AppTheme(rawValue: preferences.theme) ?? .system
        showsMain = repository.isLoggedIn
        repository.reminderScheduler = notifications
        repository.alertPresenter = notifications
        notifications.onOpenTask = { [weak self] id in self?.openTaskId = id }
        watchNetwork()
    }

    /// "iPhone (iOS 27.2)": the name of the phone needs a special permission since iOS 16.
    static var deviceName: String {
        "\(UIDevice.current.model) (\(UIDevice.current.systemName) \(UIDevice.current.systemVersion))"
    }

    @ObservationIgnored private var networkKnown = false

    private func watchNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.pathChanged(available: available) }
        }
        monitor.start(queue: DispatchQueue(label: "network"))
    }

    private func pathChanged(available: Bool) {
        // The first answer is the current state, not a change
        guard networkKnown else {
            networkKnown = true
            if !available { repository.networkChanged(available: false) }
            return
        }
        repository.networkChanged(available: available)
    }

    /// A link opened the app (camera scan, browser, in-app scanner).
    func handle(_ url: URL) {
        #if DEBUG
        if DebugSwitches.handle(url, repository: repository) { return }
        #endif
        if let login = QRLogin(link: url.absoluteString) { qrLogin = login }
    }

    /// Full sign-out, from the settings, the blocking screen, a confirmed link or an ended session.
    func signOut() {
        BackgroundRefresh.cancel()
        repository.logout()
        showsMain = false
    }
}

/// Avatars, kept in memory.
@MainActor
final class ImageCache {
    private let cache = NSCache<NSURL, UIImage>()

    func image(_ url: URL, repository: Repository) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let data = try? await repository.imageData(url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
