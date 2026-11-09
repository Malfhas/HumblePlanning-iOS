import Foundation

/// Sizes of the team grid, in points, and the arithmetic of its bars, scrolling and pinching.
public enum GridMetrics {
    public static let barHeight = 22.0
    public static let barGap = 3.0
    public static let rowPadding = 5.0
    public static let rowMinHeight = 44.0
    public static let dayHeaderHeight = 48.0
    public static let teamHeaderHeight = 36.0
    /// Inset of a bar on each side, its corner radius and its inner horizontal padding.
    public static let barInset = 1.0
    public static let barCornerRadius = 5.0
    public static let barPadding = 4.0
    /// Narrower bars show their colour only.
    public static let minTitleWidth = 30.0
    /// Narrower bars show no lock.
    public static let minLockWidth = 40.0
    public static let lockIconSize = 11.0
    /// Narrower columns write the day number alone.
    public static let weekdayLabelMinWidth = 40.0

    /// Width of a day: bounds, default (kept from one launch to the next, clamped when read) and the menu presets.
    public static let minCellWidth = 24.0
    public static let defaultCellWidth = 56.0
    public static let maxCellWidth = 140.0
    public static let compactCellWidth = 32.0
    public static let wideCellWidth = 96.0
    public static let presets = [compactCellWidth, defaultCellWidth, wideCellWidth]

    public static func clampedCellWidth(_ width: Double) -> Double { min(max(width, minCellWidth), maxCellWidth) }

    /// The preset ticked in the width menu: the nearest one (the narrower on a tie).
    public static func nearestPreset(to width: Double) -> Double {
        presets.min { abs($0 - width) < abs($1 - width) } ?? defaultCellWidth
    }

    /// The column of names: wider on a tablet (content of 600 points or more).
    public static func nameColumnWidth(contentWidth: Double) -> Double { contentWidth >= 600 ? 168 : 108 }

    public static func rowHeight(lanes: Int) -> Double {
        max(rowMinHeight, rowPadding * 2 + (barHeight + barGap) * Double(lanes) - barGap)
    }

    /// Where a bar goes in its row, from the left edge of the first day.
    public static func geometry(of bar: GridBar, cellWidth: Double) -> GridBarGeometry {
        let half = cellWidth / 2
        let x = cellWidth * Double(bar.first) + (bar.part == .afternoon ? half : 0)
        let width = cellWidth * Double(bar.last - bar.first + 1) - (bar.part == .whole ? 0 : half)
        return GridBarGeometry(x: x, y: rowPadding + (barHeight + barGap) * Double(bar.lane), width: width)
    }

    /// The day under a tap on an empty spot of a row (`x` from the left edge of the first day).
    public static func column(atX x: Double, cellWidth: Double, days: Int) -> Int {
        min(max(Int(x / cellWidth), 0), max(days - 1, 0))
    }

    /// Scroll offset that puts the day before the selected one first: on opening, "Today", a date or a month chosen.
    public static func focusOffset(selected: CalendarDay, period: DayRange, cellWidth: Double) -> Double {
        let index = min(max(period.lowerBound.days(to: selected), 0), period.count - 1)
        return Double(max(index - 1, 0)) * cellWidth
    }

    /// A pinch: the new day width and the scroll offset that keeps the content under the fingers in place.
    /// `focusX` is the centroid of the fingers minus the width of the names column.
    public static func zoom(cellWidth before: Double, scale: Double, focusX: Double,
                            scrollX: Double) -> (cellWidth: Double, scrollX: Double) {
        let after = clampedCellWidth(before * scale)
        return (after, (scrollX + focusX) * (after / before) - focusX)
    }
}

/// A bar in its row: `x` and `width` cover its days (half a day for a morning or an afternoon); the drawn shape
/// is `frame`, inset by one point on each side.
public struct GridBarGeometry: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double

    public var frame: (x: Double, y: Double, width: Double, height: Double) {
        (x + GridMetrics.barInset, y, width - 2 * GridMetrics.barInset, GridMetrics.barHeight)
    }

    public var showsTitle: Bool { width >= GridMetrics.minTitleWidth }
    public func showsLock(_ locked: Bool) -> Bool { locked && width >= GridMetrics.minLockWidth }

    /// Where the content starts in the scrolled grid.
    public var contentStart: Double { x + GridMetrics.barInset + GridMetrics.barPadding }

    /// The start of the bar is scrolled out of sight: a "‹" leads its content.
    public func startHidden(scrollX: Double) -> Bool { scrollX > contentStart }

    /// The content follows the left edge of the grid when the start of the bar is out of sight, so that the
    /// title of a long task stays readable; it stops `minTitleWidth` before the end of the bar.
    public func contentShift(scrollX: Double) -> Double {
        let inner = width - 2 * GridMetrics.barInset - 2 * GridMetrics.barPadding
        return min(max(scrollX - contentStart, 0), max(inner - GridMetrics.minTitleWidth, 0))
    }
}
