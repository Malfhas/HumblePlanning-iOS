import Foundation
import Synchronization

/// The URL sessions of the app: no cookie storage (the session cookie is sent by hand, only to its
/// server), and a redirect guard. One for the API (idle 20 s, 90 s in all), one for the assistant
/// stream (idle 120 s, no total limit).
public final class Transport: NSObject, URLSessionTaskDelegate, Sendable {
    public static let shared = Transport()


    public let api: URLSession
    public let stream: URLSession

    /// `protocolClasses` lets the tests answer requests without a server.
    init(protocolClasses: [AnyClass]? = nil) {
        let delegate = RedirectDelegate()
        func configuration(idle: TimeInterval, total: TimeInterval) -> URLSessionConfiguration {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = idle
            configuration.timeoutIntervalForResource = total
            configuration.waitsForConnectivity = false
            if let protocolClasses { configuration.protocolClasses = protocolClasses }
            return configuration
        }
        api = URLSession(configuration: configuration(idle: 20, total: 90), delegate: delegate, delegateQueue: nil)
        stream = URLSession(configuration: configuration(idle: 120, total: 7 * 24 * 3600), delegate: delegate, delegateQueue: nil)
        super.init()
    }

    /// Connections of a network that went away would hang until their timeout.
    public func networkChanged() {
        api.flush {}
    }

    #if DEBUG
    private static let offlineSwitch = Atomic(false)

    /// Development only: while on, no request leaves, as without network (interface tests).
    public static var simulatesOffline: Bool {
        get { offlineSwitch.load(ordering: .relaxed) }
        set { offlineSwitch.store(newValue, ordering: .relaxed) }
    }
    #endif
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        RedirectPolicy.follow(from: task.originalRequest, to: request)
    }
}
