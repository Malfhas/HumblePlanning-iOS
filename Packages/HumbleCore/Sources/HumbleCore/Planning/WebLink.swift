import Foundation

/// The link check of the task form: what OkHttp's `toHttpUrlOrNull()` accepts on Android. An `http` or `https`
/// scheme (any case) and a valid host; the rest of the address is accepted as typed (OkHttp encodes it).
enum WebLink {
    static func isValid(_ text: String) -> Bool {
        let chars = Array(text.unicodeScalars)
        guard let schemeEnd = schemeDelimiter(chars) else { return false }
        let scheme = String(String.UnicodeScalarView(chars[..<schemeEnd])).lowercased()
        guard scheme == "http" || scheme == "https" else { return false }
        var pos = schemeEnd + 1
        while pos < chars.count, chars[pos] == "/" || chars[pos] == "\\" { pos += 1 }
        // The authority ends at the first of / \ ? #; the user info before its last @
        var end = pos
        while end < chars.count, !"/\\?#".unicodeScalars.contains(chars[end]) { end += 1 }
        if let at = chars[pos..<end].lastIndex(of: "@") { pos = at + 1 }
        let authority = Array(chars[pos..<end])
        let colon = portColon(authority)
        if colon + 1 < authority.count {
            guard let port = Int(String(String.UnicodeScalarView(authority[(colon + 1)...]))), (1...65535).contains(port)
            else { return false }
        }
        return isValidHost(percentDecoded(Array(authority[..<colon])))
    }

    /// Index of the `:` ending a scheme: a letter, then letters, digits, `+`, `-` or `.`.
    private static func schemeDelimiter(_ chars: [Unicode.Scalar]) -> Int? {
        guard chars.count >= 2, chars[0].isASCII, chars[0].properties.isAlphabetic else { return nil }
        for index in 1..<chars.count {
            let c = chars[index]
            if c == ":" { return index }
            guard c.isASCII, c.properties.isAlphabetic || ("0"..."9").contains(c) || "+-.".unicodeScalars.contains(c)
            else { return nil }
        }
        return nil
    }

    /// The `:` before the port, outside an IPv6 `[…]`; the end when there is none.
    private static func portColon(_ chars: [Unicode.Scalar]) -> Int {
        var index = 0
        while index < chars.count {
            switch chars[index] {
            case "[":
                while index < chars.count, chars[index] != "]" { index += 1 }
            case ":": return index
            default: break
            }
            index += 1
        }
        return chars.count
    }

    private static func percentDecoded(_ chars: [Unicode.Scalar]) -> String {
        var bytes: [UInt8] = []
        var index = 0
        while index < chars.count {
            if chars[index] == "%", index + 2 < chars.count,
               let byte = UInt8(String(String.UnicodeScalarView(chars[(index + 1)...(index + 2)])), radix: 16) {
                bytes.append(byte)
                index += 3
            } else {
                bytes.append(contentsOf: Array(String(chars[index]).utf8))
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func isValidHost(_ host: String) -> Bool {
        if host.contains(":") {
            // IPv6, in brackets or not
            let inner = host.hasPrefix("[") && host.hasSuffix("]") ? host.dropFirst().dropLast() : Substring(host)
            return inner.filter { $0 == ":" }.count >= 2
                && inner.unicodeScalars.allSatisfy { $0.properties.isASCIIHexDigit || $0 == ":" || $0 == "." }
        }
        let forbidden = " #%/:?@[\\]".unicodeScalars
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ !($0.value <= 0x1F || (0x7F...0x9F).contains($0.value) || forbidden.contains($0)) })
        else { return false }
        // Labels of 1 to 63 characters (a final dot allowed), 253 at most in all
        guard host.utf8.count <= 253 else { return false }
        var labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count > 1, labels.last?.isEmpty == true { labels.removeLast() }
        return labels.allSatisfy { !$0.isEmpty && (!$0.allSatisfy(\.isASCII) || $0.utf8.count <= 63) }
    }
}
