import SwiftUI
import HumbleCore

/// Colours of the app: the system ones (they follow light/dark and the glass), plus the violet of the
/// brand as the accent and three tones for messages.
enum Palette {
    static let brandStart = Color(red: 0x5A / 255, green: 0x17 / 255, blue: 0xFF / 255)
    static let brandEnd = Color(red: 0xCF / 255, green: 0x9B / 255, blue: 0xFF / 255)
    static let warning = Color(light: 0xB45309, dark: 0xFBBF24)
    static let success = Color(light: 0x15803D, dark: 0x4ADE80)
    static let danger = Color(light: 0xDC2626, dark: 0xF87171)
    /// Text on colours of the server (projects, statuses, people).
    static let darkText = Color(hex: 0x18181B)

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brandStart, brandEnd], startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    /// `#RRGGBB` or `RRGGBB` of the server, nil otherwise.
    init?(serverHex value: String?) {
        guard let rgb = RGBColor(hex: value) else { return nil }
        self.init(rgb)
    }

    init(_ rgb: RGBColor) {
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

/// The light or dark choice of the settings.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
