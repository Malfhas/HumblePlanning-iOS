import Foundation

/// Identity of the app, as the server sees it.
public enum AppInfo {
    /// Sent as `platform` when the device registers.
    public static let platform = "ios"

    #if DEBUG
    /// Development only: the version claimed instead (`-HPAppVersion`, interface tests), set by the app at
    /// launch before any request.
    public nonisolated(unsafe) static var debugVersion: String?
    #endif

    /// `CFBundleShortVersionString` before any `-suffix`, sent as `X-App-Version`.
    public static var version: String {
        #if DEBUG
        if let debugVersion { return debugVersion }
        #endif
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return String(raw.split(separator: "-").first ?? "1.0.0")
    }

    public static var userAgent: String { "HumblePlanning-iOS/\(version)" }

    /// The App Store page, opened when the server requires a newer version.
    public static let storeURL = URL(string: "https://apps.apple.com/app/humble-planning")!
    public static let sourceURL = URL(string: "https://github.com/Malfhas/HumblePlanning-iOS")!
    public static let websiteURL = URL(string: "https://humbleplanning.com")!

    /// The server's version is older than `minimum`: numeric segments compared one by one (missing or
    /// non-numeric = 0, any `-suffix` ignored), like the server's `compareVersions`.
    public static func isOlder(_ version: String, than minimum: String?) -> Bool {
        guard let minimum, !minimum.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        func parts(_ value: String) -> [Int] {
            let core = value.split(separator: "-", maxSplits: 1).first.map(String.init) ?? value
            return core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        }
        let a = parts(version), b = parts(minimum)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x < y }
        }
        return false
    }
}
