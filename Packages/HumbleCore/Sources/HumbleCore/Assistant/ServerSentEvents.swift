import Foundation

/// One line of a turn's response body (server-sent events of the AI SDK UI message stream).
public enum SSELine: Sendable, Hashable {
    /// `data: [DONE]`: the stream is over.
    case done
    /// A `data:` line holding a JSON object, for ``ReplyBuilder/accept(_:)``.
    case event(JSONObject)

    /// Reads one line of the body; nil for anything else than a `data:` line holding `[DONE]` or a JSON
    /// object: `event:`, `id:`, comments, blank lines and unparsable data are skipped.
    public static func parse(_ line: String) -> SSELine? {
        guard let data = line.dropping(prefix: "data:")?.kotlinTrimmed else { return nil }
        if data == "[DONE]" { return .done }
        guard let event = (try? JSONValue.parse(data))?.objectValue else { return nil }
        return .event(event)
    }
}

/// The lines of a body as the Android app reads them (OkHttp's `readUtf8Line`): split on LF only, a CR
/// before it dropped, empty lines kept, a last line without LF kept unless empty, UTF-8 decoded with
/// replacement characters.
///
/// Prefer it to Foundation's `lines`, which also splits on U+2028, U+2029, U+0085 and a lone CR: JSON
/// text may carry U+2028 raw inside a string, and a `data:` line cut there loses its event.
public struct SSELineSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    public typealias Element = String

    let base: Base

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        var ended = false

        public mutating func next() async throws -> String? {
            guard !ended else { return nil }
            var line: [UInt8] = []
            while let byte = try await base.next() {
                if byte == 0x0A {
                    if line.last == 0x0D { line.removeLast() }
                    return String(decoding: line, as: UTF8.self)
                }
                line.append(byte)
            }
            ended = true
            return line.isEmpty ? nil : String(decoding: line, as: UTF8.self)
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator())
    }
}

extension SSELineSequence: Sendable where Base: Sendable {}

extension AsyncSequence where Element == UInt8 {
    /// The lines of this body for ``SSELine/parse(_:)``: see ``SSELineSequence``.
    public var sseLines: SSELineSequence<Self> { SSELineSequence(base: self) }
}
