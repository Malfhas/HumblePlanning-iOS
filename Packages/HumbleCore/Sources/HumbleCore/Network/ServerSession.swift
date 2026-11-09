import Foundation

/// The session of the signed-in account: a Better Auth cookie bound to its server.
public struct ServerSession: Codable, Sendable, Equatable {
    public var serverURL: String
    public var cookieName: String
    public var cookieValue: String

    public init(serverURL: String, cookieName: String, cookieValue: String) {
        self.serverURL = serverURL
        self.cookieName = cookieName
        self.cookieValue = cookieValue
    }

    public var cookie: String { "\(cookieName)=\(cookieValue)" }

    /// The cookie only goes to its own server: same scheme, host and port.
    public func belongs(to url: URL) -> Bool {
        guard let server = URL(string: serverURL) else { return false }
        return Origin(server) == Origin(url)
    }
}

struct Origin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else { return nil }
        self.scheme = scheme
        self.host = host
        port = url.port ?? (scheme == "https" ? 443 : 80)
    }
}

/// What a redirection keeps: never a switch between http and https, and the session cookie only
/// on its own server (the language cookie always).
enum RedirectPolicy {
    static func follow(from original: URLRequest?, to redirected: URLRequest) -> URLRequest? {
        guard let from = original?.url, let to = redirected.url else { return redirected }
        guard from.scheme?.lowercased() == to.scheme?.lowercased() else { return nil }
        guard Origin(from) != Origin(to), let cookie = redirected.value(forHTTPHeaderField: "Cookie") else { return redirected }
        var request = redirected
        let kept = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("HP_LOCALE=") }
        request.setValue(kept.isEmpty ? nil : kept.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        return request
    }
}
