import Foundation

/// Why a call failed. The first four change the whole app (offline banner, blocking screen,
/// sign-out); the others are shown where they happen.
public enum APIError: Error, Sendable, Equatable {
    /// No connection, timeout, or a bare 5xx from a proxy (server being updated).
    case network(String)
    case upgradeRequired(minimumVersion: String, storeURL: String)
    case maintenance(String)
    case appNotAllowed(String)
    case sessionExpired
    /// The address does not answer like a Humble Planning server.
    case notHumblePlanning
    /// A body that is not what was expected (first 300 characters).
    case unexpected(String)
    /// An error of the server, with its message translated into the language of the request.
    case server(status: Int, code: String, message: String)

    /// Shown by the blocking screen, never as an error message.
    public var isBlocking: Bool {
        switch self {
        case .upgradeRequired, .maintenance, .appNotAllowed: true
        default: false
        }
    }

    public var isNotFound: Bool { if case .server(404, _, _) = self { true } else { false } }
    public var isForbidden: Bool { if case .server(403, _, _) = self { true } else { false } }
    public var isNetwork: Bool { if case .network = self { true } else { false } }

    /// The message of the server, when it gave one.
    public var serverMessage: String? {
        switch self {
        case .server(_, _, let message), .maintenance(let message), .appNotAllowed(let message):
            message.isEmpty ? nil : message
        default: nil
        }
    }

    /// The failure of a non-2xx response, in the order of the Android client.
    static func failure(status: Int, path: String, body: Data) -> APIError {
        let error = ErrorBody(body)
        if status == 426 {
            return .upgradeRequired(minimumVersion: error?.param("minimumVersion") ?? "", storeURL: error?.param("storeUrl") ?? "")
        }
        if status == 423 { return .maintenance(error?.error ?? "") }
        if status == 403, error?.code == "mobile.errors.appNotAllowed" { return .appNotAllowed(error?.error ?? "") }
        guard let error else {
            if status >= 500 { return .network("HTTP \(status)") }
            return .unexpected(String(decoding: body.prefix(300), as: UTF8.self))
        }
        if status == 401, ["errors.unauthenticated", "errors.sessionExpired"].contains(error.code), !path.hasPrefix("/api/mobile/auth/") {
            return .sessionExpired
        }
        return .server(status: status, code: error.code, message: error.error)
    }

    /// `{error, code, params}`; nil when the body is not a JSON object.
    struct ErrorBody {
        var error: String
        var code: String
        var params: JSONObject

        init?(_ body: Data) {
            guard let object = (try? JSONValue.parse(body))?.objectValue else { return nil }
            error = object["error"]?.stringValue ?? ""
            code = object["code"]?.stringValue ?? ""
            params = object["params"]?.objectValue ?? JSONObject()
        }

        func param(_ name: String) -> String { params[name]?.primitiveText ?? "" }
    }
}
