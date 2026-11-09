import UIKit
import HumbleCore

/// The initials of a person on their colour, then their photo once loaded.
final class GridAvatarView: UIView {
    private let initials = UILabel()
    private let photo = UIImageView()
    private(set) var imageKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        initials.textAlignment = .center
        photo.contentMode = .scaleAspectFill
        addSubview(initials)
        addSubview(photo)
        layer.borderWidth = 1
        refreshBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GridAvatarView, _) in view.refreshBorder() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ user: User, image: UIImage?) {
        let rgb = RGBColor(hex: user.color)
        backgroundColor = rgb.map { GridStyle.color($0) } ?? .secondarySystemFill
        initials.text = avatarInitials(user.displayName)
        initials.textColor = rgb.map { GridStyle.color($0.contentColor) } ?? .label
        imageKey = Self.imageKey(user)
        show(image)
    }

    func show(_ image: UIImage?) {
        photo.image = image
        photo.isHidden = image == nil
    }

    static func imageKey(_ user: User) -> String? {
        guard let image = user.image, !image.isEmpty else { return nil }
        return user.id + "|" + image
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        initials.frame = bounds
        initials.font = .systemFont(ofSize: bounds.width * 0.38, weight: .semibold)
        photo.frame = bounds
    }

    private func refreshBorder() {
        layer.borderColor = UIColor.label.withAlphaComponent(0.1).resolvedColor(with: traitCollection).cgColor
    }
}

/// A person in the names column: avatar and name, the user's own name in bold and in the accent.
final class GridNameCell: UIView {
    let avatar = GridAvatarView()
    private let name = UILabel()
    private let bottomLine = UIView.gridFill(GridStyle.line)
    private let rightLine = UIView.gridFill(GridStyle.line)
    private(set) var userId = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = GridStyle.surface
        isUserInteractionEnabled = false
        name.numberOfLines = 2
        name.lineBreakMode = .byTruncatingTail
        for view in [avatar, name, bottomLine, rightLine] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ user: User, isMe: Bool, image: UIImage?) {
        userId = user.id
        avatar.configure(user, image: image)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 14
        style.maximumLineHeight = 14
        style.lineBreakMode = .byTruncatingTail
        name.attributedText = NSAttributedString(string: user.displayName, attributes: [
            .font: isMe ? GridStyle.meFont : GridStyle.nameFont,
            .foregroundColor: isMe ? GridStyle.accent : UIColor.label,
            .paragraphStyle: style,
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pixel = 1 / max(traitCollection.displayScale, 1)
        let size = 24.0, padding = 8.0
        avatar.frame = CGRect(x: padding, y: (bounds.height - size) / 2, width: size, height: size)
        let x = padding + size + 6
        let width = max(bounds.width - x - padding, 0)
        let height = min(name.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height, 28)
        name.frame = CGRect(x: x, y: ((bounds.height - height) / 2 / pixel).rounded() * pixel, width: width, height: height)
        bottomLine.frame = CGRect(x: 0, y: bounds.height - pixel, width: bounds.width, height: pixel)
        rightLine.frame = CGRect(x: bounds.width - pixel, y: 0, width: pixel, height: bounds.height)
    }
}

/// The header of a team: colour, name, number of people and a chevron; a tap folds or unfolds its rows.
final class GridTeamHeaderView: UIControl {
    private let colorBar = UIView.gridFill()
    private let name = UILabel()
    private let count = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
    private(set) var key = ""
    private var collapsed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = GridStyle.teamHeader
        colorBar.layer.cornerRadius = 2
        name.font = GridStyle.teamFont
        name.textColor = .label
        name.lineBreakMode = .byTruncatingTail
        count.font = GridStyle.countFont
        count.textColor = .secondaryLabel
        chevron.tintColor = .secondaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        chevron.contentMode = .center
        for view in [colorBar, name, count, chevron] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = [.header, .button]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ header: GridPlan.Header) {
        key = header.key
        colorBar.backgroundColor = RGBColor(hex: header.team?.color).map { GridStyle.color($0) } ?? GridStyle.noTeamColor
        name.text = header.team?.name ?? String(localized: .gridNoTeam)
        count.text = String(localized: .nPeople(header.count))
        collapsed = header.collapsed
        chevron.transform = collapsed ? CGAffineTransform(rotationAngle: -.pi / 2) : .identity
        accessibilityLabel = "\(name.text ?? ""), \(count.text ?? "")"
        accessibilityValue = String(localized: collapsed ? .gridCollapsed : .gridExpanded)
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? GridStyle.teamHeaderPressed : GridStyle.teamHeader }
    }

    /// A plain UIControl sends no primary action by itself (only UIButton and the like do): a touch lifted
    /// inside the header is one.
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        if let touch, bounds.contains(touch.location(in: self)) { sendActions(for: .primaryActionTriggered) }
    }

    /// The double tap of VoiceOver folds or unfolds as well.
    override func accessibilityActivate() -> Bool {
        sendActions(for: .primaryActionTriggered)
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padding = 12.0, gap = 8.0, chevronWidth = 20.0
        let middle = bounds.height / 2
        colorBar.frame = CGRect(x: padding, y: middle - 9, width: 4, height: 18)
        chevron.frame = CGRect(x: bounds.width - padding - chevronWidth, y: middle - 10, width: chevronWidth, height: 20)
        let x = padding + 4 + gap
        let limit = chevron.frame.minX - gap
        let countWidth = count.sizeThatFits(.zero).width
        let nameWidth = min(name.sizeThatFits(.zero).width, max(limit - x - gap - countWidth, 0))
        name.frame = CGRect(x: x, y: 0, width: nameWidth, height: bounds.height)
        count.frame = CGRect(x: name.frame.maxX + gap, y: 0, width: max(min(countWidth, limit - name.frame.maxX - gap), 0),
                             height: bounds.height)
    }
}

/// Week numbers and days above the grid: one fill per marked day and two labels per column.
final class GridDaysHeader: UIView {
    private var columns: [GridColumn] = []
    private var fills: [(index: Int, view: UIView)] = []
    private var weeks: [UILabel?] = []
    private var days: [UILabel] = []
    private var locale = Locale.current
    private var labelWidth: Double?
    private let divider = UIView.gridFill(GridStyle.line)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = GridStyle.surface
        isUserInteractionEnabled = false
        addSubview(divider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ columns: [GridColumn], locale: Locale) {
        self.columns = columns
        self.locale = locale
        labelWidth = nil
        for fill in fills { fill.view.removeFromSuperview() }
        for label in weeks { label?.removeFromSuperview() }
        for label in days { label.removeFromSuperview() }
        fills = columns.enumerated().compactMap { index, column in
            GridStyle.headerFill(column).map { (index, UIView.gridFill($0)) }
        }
        for fill in fills { insertSubview(fill.view, belowSubview: divider) }
        weeks = columns.map { column in
            guard column.showsWeekNumber else { return nil }
            let label = UILabel()
            label.font = GridStyle.weekFont
            label.textColor = .secondaryLabel
            label.text = String(localized: .gridWeek(column.day.isoWeek))
            label.sizeToFit()
            addSubview(label)
            return label
        }
        days = columns.map { column in
            let label = UILabel()
            label.font = column.isToday ? GridStyle.todayFont : GridStyle.dayFont
            label.textColor = column.isToday ? GridStyle.accent : .label
            addSubview(label)
            return label
        }
    }

    /// Places the columns for a day width; texts change only when the weekday letter appears or goes.
    func layout(nameWidth: Double, cellWidth: Double, pixel: Double) {
        let wide = cellWidth >= GridMetrics.weekdayLabelMinWidth
        if labelWidth.map({ ($0 >= GridMetrics.weekdayLabelMinWidth) != wide }) ?? true {
            for (column, label) in zip(columns, days) {
                label.text = PlanningFormat.gridDayLabel(column.day, cellWidth: cellWidth, locale: locale)
                label.sizeToFit()
            }
        }
        labelWidth = cellWidth
        func snap(_ value: Double) -> Double { (value / pixel).rounded() * pixel }
        for fill in fills {
            let left = snap(nameWidth + Double(fill.index) * cellWidth)
            fill.view.frame = CGRect(x: left, y: 0, width: snap(nameWidth + Double(fill.index + 1) * cellWidth) - left, height: bounds.height)
        }
        let lines = (weeks.first { $0 != nil } ?? nil)?.bounds.height ?? 13
        let dayHeight = days.first?.bounds.height ?? 15
        let top = snap((bounds.height - lines - dayHeight) / 2)
        for index in columns.indices {
            let center = nameWidth + (Double(index) + 0.5) * cellWidth
            if let week = weeks[index] {
                week.frame.origin = CGPoint(x: snap(center - week.bounds.width / 2), y: top)
            }
            days[index].frame.origin = CGPoint(x: snap(center - days[index].bounds.width / 2), y: top + lines)
        }
        divider.frame = CGRect(x: 0, y: bounds.height - pixel, width: bounds.width, height: pixel)
    }
}

/// The corner above the names: how many people the grid shows.
final class GridCornerView: UIView {
    private let label = UILabel()
    private let divider = UIView.gridFill(GridStyle.line)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = GridStyle.surface
        isUserInteractionEnabled = false
        label.font = GridStyle.countFont
        label.textColor = .secondaryLabel
        addSubview(label)
        addSubview(divider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(people: Int) {
        label.text = String(localized: .nPeople(people))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pixel = 1 / max(traitCollection.displayScale, 1)
        label.frame = CGRect(x: 12, y: 0, width: max(bounds.width - 16, 0), height: bounds.height)
        divider.frame = CGRect(x: 0, y: bounds.height - pixel, width: bounds.width, height: pixel)
    }
}
