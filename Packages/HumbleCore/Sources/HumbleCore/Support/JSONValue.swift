import Foundation

/// Any JSON value, objects keeping the order of their keys: the tool inputs of the assistant are
/// shown in the order the server wrote them, and sent back as they came.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var objectValue: JSONObject? {
        if case .object(let value) = self { value } else { nil }
    }

    /// The text of a primitive (numbers become text, like `JsonPrimitive.content`), nil otherwise.
    public var primitiveText: String? {
        switch self {
        case .string(let value): value
        case .bool(let value): value ? "true" : "false"
        case .number(let value): JSONValue.format(value)
        case .null: "null"
        case .array, .object: nil
        }
    }

    static func format(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        return String(number)
    }
}

/// A JSON object with ordered keys.
public struct JSONObject: Sendable, Hashable, Sequence {
    public private(set) var members: [(key: String, value: JSONValue)]

    public init(_ members: [(key: String, value: JSONValue)] = []) {
        self.members = members
    }

    public subscript(key: String) -> JSONValue? {
        get { members.first { $0.key == key }?.value }
        set {
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append((key, newValue))
            }
        }
    }

    public var keys: [String] { members.map(\.key) }

    public func makeIterator() -> IndexingIterator<[(key: String, value: JSONValue)]> {
        members.makeIterator()
    }

    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        lhs.members.count == rhs.members.count && zip(lhs.members, rhs.members).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    public func hash(into hasher: inout Hasher) {
        for member in members {
            hasher.combine(member.key)
            hasher.combine(member.value)
        }
    }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    public typealias Key = String
    public typealias Value = JSONValue

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.init(elements.map { (key: $0.0, value: $0.1) })
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public typealias Key = String
    public typealias Value = JSONValue
    public typealias ArrayLiteralElement = JSONValue

    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(JSONObject(elements.map { (key: $0.0, value: $0.1) }))
    }
    public init(nilLiteral: ()) { self = .null }
}

// MARK: - Text

extension JSONValue {
    public struct ParseError: Error, Sendable {}

    /// Parses JSON text, keeping the order of object keys.
    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = Parser(bytes: Array(data))
        parser.skipSpaces()
        let value = try parser.value(depth: 0)
        parser.skipSpaces()
        guard parser.index == parser.bytes.count else { throw ParseError() }
        return value
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// Compact JSON text, keys in their order.
    public var serialized: String {
        var out = ""
        write(to: &out)
        return out
    }

    public var serializedData: Data { Data(serialized.utf8) }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(let value): out += value.isFinite ? JSONValue.format(value) : "null"
        case .string(let value): JSONValue.writeString(value, to: &out)
        case .array(let values):
            out += "["
            for (index, value) in values.enumerated() {
                if index > 0 { out += "," }
                value.write(to: &out)
            }
            out += "]"
        case .object(let object):
            out += "{"
            for (index, member) in object.members.enumerated() {
                if index > 0 { out += "," }
                JSONValue.writeString(member.key, to: &out)
                out += ":"
                member.value.write(to: &out)
            }
            out += "}"
        }
    }

    private static func writeString(_ value: String, to out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipSpaces() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws -> JSONValue {
            guard depth < 256, index < bytes.count else { throw ParseError() }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { throw ParseError() }
            index += expected.count
        }

        mutating func object(depth: Int) throws -> JSONValue {
            index += 1
            var object = JSONObject()
            skipSpaces()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
            while true {
                skipSpaces()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw ParseError() }
                let key = try string()
                skipSpaces()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ParseError() }
                index += 1
                skipSpaces()
                object[key] = try value(depth: depth + 1)
                skipSpaces()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
                throw ParseError()
            }
        }

        mutating func array(depth: Int) throws -> JSONValue {
            index += 1
            var values: [JSONValue] = []
            skipSpaces()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(values) }
            while true {
                skipSpaces()
                values.append(try value(depth: depth + 1))
                skipSpaces()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(values) }
                throw ParseError()
            }
        }

        mutating func string() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var raw: [UInt8] = []
            func flush() throws {
                guard !raw.isEmpty else { return }
                guard let text = String(bytes: raw, encoding: .utf8) else { throw ParseError() }
                scalars.append(contentsOf: text.unicodeScalars)
                raw.removeAll(keepingCapacity: true)
            }
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    index += 1
                    try flush()
                    return String(scalars)
                }
                if byte == UInt8(ascii: "\\") {
                    try flush()
                    index += 1
                    guard index < bytes.count else { throw ParseError() }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code), index + 1 < bytes.count,
                           bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            index += 2
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw ParseError() }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                    default: throw ParseError()
                    }
                    continue
                }
                guard byte >= 0x20 else { throw ParseError() }
                raw.append(byte)
                index += 1
            }
            throw ParseError()
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count, let code = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else { throw ParseError() }
            index += 4
            return code
        }

        mutating func number() throws -> Double {
            let start = index
            while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
            guard index > start, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else { throw ParseError() }
            return value
        }
    }
}

// MARK: - Codable (inside DTOs decoded by JSONDecoder: key order is not kept there)

extension JSONValue: Codable {
    private struct MemberKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        if let object = try? decoder.container(keyedBy: MemberKey.self) {
            var result = JSONObject()
            for key in object.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
                result[key.stringValue] = try object.decode(JSONValue.self, forKey: key)
            }
            self = .object(result)
        } else if var array = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !array.isAtEnd { values.append(try array.decode(JSONValue.self)) }
            self = .array(values)
        } else {
            let single = try decoder.singleValueContainer()
            if single.decodeNil() { self = .null }
            else if let value = try? single.decode(Bool.self) { self = .bool(value) }
            else if let value = try? single.decode(Double.self) { self = .number(value) }
            else { self = .string(try single.decode(String.self)) }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .object(let object):
            var container = encoder.container(keyedBy: MemberKey.self)
            for member in object.members { try container.encode(member.value, forKey: MemberKey(stringValue: member.key)) }
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }
}
