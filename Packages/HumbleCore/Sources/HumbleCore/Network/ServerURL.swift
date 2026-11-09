import Foundation

/// The address of a Humble Planning server as typed or scanned, made canonical:
/// `https://host[:port][/path]`, host in lower case, no trailing slash, no query.
public enum ServerURL {
    public enum Result: Equatable, Sendable {
        case ok(url: String, host: String)
        case empty
        case httpsRequired
        case invalid
    }

    /// Debug builds may reach a test server in clear text on this computer or the local network.
    #if DEBUG
    public static let allowsCleartextLocalHosts = true
    #else
    public static let allowsCleartextLocalHosts = false
    #endif

    public static func normalize(_ input: String, allowCleartextLocalHosts: Bool = allowsCleartextLocalHosts) -> Result {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.lowercased() == "https://" { return .empty }
        if raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) || raw.contains("\\") {
            return .invalid
        }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        let components = URLComponents(string: withScheme).flatMap { c -> URLComponents? in
            ["http", "https"].contains(c.scheme?.lowercased() ?? "") ? c : nil
        }
        let host = (components?.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let cleartextAllowed = allowCleartextLocalHosts && components?.scheme?.lowercased() == "http" && isLocal(host)
        if !withScheme.lowercased().hasPrefix("https://") && !cleartextAllowed { return .httpsRequired }
        guard let components, !host.isEmpty, components.user == nil, components.password == nil else { return .invalid }
        let scheme = components.scheme!.lowercased()
        let defaultPort = scheme == "https" ? 443 : 80
        let port = components.port.map { $0 == defaultPort ? "" : ":\($0)" } ?? ""
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return .ok(url: "\(scheme)://\(hostPart)\(port)\(path)", host: host)
    }

    /// `host[:port]` of a valid address, shown before signing in with a QR code.
    public static func hostOf(_ input: String) -> String? {
        guard case .ok(let url, let host) = normalize(input), let components = URLComponents(string: url) else { return nil }
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return components.port.map { "\(hostPart):\($0)" } ?? hostPart
    }

    /// This computer, or an address of a private network (`10/8`, `172.16/12`, `192.168/16`) or `.local`.
    static func isLocal(_ host: String) -> Bool {
        if ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, host.split(separator: ".").count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168)
    }
}

/// `humbleplanning://login?url=<server>&code=<64 hex>`: the link of the QR code of the web profile.
public struct QRLogin: Equatable, Sendable {
    public let serverURL: String
    public let code: String

    public init?(link: String) {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: text),
              components.scheme?.lowercased() == "humbleplanning",
              components.host?.lowercased() == "login" else { return nil }
        let items = components.queryItems ?? []
        let server = (items.first { $0.name == "url" }?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (items.first { $0.name == "code" }?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, code.count == 64, code.allSatisfy(\.isHexDigit) else { return nil }
        serverURL = server
        self.code = code
    }
}
