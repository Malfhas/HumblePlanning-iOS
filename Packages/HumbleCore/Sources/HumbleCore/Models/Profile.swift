import Foundation

/// `PUT /api/profile`: optional texts are written as null when empty, the color only when set.
public struct UpdateProfileRequest: Encodable, Sendable, Equatable {
    public var name: String
    public var firstName: String?
    public var phone: String?
    public var mobile: String?
    public var job: String?
    public var color: String?

    public init(name: String, firstName: String?, phone: String?, mobile: String?, job: String?, color: String?) {
        func clean(_ value: String?) -> String? {
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firstName = clean(firstName)
        self.phone = clean(phone)
        self.mobile = clean(mobile)
        self.job = clean(job)
        self.color = color
    }

    enum CodingKeys: String, CodingKey { case name, firstName, phone, mobile, job, color }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(phone, forKey: .phone)
        try c.encode(mobile, forKey: .mobile)
        try c.encode(job, forKey: .job)
        try c.encodeIfPresent(color, forKey: .color)
    }
}
