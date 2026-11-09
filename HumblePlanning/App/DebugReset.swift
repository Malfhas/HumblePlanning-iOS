#if DEBUG
import Foundation
import Security
import UserNotifications

/// Development only: `-HPResetState YES` starts the app as if just installed (interface tests): no session,
/// no settings, no offline copy, no reminder. The launch arguments themselves stay readable.
enum DebugReset {
    static func runIfAsked() {
        guard UserDefaults.standard.bool(forKey: "HPResetState") else { return }
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecUseDataProtectionKeychain as String: true] as CFDictionary)
        let files = FileManager.default
        for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
            guard let root = files.urls(for: directory, in: .userDomainMask).first else { continue }
            for item in (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                try? files.removeItem(at: item)
            }
        }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
#endif
