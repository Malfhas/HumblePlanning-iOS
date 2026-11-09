import Foundation

/// A block of an answer.
public enum MarkdownBlock: Sendable, Hashable {
    /// `#` to `######` then a space; `level` is the number of `#` (Android draws every level alike).
    case heading(level: Int, [MarkdownInline])
    /// A line starting with `-`, `*` or `•` then a space, indented or not.
    case bullet([MarkdownInline])
    /// Lines up to a blank line, each trimmed, joined with `\n`.
    case paragraph([MarkdownInline])

    public var inlines: [MarkdownInline] {
        switch self {
        case .heading(_, let inlines), .bullet(let inlines), .paragraph(let inlines): inlines
        }
    }
}

/// A run of text inside a block. Runs do not nest.
public enum MarkdownInline: Sendable, Hashable {
    case text(String)
    /// `**x**`, markers removed.
    case bold(String)
    /// `` `x` ``, markers removed.
    case code(String)

    public var content: String {
        switch self {
        case .text(let text), .bold(let text), .code(let text): text
        }
    }
}

extension Array where Element == MarkdownInline {
    /// The text without its markers (accessibility, copy).
    public var plainText: String { map(\.content).joined() }
}

/// The light Markdown of the assistant's answers (`Markdown.kt` of the Android app, no library): headings,
/// bullets and paragraphs, with bold and inline code inside. Everything else stays literal: italics,
/// links, numbered lists, tables, quotes, fenced code (its backticks pair up inline).
///
/// An unclosed marker stays literal, so an answer still streaming never flickers into bold.
public enum Markdown {
    public static func blocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph = ""
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(inlines(paragraph))) }
            paragraph = ""
        }
        for line in text.kotlinLines {
            if line.isKotlinBlank {
                flush()
            } else if let item = bullet(line) {
                flush()
                blocks.append(.bullet(inlines(item)))
            } else if case let (level, title)? = heading(line.kotlinTrimmed) {
                flush()
                blocks.append(.heading(level: level, inlines(title)))
            } else {
                if !paragraph.isEmpty { paragraph += "\n" }
                paragraph += line.kotlinTrimmed
            }
        }
        flush()
        return blocks
    }

    /// `**bold**` and `` `code` ``, read left to right; a marker needs its closing one after at least one
    /// character, or it stays as text.
    public static func inlines(_ text: String) -> [MarkdownInline] {
        let scalars = Array(text.unicodeScalars)
        var runs: [MarkdownInline] = []
        var literal = String.UnicodeScalarView()
        func run(_ make: (String) -> MarkdownInline, _ range: Range<Int>) {
            if !literal.isEmpty { runs.append(.text(String(literal))) }
            literal = String.UnicodeScalarView()
            runs.append(make(String(String.UnicodeScalarView(scalars[range]))))
        }
        var i = 0
        while i < scalars.count {
            if scalars[i] == "*", i + 1 < scalars.count, scalars[i + 1] == "*",
               let end = firstIndex(of: ["*", "*"], in: scalars, from: i + 2), end > i + 2 {
                run(MarkdownInline.bold, i + 2..<end)
                i = end + 2
            } else if scalars[i] == "`", let end = firstIndex(of: ["`"], in: scalars, from: i + 1), end > i + 1 {
                run(MarkdownInline.code, i + 1..<end)
                i = end + 1
            } else {
                literal.append(scalars[i])
                i += 1
            }
        }
        if !literal.isEmpty { runs.append(.text(String(literal))) }
        return runs
    }

    /// `^\s*[-*•]\s+(.*)$` on the raw line: the item's text.
    private static func bullet(_ line: String) -> String? {
        let scalars = Array(line.unicodeScalars)
        var i = 0
        while i < scalars.count, scalars[i].isRegexSpace { i += 1 }
        guard i < scalars.count, ["-", "*", "•"].contains(scalars[i]) else { return nil }
        i += 1
        return rest(of: scalars, afterSpacesFrom: i)
    }

    /// `^#{1,6}\s+(.*)$` on the trimmed line: the level and the title.
    private static func heading(_ line: String) -> (Int, String)? {
        let scalars = Array(line.unicodeScalars)
        var level = 0
        while level < scalars.count, scalars[level] == "#" { level += 1 }
        guard (1...6).contains(level), let title = rest(of: scalars, afterSpacesFrom: level) else { return nil }
        return (level, title)
    }

    /// `\s+(.*)$` from `start`: at least one space, then a rest that `.` matches whole.
    private static func rest(of scalars: [Unicode.Scalar], afterSpacesFrom start: Int) -> String? {
        var i = start
        guard i < scalars.count, scalars[i].isRegexSpace else { return nil }
        while i < scalars.count, scalars[i].isRegexSpace { i += 1 }
        let rest = scalars[i...]
        guard !rest.contains(where: \.isRegexLineTerminator) else { return nil }
        return String(String.UnicodeScalarView(rest))
    }

    private static func firstIndex(of marker: [Unicode.Scalar], in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        guard start <= scalars.count - marker.count else { return nil }
        return (start...(scalars.count - marker.count)).first { scalars[$0..<$0 + marker.count].elementsEqual(marker) }
    }
}
