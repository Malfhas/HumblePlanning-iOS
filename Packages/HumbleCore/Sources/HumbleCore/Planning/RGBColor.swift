import Foundation

/// An opaque colour of the server (`#RRGGBB`), without any UI framework.
public struct RGBColor: Hashable, Sendable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `"#RRGGBB"` or `"RRGGBB"` (exactly 6 hex digits once trimmed); nil when missing or anything else,
    /// and the caller falls back on a colour of the theme.
    public init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.utf8.count == 6, text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// Text on the darkest backgrounds.
    public static let white = RGBColor(red: 0xFF, green: 0xFF, blue: 0xFF)
    /// Text on the lightest backgrounds.
    public static let darkText = RGBColor(red: 0x18, green: 0x18, blue: 0x1B)
    /// Holiday without a colour of its own, as on the web planning.
    public static let holiday = RGBColor(red: 0xF9, green: 0x73, blue: 0x16)

    /// `#RRGGBB`, upper case.
    public var hex: String {
        func byte(_ value: UInt8) -> String {
            let text = String(value, radix: 16, uppercase: true)
            return text.count == 1 ? "0" + text : text
        }
        return "#" + byte(red) + byte(green) + byte(blue)
    }

    public var description: String { hex }

    /// Channels from 0 to 1, for `Color(red:green:blue:)`.
    public var components: (red: Double, green: Double, blue: Double) {
        (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
    }

    /// WCAG relative luminance, 0 (black) to 1 (white).
    public var luminance: Double {
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Text on this background must be dark (`#18181B`) rather than white: luminance above 0.55.
    public var contentColorIsDark: Bool { luminance > 0.55 }

    /// Readable text on this background: grid bars, avatar initials.
    public var contentColor: RGBColor { contentColorIsDark ? .darkText : .white }
}

/// Opacities the planning lays its colours with.
public enum PlanningTints {
    /// Holiday colour behind labels, day headers and month cells.
    public static let holidayLabel = 0.19
    /// Holiday colour over a grid column.
    public static let holidayColumn = 0.08
    /// `primaryContainer` over today's grid column.
    public static let todayColumn = 0.45
    /// `surfaceContainerHigh` over a weekend grid column.
    public static let weekendColumn = 0.6
}
