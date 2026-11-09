import Foundation

/// Photo of a person: the server keeps `avatars/<file>` and serves it at `<server>/api/avatars/<file>`.
/// A bare file name only, never an address elsewhere nor a way out of the folder. The WebP copy is asked
/// rather than the AVIF one, as on Android (the server writes both). Load it with the session cookie.
public func avatarURL(server: String, image: String?) -> URL? {
    guard var file = image?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    for prefix in ["/api/avatars/", "avatars/"] where file.hasPrefix(prefix) { file.removeFirst(prefix.count) }
    let allowed: (Unicode.Scalar) -> Bool = { scalar in
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" || scalar == ".")
    }
    guard let first = file.unicodeScalars.first, first != ".", file.unicodeScalars.allSatisfy(allowed) else { return nil }
    if file.lowercased().hasSuffix(".avif") { file = String(file.dropLast(5)) + ".webp" }
    return URL(string: "\(server)/api/avatars/\(file)")
}

/// Initials on the colour of a person: the first letter or digit of the first two words (split on spaces and
/// dashes), upper case.
public func avatarInitials(_ name: String) -> String {
    name.split(omittingEmptySubsequences: false) { $0 == " " || $0 == "-" }
        .compactMap { word in word.first { $0.isLetter || $0.isNumber } }
        .prefix(2)
        .map(String.init)
        .joined()
        .uppercased()
}

/// A file name of the server or of the phone, as a name inside a folder: never a path. Keeps what follows the
/// last `/` and `\`, drops control characters, trims, removes leading dots; `fallback` when nothing is left.
public func safeFileName(_ name: String, fallback: String) -> String {
    let last = name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? name
    let base = last.split(separator: "\\", omittingEmptySubsequences: false).last.map(String.init) ?? last
    var scalars = String.UnicodeScalarView()
    scalars.append(contentsOf: base.unicodeScalars.filter { !(0x00...0x1F ~= $0.value || 0x7F...0x9F ~= $0.value) })
    let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "." }
    return trimmed.isEmpty ? fallback : String(trimmed)
}
