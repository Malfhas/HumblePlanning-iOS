import Foundation

/// What the handshake carries: the session cookie is the only credential the Socket.IO server reads.
public struct RealtimeCredentials: Sendable, Equatable {
    /// The normalized base URL of the server (`https://host[:port][/path]`).
    public var serverURL: URL
    public var cookieName: String
    /// Sent verbatim.
    public var cookieValue: String
    /// The effective language, a bare code (`fr`, `en`, `es`, `de`): `HP_LOCALE` cookie and `Accept-Language`.
    public var language: String
    public var appVersion: String
    public var userAgent: String

    public init(
        serverURL: URL,
        cookieName: String,
        cookieValue: String,
        language: String,
        appVersion: String = AppInfo.version,
        userAgent: String = AppInfo.userAgent
    ) {
        self.serverURL = serverURL
        self.cookieName = cookieName
        self.cookieValue = cookieValue
        self.language = language
        self.appVersion = appVersion
        self.userAgent = userAgent
    }
}

/// Where and how the WebSocket connects.
///
/// Engine.IO is served at `/socket.io/` at the root of the host, whatever the path of the server URL:
/// the installer's reverse proxies (the Caddy site template, the nginx sample) route `/socket.io/*`
/// at the host root, and the web client connects to `window.location.origin`. The Socket.IO namespace
/// is always `/` (the Android client used the URL path as namespace, which fails on a sub-path install).
enum RealtimeEndpoint {
    static let path = "/socket.io/"

    /// `wss://host[:port]/socket.io/?EIO=4&transport=websocket` (`ws` for an `http` server), nil for another scheme.
    static func url(for serverURL: URL) -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: true),
              let host = components.host, !host.isEmpty
        else { return nil }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return nil
        }
        components.user = nil
        components.password = nil
        components.path = path
        components.percentEncodedQuery = "EIO=4&transport=websocket"
        components.fragment = nil
        return components.url
    }

    /// The handshake request, with the headers of every request of the app and never `Origin`
    /// (the mobile routes refuse it).
    static func request(for credentials: RealtimeCredentials) -> URLRequest? {
        guard let url = url(for: credentials.serverURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        var cookies = ["HP_LOCALE=\(credentials.language)"]
        if !credentials.cookieName.isEmpty { cookies.append("\(credentials.cookieName)=\(credentials.cookieValue)") }
        request.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.setValue(credentials.appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(AppInfo.platform, forHTTPHeaderField: "X-App-Platform")
        request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.language, forHTTPHeaderField: "Accept-Language")
        return request
    }
}

/// Timing of the connection; the defaults are those of the Android client.
public struct RealtimeTiming: Sendable, Equatable {
    /// From the start of an attempt until the namespace is connected.
    public var connectTimeout: Duration
    /// `presence:heartbeat` this often while connected (the server drops presence after 5 minutes).
    public var heartbeatInterval: Duration
    /// First reconnection delay, doubled at each failed attempt…
    public var reconnectDelay: Duration
    /// …up to this.
    public var reconnectDelayMax: Duration
    /// Each delay varies by up to this fraction, either way.
    public var randomizationFactor: Double

    public init(
        connectTimeout: Duration = .seconds(20),
        heartbeatInterval: Duration = .seconds(30),
        reconnectDelay: Duration = .seconds(1),
        reconnectDelayMax: Duration = .seconds(10),
        randomizationFactor: Double = 0.5
    ) {
        self.connectTimeout = connectTimeout
        self.heartbeatInterval = heartbeatInterval
        self.reconnectDelay = reconnectDelay
        self.reconnectDelayMax = reconnectDelayMax
        self.randomizationFactor = randomizationFactor
    }

    /// The delay before reconnection attempt `attempt` (0 for the first one), `random` in `0..<1`:
    /// the `Backoff` of the Socket.IO clients (the randomization applies before the cap, and the
    /// first decimal digit of `random` picks the direction).
    func reconnectDelay(attempt: Int, random: Double) -> Duration {
        var milliseconds = reconnectDelay.milliseconds * pow(2, Double(min(max(attempt, 0), 60)))
        if randomizationFactor > 0 {
            let deviation = (random * randomizationFactor * milliseconds).rounded(.down)
            milliseconds += Int((random * 10).rounded(.down)) & 1 == 0 ? -deviation : deviation
        }
        return .milliseconds(max(0, min(milliseconds, reconnectDelayMax.milliseconds)))
    }
}
