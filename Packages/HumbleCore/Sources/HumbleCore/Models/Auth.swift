import Foundation

/// `GET /api/mobile/info` (no session).
public struct MobileInfo: Codable, Sendable {
    @DefaultEmptyString public var service: String
    @DefaultZero public var mobileApiVersion: Int
    public var appTitle: String?
    @DefaultTrue public var loginEnabled: Bool
    @DefaultTrue public var pairingEnabled: Bool
    @DefaultFalse public var pushEnabled: Bool
    @DefaultTrue public var alertsEnabled: Bool
    @DefaultFalse public var forgotPasswordEnabled: Bool
    @DefaultFalse public var maintenance: Bool
    public var minimumAppVersion: String?
    public var storeUrl: String?
}

/// The device sent with every sign-in: it becomes a row of the user's devices.
public struct DeviceInfo: Codable, Sendable, Equatable {
    public var name: String
    public var platform: String
    public var appVersion: String
    public var locale: String

    public init(name: String, platform: String = AppInfo.platform, appVersion: String = AppInfo.version, locale: String) {
        self.name = name
        self.platform = platform
        self.appVersion = appVersion
        self.locale = locale
    }
}

public struct MobileSession: Codable, Sendable {
    @DefaultEmptyString public var userId: String
    @DefaultEmptyString public var cookieName: String
    /// Sent back verbatim.
    @DefaultEmptyString public var cookieValue: String
    @DefaultEmptyString public var expiresAt: String
}

public struct MobileLoginResponse: Codable, Sendable {
    /// `two_factor_required` or `authenticated`
    @DefaultEmptyString public var status: String
    public var pendingToken: String?
    public var session: MobileSession?
    @DefaultFalse public var forcePasswordChange: Bool
    @DefaultFalse public var setupTwoFactorRequired: Bool
}

struct MobileLoginRequest: Encodable {
    var identifier: String
    var password: String
    var device: DeviceInfo
}

struct MobileTwoFactorRequest: Encodable {
    var pendingToken: String
    var code: String
    var isBackupCode: Bool
    var device: DeviceInfo
}

struct MobilePairingRequest: Encodable {
    var code: String
    var device: DeviceInfo
}

public struct TwoFactorSetup: Codable, Sendable {
    /// Shown as a QR code.
    @DefaultEmptyString public var totpURI: String
    /// Shown as text.
    @DefaultEmptyString public var secret: String
}

public struct BackupCodes: Codable, Sendable {
    @DefaultEmpty<String> public var backupCodes: [String]
}

/// `PUT /api/mobile/devices/current`: only the push token is ever sent (null turns push off).
struct UpdateDeviceRequest: Encodable {
    var pushToken: String?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pushToken, forKey: .pushToken)
    }

    enum CodingKeys: String, CodingKey { case pushToken }
}
