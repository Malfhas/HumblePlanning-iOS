import CoreText
import UIKit
import HumbleCore

/// Draws the content of the bars into bitmaps: "‹", the lock and as much of the title as fits, then "…".
/// A drawing depends on how much of the title fits, not on the width of the bar: while a pinch or a scroll
/// changes the width by a few points, the same drawing stays, and bars that look alike share it.
final class GridBarRenderer {
    /// How much of a title is drawn: all of it, its first UTF-16 units then "…", or nothing.
    enum Fit: Hashable {
        case none, full
        case prefix(Int)
    }

    struct Key: Hashable {
        let look: BarLook
        let leading: Bool
        let lock: Bool
        let fit: Fit
    }

    struct Drawing {
        let image: CGImage?
        /// Width in points, a whole number of pixels.
        let width: Double
    }

    private struct TextKey: Hashable {
        let bold: Bool
        let italic: Bool
        let dark: Bool
    }

    /// A title measured once: its width, and where each character ends.
    private struct Measure {
        let width: Double
        let ends: [(units: Int, x: Double)]
    }

    var scale: CGFloat = 3 {
        didSet {
            guard scale != oldValue else { return }
            drawings.removeAll()
            arrows.removeAll()
            locks.removeAll()
        }
    }

    /// Width of "‹" and "›".
    let arrowWidth: Double

    private var drawings: [Key: Drawing] = [:]
    private var measures: [BarLook: Measure] = [:]
    private var ellipsisWidths: [TextKey: Double] = [:]
    private var arrows: [Bool: CGImage] = [:]
    private var locks: [Bool: CGImage] = [:]
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let maxDrawings = 2000
    private static let titleGap = 2.0

    init() {
        arrowWidth = CTLineGetTypographicBounds(Self.line("›", font: GridStyle.arrowFont, dark: false), nil, nil, nil)
    }

    /// What of the title fits in `available` points.
    func fit(_ look: BarLook, available: Double) -> Fit {
        let measure = measure(look)
        if measure.width <= available { return .full }
        let limit = available - ellipsisWidth(look)
        guard limit >= 0 else { return .none }
        var low = 0, high = measure.ends.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if measure.ends[middle].x <= limit { low = middle } else { high = middle - 1 }
        }
        return .prefix(measure.ends[low].units)
    }

    /// The space taken before the title: "‹", the lock and the gap.
    func leadingWidth(leading: Bool, lock: Bool) -> Double {
        (leading ? arrowWidth : 0) + (lock ? GridMetrics.lockIconSize : 0) + Self.titleGap
    }

    func drawing(_ key: Key) -> Drawing {
        if let drawing = drawings[key] { return drawing }
        let drawing = draw(key)
        if drawings.count >= Self.maxDrawings { drawings.removeAll(keepingCapacity: true) }
        drawings[key] = drawing
        return drawing
    }

    /// "›", in the colour of the text of the bar.
    func arrow(dark: Bool) -> CGImage? {
        if let image = arrows[dark] { return image }
        let image = bitmap(width: arrowWidth) { context in
            Self.draw(Self.line("›", font: GridStyle.arrowFont, dark: dark), font: GridStyle.arrowFont, in: context, at: 0)
        }
        arrows[dark] = image
        return image
    }

    // MARK: Drawing

    private func draw(_ key: Key) -> Drawing {
        let look = key.look
        let dark = look.textIsDark
        let font = Self.titleFont(bold: look.bold, italic: look.italic)
        let title: CTLine? = switch key.fit {
        case .none: nil
        case .full: Self.line(look.title, font: font, dark: dark)
        case .prefix(let units):
            Self.line(Self.prefix(look.title, units: units) + "…", font: font, dark: dark)
        }
        let titleWidth = title.map { CTLineGetTypographicBounds($0, nil, nil, nil) } ?? 0
        let start = (key.leading ? arrowWidth : 0) + (key.lock ? GridMetrics.lockIconSize : 0)
        let width = title == nil ? start : start + Self.titleGap + titleWidth
        let lock = key.lock ? lockImage(dark: dark) : nil
        let image = bitmap(width: width) { context in
            var x = 0.0
            if key.leading {
                Self.draw(Self.line("‹", font: GridStyle.arrowFont, dark: dark), font: GridStyle.arrowFont, in: context, at: x)
                x += arrowWidth
            }
            if let lock {
                let size = GridMetrics.lockIconSize
                context.draw(lock, in: CGRect(x: x, y: (GridMetrics.barHeight - size) / 2, width: size, height: size))
            }
            guard let title else { return }
            let left = start + Self.titleGap
            let baseline = Self.draw(title, font: font, in: context, at: left)
            context.setFillColor(Self.textColor(dark: dark))
            let thickness = max(CTFontGetUnderlineThickness(font), 1 / scale)
            if look.underline {
                context.fill(CGRect(x: left, y: baseline + CTFontGetUnderlinePosition(font) - thickness / 2, width: titleWidth, height: thickness))
            }
            if look.strikethrough {
                context.fill(CGRect(x: left, y: baseline + CTFontGetXHeight(font) / 2 - thickness / 2, width: titleWidth, height: thickness))
            }
        }
        return Drawing(image: image, width: image.map { Double($0.width) / scale } ?? 0)
    }

    /// A transparent bitmap the height of a bar, drawn in points with the origin at the bottom left.
    private func bitmap(width: Double, draw: (CGContext) -> Void) -> CGImage? {
        let pixels = Int((width * scale).rounded(.up))
        let height = Int((GridMetrics.barHeight * scale).rounded())
        guard pixels > 0,
              let context = CGContext(data: nil, width: pixels, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = .identity
        draw(context)
        return context.makeImage()
    }

    private func measure(_ look: BarLook) -> Measure {
        if let measure = measures[look] { return measure }
        let line = Self.line(look.title, font: Self.titleFont(bold: look.bold, italic: look.italic), dark: false)
        var ends: [(units: Int, x: Double)] = [(0, 0)]
        var units = 0
        for character in look.title {
            units += character.utf16.count
            ends.append((units, CTLineGetOffsetForStringIndex(line, units, nil)))
        }
        let measure = Measure(width: CTLineGetTypographicBounds(line, nil, nil, nil), ends: ends)
        measures[look] = measure
        return measure
    }

    private func ellipsisWidth(_ look: BarLook) -> Double {
        let key = TextKey(bold: look.bold, italic: look.italic, dark: false)
        if let width = ellipsisWidths[key] { return width }
        let width = CTLineGetTypographicBounds(Self.line("…", font: Self.titleFont(bold: look.bold, italic: look.italic), dark: false), nil, nil, nil)
        ellipsisWidths[key] = width
        return width
    }

    private func lockImage(dark: Bool) -> CGImage? {
        if let image = locks[dark] { return image }
        let size = GridMetrics.lockIconSize
        let symbol = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8.5, weight: .semibold))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { _ in
            guard let symbol else { return }
            let tinted = symbol.withTintColor(UIColor(cgColor: Self.textColor(dark: dark)), renderingMode: .alwaysOriginal)
            let ratio = min(size / symbol.size.width, size / symbol.size.height)
            let fitted = CGSize(width: symbol.size.width * ratio, height: symbol.size.height * ratio)
            tinted.draw(in: CGRect(x: (size - fitted.width) / 2, y: (size - fitted.height) / 2, width: fitted.width, height: fitted.height))
        }.cgImage
        locks[dark] = image
        return image
    }

    /// The first `units` UTF-16 units of `text`, without the spaces before the "…".
    private static func prefix(_ text: String, units: Int) -> String {
        let end = String.Index(utf16Offset: units, in: text)
        var prefix = text[..<end]
        while prefix.last?.isWhitespace == true { prefix.removeLast() }
        return String(prefix)
    }

    /// Draws `line` centred in the height of a bar; returns its baseline.
    @discardableResult
    private static func draw(_ line: CTLine, font: UIFont, in context: CGContext, at x: Double) -> Double {
        let ascent = font.ascender, descent = -font.descender
        let baseline = (GridMetrics.barHeight - (ascent + descent)) / 2 + descent
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        return baseline
    }

    private static func line(_ text: String, font: UIFont, dark: Bool) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor(dark: dark),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func titleFont(bold: Bool, italic: Bool) -> UIFont {
        switch (bold, italic) {
        case (false, false): regular
        case (true, false): boldFont
        case (false, true): italicFont
        case (true, true): boldItalicFont
        }
    }

    private static let regular = GridStyle.barFont
    private static let boldFont = UIFont.systemFont(ofSize: GridStyle.barFont.pointSize, weight: .bold)
    private static let italicFont = italic(regular)
    private static let boldItalicFont = italic(boldFont)

    private static func italic(_ font: UIFont) -> UIFont {
        font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic))
            .map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
    }

    private static let darkText = GridStyle.color(.darkText).cgColor
    private static let whiteText = GridStyle.color(.white).cgColor

    private static func textColor(dark: Bool) -> CGColor { dark ? darkText : whiteText }
}

/// One bar on screen: its colour with rounded corners, its content and its "›". Reused as bars scroll in and
/// out of sight; edges and content sit on whole pixels so that the text stays sharp at any width.
final class GridBarNode {
    let fill = CALayer.still()
    private let content = CALayer.still()
    private let trailing = CALayer.still()
    /// Pass of the viewport that last showed it.
    var pass = 0
    /// Layout of the grid it was placed for (`-1`: not yet).
    var generation = -1
    /// Its start was out of sight: its content follows the left edge.
    var followsEdge = false
    private var frame = CGRect.null
    private var contentFrame = CGRect.null
    private var key: GridBarRenderer.Key?
    private var contentWidth = 0.0
    private var color: RGBColor??
    private var trailingDark: Bool?

    init() {
        fill.cornerRadius = GridMetrics.barCornerRadius
        fill.cornerCurve = .continuous
        fill.addSublayer(content)
        fill.addSublayer(trailing)
    }

    /// Shows another bar.
    func reset() {
        generation = -1
        followsEdge = false
        frame = .null
        contentFrame = .null
        key = nil
        color = nil
        trailingDark = nil
        fill.isHidden = false
    }

    /// Places the bar and its content for the horizontal scroll `scrollX` (from the left edge of the first day).
    func apply(_ bar: GridPlan.Bar, origin: CGPoint, cellWidth: Double, scrollX: Double, renderer: GridBarRenderer,
               traits: UITraitCollection) {
        let scale = renderer.scale
        let geometry = GridMetrics.geometry(of: bar.bar, cellWidth: cellWidth)
        let shape = geometry.frame
        let left = ((origin.x + shape.x) * scale).rounded() / scale
        let right = ((origin.x + shape.x + shape.width) * scale).rounded() / scale
        let newFrame = CGRect(x: left, y: origin.y + shape.y, width: max(right - left, 1 / scale), height: shape.height)
        if newFrame != frame {
            frame = newFrame
            fill.frame = newFrame
        }
        let look = bar.look
        if color != .some(look.color) {
            color = .some(look.color)
            fill.backgroundColor = Self.fill(look.color, traits: traits)
        }

        let padding = GridMetrics.barPadding
        let shift = (geometry.contentShift(scrollX: scrollX) * scale).rounded(.down) / scale
        let leading = bar.bar.continuesBefore || geometry.startHidden(scrollX: scrollX)
        let lock = geometry.showsLock(look.locked)
        let available = newFrame.width - 2 * padding - shift - renderer.leadingWidth(leading: leading, lock: lock)
            - (bar.bar.continuesAfter ? renderer.arrowWidth : 0)
        let fit = geometry.showsTitle ? renderer.fit(look, available: available) : .none
        let newKey = GridBarRenderer.Key(look: look, leading: leading, lock: lock, fit: fit)
        if newKey != key {
            key = newKey
            let drawing = renderer.drawing(newKey)
            content.contentsScale = scale
            content.contents = drawing.image
            contentWidth = drawing.width
        }
        let newContentFrame = CGRect(x: padding + shift, y: 0, width: contentWidth, height: shape.height)
        if newContentFrame != contentFrame {
            contentFrame = newContentFrame
            content.frame = newContentFrame
        }

        let dark = bar.bar.continuesAfter ? look.textIsDark : nil
        if dark != trailingDark {
            trailingDark = dark
            trailing.isHidden = dark == nil
            trailing.contentsScale = scale
            trailing.contents = dark.flatMap { renderer.arrow(dark: $0) }
        }
        if dark != nil {
            let width = (renderer.arrowWidth * scale).rounded(.up) / scale
            let arrowFrame = CGRect(x: ((newFrame.width - padding - width) * scale).rounded() / scale, y: 0, width: width, height: shape.height)
            if arrowFrame != trailing.frame { trailing.frame = arrowFrame }
        }
    }

    /// After a change of light or dark mode: the accent of bars without colour changes.
    func refreshColor(traits: UITraitCollection) {
        if case .some(let rgb) = color { fill.backgroundColor = Self.fill(rgb, traits: traits) }
    }

    /// A short dimming when tapped.
    func flash() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.45
        animation.toValue = 1
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fill.add(animation, forKey: "flash")
    }

    private static func fill(_ rgb: RGBColor?, traits: UITraitCollection) -> CGColor {
        (rgb.map { GridStyle.color($0) } ?? GridStyle.accent).resolvedColor(with: traits).cgColor
    }
}
