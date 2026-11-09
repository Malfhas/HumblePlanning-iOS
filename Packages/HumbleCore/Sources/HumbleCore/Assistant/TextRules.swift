import Foundation

// The text rules of the Android app (Kotlin strings, Java regular expressions), so that what is blank,
// trimmed or split there is exactly the same here. They work on Unicode scalars, not on characters:
// a combining mark after a marker must not hide the marker.

extension Unicode.Scalar {
    /// `Char.isWhitespace()` of Kotlin on the JVM, used by `trim()` and `isBlank()`.
    var isKotlinWhitespace: Bool {
        switch value {
        case 0x09...0x0D, 0x1C...0x1F: true
        default:
            switch properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator: true
            default: false
            }
        }
    }

    /// `\s` of a Java regular expression: ASCII spaces only.
    var isRegexSpace: Bool { value == 0x20 || (0x09...0x0D).contains(value) }

    /// What `.` of a Java regular expression does not match.
    var isRegexLineTerminator: Bool { [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains(value) }
}

extension String {
    /// Kotlin's `trim()`.
    var kotlinTrimmed: String {
        let scalars = unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.isKotlinWhitespace }),
              let last = scalars.lastIndex(where: { !$0.isKotlinWhitespace }) else { return "" }
        return String(scalars[first...last])
    }

    /// Kotlin's `isBlank()`.
    var isKotlinBlank: Bool { unicodeScalars.allSatisfy(\.isKotlinWhitespace) }

    /// Kotlin's `lines()`: split on CRLF, LF and CR; `""` is one empty line.
    var kotlinLines: [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        var afterCarriageReturn = false
        for scalar in unicodeScalars {
            if scalar == "\n", afterCarriageReturn {
                afterCarriageReturn = false
                continue
            }
            afterCarriageReturn = scalar == "\r"
            if scalar == "\n" || scalar == "\r" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        lines.append(String(current))
        return lines
    }

    /// The rest after `prefix`, nil when the text does not start with it (Kotlin's `startsWith`).
    func dropping(prefix: String) -> String? {
        let scalars = unicodeScalars
        guard scalars.starts(with: prefix.unicodeScalars) else { return nil }
        return String(scalars.dropFirst(prefix.unicodeScalars.count))
    }
}

extension JSONValue {
    /// `contentOrNull` of a Kotlin JSON primitive: nil for `null`, and for arrays and objects (where the
    /// Android app would throw).
    var content: String? { self == .null ? nil : primitiveText }

    var isPrimitive: Bool {
        switch self {
        case .array, .object: false
        default: true
        }
    }
}
