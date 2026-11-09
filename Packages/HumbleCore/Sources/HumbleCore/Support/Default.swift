import Foundation

/// A value that falls back to a default when its key is missing or `null`, like the lenient
/// decoder of the Android app (`coerceInputValues`): one unexpected `null` from the server
/// must never make a whole bootstrap fail. A value of the wrong type still fails.
@propertyWrapper
public struct Default<Provider: DefaultValueProvider>: Sendable, Hashable {
    public var wrappedValue: Provider.Value

    public init(wrappedValue: Provider.Value = Provider.defaultValue) {
        self.wrappedValue = wrappedValue
    }
}

public protocol DefaultValueProvider {
    associatedtype Value: Codable & Sendable & Hashable
    static var defaultValue: Value { get }
}

extension Default: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? Provider.defaultValue : try container.decode(Provider.Value.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    /// A missing key gives the default (synthesized `Decodable` would throw `keyNotFound`).
    public func decode<P>(_ type: Default<P>.Type, forKey key: Key) throws -> Default<P> {
        try decodeIfPresent(type, forKey: key) ?? Default()
    }
}

public enum Defaults {
    public enum EmptyString: DefaultValueProvider { public static var defaultValue: String { "" } }
    public enum False: DefaultValueProvider { public static var defaultValue: Bool { false } }
    public enum True: DefaultValueProvider { public static var defaultValue: Bool { true } }
    public enum Zero: DefaultValueProvider { public static var defaultValue: Int { 0 } }
    public enum ZeroInt64: DefaultValueProvider { public static var defaultValue: Int64 { 0 } }
    public enum Empty<Element: Codable & Sendable & Hashable>: DefaultValueProvider {
        public static var defaultValue: [Element] { [] }
    }
    public enum EmptyMap<Element: Codable & Sendable & Hashable>: DefaultValueProvider {
        public static var defaultValue: [String: Element] { [:] }
    }
}

public typealias DefaultEmptyString = Default<Defaults.EmptyString>
public typealias DefaultFalse = Default<Defaults.False>
public typealias DefaultTrue = Default<Defaults.True>
public typealias DefaultZero = Default<Defaults.Zero>
public typealias DefaultEmpty<Element: Codable & Sendable & Hashable> = Default<Defaults.Empty<Element>>
