import Foundation

public struct MobileAlert: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    /// `push_test` for the test alert of the settings.
    @DefaultEmptyString public var type: String
    @DefaultEmptyString public var title: String
    @DefaultEmptyString public var message: String
    public var actionUrl: String?
    @DefaultEmptyString public var createdAt: String

    public init(id: String, type: String = "", title: String = "", message: String = "", actionUrl: String? = nil, createdAt: String = "") {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.actionUrl = actionUrl
        self.createdAt = createdAt
    }

    /// The task of the alert: links look like `/tasks?id=<uuid>`.
    public var taskId: String? {
        guard let url = actionUrl, let range = url.range(of: "id=") else { return nil }
        let rest = url[range.upperBound...]
        let id = rest.prefix { $0 != "&" }
        return id.trimmingCharacters(in: .whitespaces).isEmpty ? nil : String(id)
    }
}

/// `GET /api/mobile/alerts`: oldest first.
public struct AlertsPage: Codable, Sendable {
    @DefaultEmptyString public var serverTime: String
    @DefaultEmpty<MobileAlert> public var alerts: [MobileAlert]
    @DefaultFalse public var more: Bool
}

public struct Device: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var platform: String
    public var deviceName: String?
    public var appVersion: String?
    @DefaultFalse public var pushEnabled: Bool
    @DefaultFalse public var current: Bool
    public var lastSeenAt: String?

    /// The name of the device, or its platform.
    public var label: String {
        let name = (deviceName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? platform : name
    }
}

struct PushTestResult: Codable {
    var delivered: Int?
}
