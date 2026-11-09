import Foundation

/// How the approval card shows a tool call to a person rather than to a parser.
public enum ToolCallText {
    /// `create_task`, `createTask`, `create-task` → `Create task`.
    public static func readableToolName(_ name: String) -> String {
        var spaced = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in name.unicodeScalars {
            if let previous, ("a"..."z").contains(previous) || ("0"..."9").contains(previous), ("A"..."Z").contains(scalar) {
                spaced.append(" ")
            }
            spaced.append(scalar == "_" || scalar == "-" ? " " : scalar)
            previous = scalar
        }
        let words = String(spaced).kotlinTrimmed.lowercased()
        guard let first = words.first else { return "" }
        return first.uppercased() + words.dropFirst()
    }

    /// Input of a tool as indented `key: value` lines (two spaces a level), array items as `- item`, keys
    /// in their order. The nulls of an object are skipped; a null array item is a bare `- `.
    public static func readableJSON(_ value: JSONValue?, indent: String = "") -> String {
        switch value {
        case nil, .null?:
            return ""
        case .array(let items)?:
            return items.map { item in
                item.isPrimitive ? "\(indent)- \(item.content ?? "")" : "\(indent)-\n" + readableJSON(item, indent: indent + "  ")
            }.joined(separator: "\n")
        case .object(let object)?:
            return object.filter { $0.value != .null }.map { member in
                member.value.isPrimitive
                    ? "\(indent)\(member.key): \(member.value.content ?? "")"
                    : "\(indent)\(member.key):\n" + readableJSON(member.value, indent: indent + "  ")
            }.joined(separator: "\n")
        case let primitive?:
            return primitive.content ?? ""
        }
    }
}

extension PendingApproval {
    /// Title of the approval card.
    public var readableToolName: String { ToolCallText.readableToolName(toolName) }

    /// Body of the approval card, nil when there is nothing to show (no input box then).
    public var readableInput: String? {
        let text = ToolCallText.readableJSON(input)
        return text.isKotlinBlank ? nil : text
    }
}
