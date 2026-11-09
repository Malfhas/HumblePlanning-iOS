#if DEBUG
import Foundation
import HumbleCore

/// Development only, for the interface tests:
/// - `-HPAppVersion <version>` at launch: the app claims this version to the server (update screen);
/// - the links `humbleplanning://debug/offline` and `humbleplanning://debug/online`: no request leaves while
///   offline, and the app hears of each change as from the network monitor.
enum DebugSwitches {
    static func applyLaunchArguments() {
        AppInfo.debugVersion = UserDefaults.standard.string(forKey: "HPAppVersion")
    }

    /// True when the link was one of these switches.
    static func handle(_ url: URL, repository: Repository) -> Bool {
        guard url.scheme?.lowercased() == "humbleplanning", url.host()?.lowercased() == "debug" else { return false }
        switch url.path() {
        case "/offline":
            Transport.simulatesOffline = true
            repository.networkChanged(available: false)
        case "/online":
            Transport.simulatesOffline = false
            repository.networkChanged(available: true)
        default:
            break
        }
        return true
    }
}
#endif
