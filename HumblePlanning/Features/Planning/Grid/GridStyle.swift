import UIKit
import HumbleCore

/// Colours and fonts of the team grid: the system surfaces and texts, the accent of the brand, and the tints
/// of the planning for the days and the lines (the same as on Android).
enum GridStyle {
    static let surface = UIColor.systemBackground
    static let teamHeader = UIColor.secondarySystemBackground
    static let teamHeaderPressed = UIColor.systemGray5
    static let accent = UIColor(named: "AccentColor") ?? .systemIndigo
    /// `primaryContainer`: today's header, and today's column at 45 %.
    static let today = UIColor(gridLight: 0xEDE5FF, dark: 0x3A1E8C)
    static let todayColumn = UIColor(gridLight: 0xEDE5FF, dark: 0x3A1E8C, alpha: PlanningTints.todayColumn)
    /// `surfaceContainerHigh`: weekend header, and weekend column at 60 %.
    static let weekend = UIColor(gridLight: 0xEBEBED, dark: 0x221F2B)
    static let weekendColumn = UIColor(gridLight: 0xEBEBED, dark: 0x221F2B, alpha: PlanningTints.weekendColumn)
    /// `outlineVariant`: grid lines; the lines of other days than Mondays at 50 %.
    static let line = UIColor(gridLight: 0xE4E4E7, dark: 0x2E2B37)
    static let dayLine = UIColor(gridLight: 0xE4E4E7, dark: 0x2E2B37, alpha: 0.5)
    /// `outline`: a team without colour.
    static let noTeamColor = UIColor(gridLight: 0xA1A1AA, dark: 0x71717A)

    static let weekFont = UIFont.systemFont(ofSize: 11, weight: .medium)
    static let dayFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    static let todayFont = UIFont.systemFont(ofSize: 12, weight: .bold)
    static let countFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    static let nameFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    static let meFont = UIFont.systemFont(ofSize: 12, weight: .bold)
    static let teamFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    static let barFont = UIFont.systemFont(ofSize: 11, weight: .medium)
    static let arrowFont = UIFont.systemFont(ofSize: 12, weight: .medium)

    static func color(_ rgb: RGBColor, alpha: Double = 1) -> UIColor {
        let (red, green, blue) = rgb.components
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Fill of a day column below the header; nil for an ordinary day.
    static func columnFill(_ column: GridColumn) -> UIColor? {
        if column.isToday { return todayColumn }
        if let holiday = column.holiday { return color(holiday.tint, alpha: PlanningTints.holidayColumn) }
        return column.isWeekend ? weekendColumn : nil
    }

    /// Fill of a day in the header; nil for an ordinary day.
    static func headerFill(_ column: GridColumn) -> UIColor? {
        if column.isToday { return today }
        if let holiday = column.holiday { return color(holiday.tint, alpha: PlanningTints.holidayLabel) }
        return column.isWeekend ? weekend : nil
    }
}

extension UIColor {
    convenience init(gridLight light: UInt32, dark: UInt32, alpha: Double = 1) {
        self.init { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
    }
}

extension CALayer {
    /// A layer that never animates on its own: the grid moves thousands of them while scrolling and pinching.
    static func still() -> CALayer {
        let layer = CALayer()
        layer.actions = stillActions
        return layer
    }

    private static let stillActions: [String: any CAAction] = Dictionary(uniqueKeysWithValues: [
        "position", "bounds", "contents", "backgroundColor", "hidden", "opacity", "sublayers",
        "onOrderIn", "onOrderOut", "transform", "cornerRadius",
    ].map { ($0, NSNull()) })
}

extension UIView {
    /// A plain rectangle of colour that lets touches through.
    static func gridFill(_ color: UIColor? = nil) -> UIView {
        let view = UIView()
        view.backgroundColor = color
        view.isUserInteractionEnabled = false
        return view
    }
}
