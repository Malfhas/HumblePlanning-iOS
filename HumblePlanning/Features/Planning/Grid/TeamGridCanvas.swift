import UIKit
import HumbleCore

/// What the grid asks of the planning.
struct GridActions {
    var openTask: (String) -> Void = { _ in }
    var create: (CalendarDay, String) -> Void = { _, _ in }
    var toggleTeam: (String) -> Void = { _ in }
    /// The width of the days once a pinch ends: saved.
    var commitWidth: (Double) -> Void = { _ in }
    var refresh: @MainActor () async -> Void = {}
    var avatar: @MainActor (User) async -> UIImage? = { _ in nil }
}

/// The team grid in UIKit: a single scroll view in both directions, so that the days header, the names, the
/// team headers and the bars share one native scroll (bounce, deceleration, pull to refresh).
///
/// Inside the scroll view, in content coordinates: the day columns and lines (plain views), the bars (layers,
/// only those near the screen), the names column pinned to the left, the team headers pinned to the left and
/// sticking under the days header, the days header pinned to the top and the corner pinned to both. Scrolling
/// only moves what is pinned and the content of the bars whose start is out of sight.
final class TeamGridCanvas: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var actions = GridActions()
    /// What the tab bar covers at the bottom: the last row scrolls above it.
    var bottomInset = 0.0 {
        didSet { if bottomInset != oldValue { setNeedsLayout() } }
    }

    private let scrollView = GridScrollView()
    private let backgroundView = UIView.gridFill()
    private let barsView = UIView.gridFill()
    private let namesView = UIView.gridFill()
    private let teamsView = GridPassthroughView()
    private let header = GridDaysHeader()
    private let corner = GridCornerView()
    private let refreshControl = UIRefreshControl()
    private let renderer = GridBarRenderer()
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))

    private var content: GridContent?
    private var plan = GridPlan()
    private var cellWidth = GridMetrics.defaultCellWidth
    /// The last width the planning asked for: a change is a choice of the menu.
    private var requestedWidth: Double?
    private var focus: GridFocus?
    /// Scroll to the selected day at the next layout, animated or not.
    private var pendingFocus: Bool?
    private var nameWidth = GridMetrics.nameColumnWidth(contentWidth: 0)
    private var needsGeometry = true
    private var applyingWidth = false
    private var pinching = false
    private var pinchZoomed = false
    private var widthLink: CADisplayLink?
    private var widthAnimation = (from: 0.0, to: 0.0, start: 0.0)

    private var columnFills: [(index: Int, view: UIView)] = []
    private var columnLines: [UIView] = []
    private var rowLines: [UIView] = []
    private var nameCells: [GridNameCell] = []
    private var teamViews: [GridTeamHeaderView] = []
    /// The layer of each bar of the plan near the screen, by index.
    private var barNodes: [GridBarNode?] = []
    private var liveBars: [Int] = []
    private var nextLiveBars: [Int] = []
    private var freeBars: [GridBarNode] = []
    private var pass = 0
    /// Bumped when bars move for another reason than scrolling: width, names column, content, screen.
    private var generation = 0
    private var avatars: [String: UIImage] = [:]
    private var loadingAvatars: Set<String> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = GridStyle.surface
        scrollView.backgroundColor = GridStyle.surface
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isDirectionalLockEnabled = true
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.refreshControl = refreshControl
        scrollView.makeAccessibilityElements = { [weak self] in self?.makeAccessibilityElements() ?? [] }
        refreshControl.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .valueChanged)
        for view in [backgroundView, barsView, namesView, teamsView, header, corner] as [UIView] { scrollView.addSubview(view) }
        addSubview(scrollView)
        tap.delegate = self
        pinch.delegate = self
        scrollView.addGestureRecognizer(tap)
        scrollView.addGestureRecognizer(pinch)
        // The grid keeps its size with large text: at the accessibility sizes, touch and hold shows what is under
        // the finger in large, like the tab bar (lifting on a bar opens it)
        let largeContent = UILargeContentViewerInteraction(delegate: self)
        scrollView.addInteraction(largeContent)
        tap.require(toFail: largeContent.gestureRecognizerForExclusionRelationship)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) { (canvas: TeamGridCanvas, _) in
            canvas.traitsChanged()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Input

    func update(content new: GridContent, cellWidth width: Double, focus newFocus: GridFocus) {
        if new != content {
            var unfolded = content
            unfolded?.collapsed = new.collapsed
            let folding = unfolded == new && window != nil
            content = new
            if folding {
                UIView.transition(with: scrollView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    self.rebuild()
                    self.layoutIfNeeded()
                }
            } else {
                rebuild()
            }
        }
        if width != requestedWidth {
            let first = requestedWidth == nil
            requestedWidth = width
            if !pinching && width != cellWidth {
                if first || window == nil || UIAccessibility.isReduceMotionEnabled {
                    cellWidth = width
                    needsGeometry = true
                    setNeedsLayout()
                } else {
                    animateWidth(to: width)
                }
            }
        }
        if newFocus != focus {
            pendingFocus = window != nil && focus?.period == newFocus.period
            focus = newFocus
            setNeedsLayout()
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if scrollView.frame != bounds {
            scrollView.frame = bounds
            needsGeometry = true
        }
        let names = GridMetrics.nameColumnWidth(contentWidth: bounds.width)
        if names != nameWidth {
            nameWidth = names
            needsGeometry = true
        }
        syncScale()
        let bottom = max(bottomInset, safeAreaInsets.bottom)
        if scrollView.contentInset.bottom != bottom + 12 {
            scrollView.contentInset.bottom = bottom + 12
            needsGeometry = true
        }
        if needsGeometry {
            needsGeometry = false
            applyGeometry()
        }
        if let animated = pendingFocus, bounds.width > 0, content != nil {
            pendingFocus = nil
            scrollToFocus(animated: animated)
        }
        updateViewport()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    /// New content: the views of the rows, teams, columns and days are made again; nothing depends on the width yet.
    private func rebuild() {
        guard let content else { return }
        plan = GridPlan(content)
        header.configure(content.columns, locale: content.locale)
        corner.configure(people: content.peopleCount)

        for fill in columnFills { fill.view.removeFromSuperview() }
        columnFills = content.columns.enumerated().compactMap { index, column in
            GridStyle.columnFill(column).map { (index, UIView.gridFill($0)) }
        }
        for fill in columnFills { backgroundView.addSubview(fill.view) }
        resize(&columnLines, to: content.columns.count)
        for (line, column) in zip(columnLines, content.columns) {
            line.backgroundColor = column.isMonday ? GridStyle.line : GridStyle.dayLine
        }
        resize(&rowLines, to: plan.rows.count)
        for line in rowLines { line.backgroundColor = GridStyle.line }

        var cells = Dictionary(nameCells.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
        nameCells = plan.rows.map { row in
            let cell = cells.removeValue(forKey: row.user.id) ?? GridNameCell()
            if cell.superview == nil { namesView.addSubview(cell) }
            let key = GridAvatarView.imageKey(row.user)
            cell.configure(row.user, isMe: row.isMe, image: key.flatMap { avatars[$0] })
            loadAvatar(row.user)
            return cell
        }
        for cell in cells.values { cell.removeFromSuperview() }

        while teamViews.count > plan.headers.count { teamViews.removeLast().removeFromSuperview() }
        while teamViews.count < plan.headers.count {
            let view = GridTeamHeaderView()
            view.addAction(UIAction { [weak self, weak view] _ in
                guard let key = view?.key else { return }
                self?.actions.toggleTeam(key)
            }, for: .primaryActionTriggered)
            teamsView.addSubview(view)
            teamViews.append(view)
        }
        for (view, header) in zip(teamViews, plan.headers) { view.configure(header) }

        for index in liveBars { barNodes[index].map(recycle) }
        liveBars.removeAll(keepingCapacity: true)
        barNodes = Array(repeating: nil, count: plan.bars.count)
        needsGeometry = true
        setNeedsLayout()
        scrollView.invalidateAccessibility()
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .layoutChanged, argument: nil) }
    }

    private func resize(_ lines: inout [UIView], to count: Int) {
        while lines.count > count { lines.removeLast().removeFromSuperview() }
        while lines.count < count {
            let line = UIView.gridFill()
            backgroundView.addSubview(line)
            lines.append(line)
        }
    }

    /// Everything that depends on the width of the days and of the names column.
    private func applyGeometry() {
        guard let content else { return }
        generation += 1
        let pixel = self.pixel
        let header = GridMetrics.dayHeaderHeight
        let daysWidth = Double(content.columns.count) * cellWidth
        let width = nameWidth + daysWidth
        let rowsHeight = max(plan.height - header, 0)
        scrollView.contentSize = CGSize(width: width, height: plan.height)
        backgroundView.frame = CGRect(x: 0, y: 0, width: width, height: plan.height)
        barsView.frame = backgroundView.frame
        for fill in columnFills {
            let left = ((nameWidth + Double(fill.index) * cellWidth) / pixel).rounded() * pixel
            let right = ((nameWidth + Double(fill.index + 1) * cellWidth) / pixel).rounded() * pixel
            fill.view.frame = CGRect(x: left, y: header, width: right - left, height: rowsHeight)
        }
        for (index, line) in columnLines.enumerated() {
            let strong = content.columns[index].isMonday
            let x = ((nameWidth + Double(index) * cellWidth) / pixel).rounded() * pixel
            line.frame = CGRect(x: strong ? x - pixel : x, y: header, width: strong ? 2 * pixel : pixel, height: rowsHeight)
        }
        for (line, row) in zip(rowLines, plan.rows) {
            line.frame = CGRect(x: nameWidth, y: row.y + row.height - pixel, width: daysWidth, height: pixel)
        }
        self.header.frame = CGRect(x: 0, y: self.header.frame.minY, width: max(width, bounds.width), height: header)
        self.header.layout(nameWidth: nameWidth, cellWidth: cellWidth, pixel: pixel)
        corner.frame = CGRect(x: corner.frame.minX, y: corner.frame.minY, width: nameWidth, height: header)
        namesView.frame = CGRect(x: namesView.frame.minX, y: 0, width: nameWidth, height: plan.height)
        for (cell, row) in zip(nameCells, plan.rows) {
            cell.frame = CGRect(x: 0, y: row.y, width: nameWidth, height: row.height)
        }
        teamsView.frame = CGRect(x: teamsView.frame.minX, y: 0, width: bounds.width, height: plan.height)
        for view in teamViews {
            view.frame = CGRect(x: 0, y: view.frame.minY, width: bounds.width, height: GridMetrics.teamHeaderHeight)
        }
        let indicators = max(bottomInset, safeAreaInsets.bottom)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: header, left: 0, bottom: indicators, right: 0)
        scrollView.horizontalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: nameWidth, bottom: indicators, right: 0)
        if !scrollView.isTracking && !scrollView.isDecelerating {
            let offset = scrollView.contentOffset
            let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
            let maxY = max(scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height,
                           -scrollView.adjustedContentInset.top)
            let clamped = CGPoint(x: min(max(offset.x, 0), maxX), y: min(offset.y, maxY))
            if clamped != offset {
                applyingWidth = true
                scrollView.contentOffset = clamped
                applyingWidth = false
            }
        }
    }

    /// Pins the names, the team headers, the days header and the corner, then shows the bars near the screen.
    private func updateViewport() {
        guard content != nil else { return }
        let offset = scrollView.contentOffset
        let pinnedX = max(0, offset.x), pinnedY = max(0, offset.y)
        namesView.frame.origin.x = pinnedX
        teamsView.frame.origin.x = pinnedX
        header.frame.origin.y = pinnedY
        corner.frame.origin = CGPoint(x: pinnedX, y: pinnedY)
        let top = pinnedY + GridMetrics.dayHeaderHeight
        for (view, header) in zip(teamViews, plan.headers) {
            view.frame.origin.y = min(max(header.y, top), header.end - GridMetrics.teamHeaderHeight)
        }
        layoutBars(offset: offset)
    }

    /// Bars within half a screen of the visible area get a layer; the others give theirs back. A bar already
    /// placed is placed again only when the scroll hides its start (its content follows the edge).
    private func layoutBars(offset: CGPoint) {
        pass += 1
        let size = scrollView.bounds.size
        let minX = offset.x - size.width / 2, maxX = offset.x + size.width * 1.5
        let minY = offset.y - size.height / 3, maxY = offset.y + size.height * 4 / 3
        let traits = traitCollection
        let half = cellWidth / 2, contentInset = GridMetrics.barInset + GridMetrics.barPadding
        nextLiveBars.removeAll(keepingCapacity: true)
        var index = plan.firstRow(below: minY)
        while index < plan.rowSpans.count, plan.rowSpans[index].y < maxY {
            let row = plan.rowSpans[index]
            let origin = CGPoint(x: nameWidth, y: row.y)
            for barIndex in row.bars {
                let span = plan.barSpans[barIndex]
                let start = cellWidth * Double(span.first)
                guard nameWidth + start + cellWidth * Double(span.days) >= minX, nameWidth + start <= maxX else { continue }
                let node = barNodes[barIndex] ?? node(for: barIndex)
                node.pass = pass
                nextLiveBars.append(barIndex)
                let followsEdge = offset.x > start + (span.afternoon ? half : 0) + contentInset
                if node.generation != generation || followsEdge || node.followsEdge {
                    node.apply(plan.bars[barIndex], origin: origin, cellWidth: cellWidth, scrollX: offset.x,
                               renderer: renderer, traits: traits)
                    node.generation = generation
                    node.followsEdge = followsEdge
                }
            }
            index += 1
        }
        for barIndex in liveBars where barNodes[barIndex]?.pass != pass {
            barNodes[barIndex].map(recycle)
            barNodes[barIndex] = nil
        }
        swap(&liveBars, &nextLiveBars)
    }

    private func node(for index: Int) -> GridBarNode {
        let node: GridBarNode
        if let free = freeBars.popLast() {
            node = free
        } else {
            node = GridBarNode()
            barsView.layer.addSublayer(node.fill)
        }
        node.reset()
        barNodes[index] = node
        return node
    }

    private func recycle(_ node: GridBarNode) {
        node.fill.isHidden = true
        freeBars.append(node)
    }

    private var pixel: Double { 1 / max(traitCollection.displayScale, 1) }

    private func traitsChanged() {
        for index in liveBars { barNodes[index]?.refreshColor(traits: traitCollection) }
        needsGeometry = true
        setNeedsLayout()
    }

    /// Bars are drawn for the pixels of the screen the grid is on.
    private func syncScale() {
        let scale = max(traitCollection.displayScale, 1)
        guard scale != renderer.scale else { return }
        renderer.scale = scale
        for index in liveBars { barNodes[index]?.reset() }
        needsGeometry = true
    }

    // MARK: Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !applyingWidth else { return }
        updateViewport()
    }

    /// The day before the selected one comes first; the vertical position stays.
    private func scrollToFocus(animated: Bool) {
        guard let focus else { return }
        let target = GridMetrics.focusOffset(selected: focus.selected, period: focus.period, cellWidth: cellWidth)
        let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        let point = CGPoint(x: min(max(target, 0), maxX), y: scrollView.contentOffset.y)
        guard point != scrollView.contentOffset else { return }
        scrollView.setContentOffset(point, animated: animated)
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            await actions.refresh()
            refreshControl.endRefreshing()
        }
    }

    // MARK: Width of the days

    /// Applies a width and the horizontal offset that goes with it, in the same frame.
    private func setWidth(_ width: Double, offsetX: Double) {
        cellWidth = width
        applyGeometry()
        let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        applyingWidth = true
        scrollView.contentOffset.x = min(max(offsetX, 0), maxX)
        applyingWidth = false
        updateViewport()
    }

    /// A width of the menu: the days widen or narrow in a quarter of a second; the offset in points stays.
    private func animateWidth(to width: Double) {
        widthAnimation = (cellWidth, width, CACurrentMediaTime())
        guard widthLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(widthStep))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        widthLink = link
    }

    @objc private func widthStep(_ link: CADisplayLink) {
        let progress = min((link.targetTimestamp - widthAnimation.start) / 0.25, 1)
        let eased = 1 - pow(1 - progress, 3)
        setWidth(widthAnimation.from + (widthAnimation.to - widthAnimation.from) * eased, offsetX: scrollView.contentOffset.x)
        if progress >= 1 { stopWidthAnimation() }
    }

    private func stopWidthAnimation() {
        widthLink?.invalidate()
        widthLink = nil
    }

    /// Two fingers change the width of the days around them; one finger scrolls as usual. Saved when they lift.
    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopWidthAnimation()
            pinching = true
            pinchZoomed = false
            scrollView.isScrollEnabled = false
            recognizer.scale = 1
        case .changed:
            let scale = recognizer.scale
            recognizer.scale = 1
            guard scale != 1, recognizer.numberOfTouches >= 2 else { return }
            let focusX = recognizer.location(in: self).x - nameWidth
            let zoom = GridMetrics.zoom(cellWidth: cellWidth, scale: scale, focusX: focusX, scrollX: scrollView.contentOffset.x)
            guard zoom.cellWidth != cellWidth else { return }
            pinchZoomed = true
            setWidth(zoom.cellWidth, offsetX: zoom.scrollX)
        default:
            pinching = false
            scrollView.isScrollEnabled = true
            if pinchZoomed {
                pinchZoomed = false
                requestedWidth = cellWidth
                actions.commitWidth(cellWidth)
            }
        }
    }

    // MARK: Taps

    /// A bar opens its task; an empty day of a row opens a new task there when the role allows it.
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let content, let (row, point) = rowPoint(recognizer.location(in: scrollView)) else { return }
        let rowPlan = plan.rows[row]
        let x = point.x - nameWidth, y = point.y - rowPlan.y
        let slack = GridMetrics.barGap
        var hit: Int?
        for index in rowPlan.bars {
            let geometry = GridMetrics.geometry(of: plan.bars[index].bar, cellWidth: cellWidth)
            guard x >= geometry.x, x <= geometry.x + geometry.width,
                  y >= geometry.y - slack, y <= geometry.y + GridMetrics.barHeight + slack else { continue }
            if hit == nil || (y >= geometry.y && y <= geometry.y + GridMetrics.barHeight) { hit = index }
        }
        if let hit {
            barNodes[hit]?.flash()
            actions.openTask(plan.bars[hit].bar.task.id)
        } else if rowPlan.canCreate {
            let column = GridMetrics.column(atX: x, cellWidth: cellWidth, days: content.columns.count)
            flashCell(row: rowPlan, column: column)
            actions.create(content.period.lowerBound.adding(days: column), rowPlan.user.id)
        }
    }

    /// The row under a point of the content, outside the pinned header, names and team headers.
    private func rowPoint(_ point: CGPoint) -> (Int, CGPoint)? {
        let offset = scrollView.contentOffset
        guard point.y >= max(0, offset.y) + GridMetrics.dayHeaderHeight, point.x >= max(0, offset.x) + nameWidth,
              !teamViews.contains(where: { $0.frame.contains(CGPoint(x: point.x - teamsView.frame.minX, y: point.y)) }),
              let row = plan.row(at: point.y) else { return nil }
        return (row, point)
    }

    private func flashCell(row: GridPlan.Row, column: Int) {
        let cell = UIView.gridFill(GridStyle.accent.withAlphaComponent(0.22))
        cell.frame = CGRect(x: nameWidth + Double(column) * cellWidth, y: row.y, width: cellWidth, height: row.height)
        barsView.addSubview(cell)
        UIView.animate(withDuration: 0.45, delay: 0.1, options: [.curveEaseOut, .allowUserInteraction]) {
            cell.alpha = 0
        } completion: { _ in
            cell.removeFromSuperview()
        }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard recognizer === tap else { return true }
        return !(touch.view is UIControl) && !scrollView.isDecelerating
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizer === pinch
    }

    // MARK: Avatars

    private func loadAvatar(_ user: User) {
        guard let key = GridAvatarView.imageKey(user), avatars[key] == nil, !loadingAvatars.contains(key) else { return }
        loadingAvatars.insert(key)
        let load = actions.avatar
        Task { [weak self] in
            let image = await load(user)
            guard let self else { return }
            loadingAvatars.remove(key)
            guard let image else { return }
            avatars[key] = image
            for cell in nameCells where cell.avatar.imageKey == key { cell.avatar.show(image) }
        }
    }

    // MARK: Accessibility

    /// The corner, the days, then each team header followed by its people and their bars.
    private func makeAccessibilityElements() -> [Any] {
        guard let content else { return [] }
        var elements: [Any] = []
        let corner = GridAccessibilityElement(accessibilityContainer: scrollView)
        corner.accessibilityLabel = String(localized: .nPeople(content.peopleCount))
        corner.frameInContent = { [weak self] in self?.corner.frame ?? .zero }
        elements.append(corner)
        for (index, column) in content.columns.enumerated() {
            let element = GridAccessibilityElement(accessibilityContainer: scrollView)
            var parts = [PlanningFormat.longLabel(column.day, locale: content.locale)]
            if column.isToday { parts.append(String(localized: .today)) }
            if let holiday = column.holiday { parts.append(holiday.shownLabel ?? String(localized: .holiday)) }
            element.accessibilityLabel = parts.joined(separator: ", ")
            element.frameInContent = { [weak self] in
                guard let self else { return .zero }
                return CGRect(x: nameWidth + Double(index) * cellWidth, y: header.frame.minY,
                              width: cellWidth, height: GridMetrics.dayHeaderHeight)
            }
            elements.append(element)
        }
        var headerIndex = 0
        for (rowIndex, row) in plan.rows.enumerated() {
            while headerIndex < plan.headers.count, plan.headers[headerIndex].y < row.y {
                elements.append(teamViews[headerIndex])
                headerIndex += 1
            }
            let name = GridAccessibilityElement(accessibilityContainer: scrollView)
            name.accessibilityLabel = row.user.displayName
            name.frameInContent = { [weak self] in
                guard let self, rowIndex < plan.rows.count else { return .zero }
                let row = plan.rows[rowIndex]
                return CGRect(x: namesView.frame.minX, y: row.y, width: nameWidth, height: row.height)
            }
            // A tap on an empty day of the row makes a task there: VoiceOver gets it as an action of the person
            if row.canCreate {
                let userId = row.user.id
                name.accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: .newTask)) { [weak self] _ in
                    guard let self, let content = self.content else { return false }
                    let selected = focus?.selected
                    let day = selected.flatMap { content.period.contains($0) ? $0 : nil } ?? content.period.lowerBound
                    actions.create(day, userId)
                    return true
                }]
            }
            elements.append(name)
            for barIndex in row.bars {
                elements.append(barElement(barIndex, row: row, content: content))
            }
        }
        elements.append(contentsOf: teamViews.dropFirst(headerIndex).map { $0 as Any })
        return elements
    }

    /// Title, own title, person, dates, times, status and lock, as on Android.
    private func barElement(_ index: Int, row: GridPlan.Row, content: GridContent) -> GridAccessibilityElement {
        let bar = plan.bars[index]
        let task = bar.bar.task
        var parts = [bar.look.title]
        if let own = task.ownTitle, own != bar.look.title { parts.append(own) }
        parts.append(row.user.displayName)
        if let dates = PlanningFormat.barDates(task, locale: content.locale) { parts.append(dates) }
        if let times = task.timeRange { parts.append(times) }
        if let status = task.statusOf(content.references) { parts.append(status.name) }
        if task.isLocked { parts.append(String(localized: .a11YLocked)) }
        let element = GridAccessibilityElement(accessibilityContainer: scrollView)
        element.accessibilityLabel = parts.joined(separator: ", ")
        element.accessibilityTraits = .button
        let rowY = row.y
        element.frameInContent = { [weak self] in
            guard let self, index < plan.bars.count else { return .zero }
            let shape = GridMetrics.geometry(of: plan.bars[index].bar, cellWidth: cellWidth).frame
            return CGRect(x: nameWidth + shape.x, y: rowY + shape.y, width: shape.width, height: shape.height)
        }
        element.activate = { [weak self] in self?.actions.openTask(task.id) }
        return element
    }
}

/// The scroll view of the grid: drags may start on a team header, and its accessibility elements are made
/// only when asked for.
final class GridScrollView: UIScrollView {
    var makeAccessibilityElements: (() -> [Any])?
    private var elements: [Any]?

    func invalidateAccessibility() { elements = nil }

    override var accessibilityElements: [Any]? {
        get {
            if elements == nil { elements = makeAccessibilityElements?() }
            return elements
        }
        set { elements = newValue }
    }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// A container that is not a target of touches itself, only its subviews are.
final class GridPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

/// An accessibility element whose frame follows the scrolling and the width of the days.
final class GridAccessibilityElement: UIAccessibilityElement {
    /// In the coordinates of the content of the scroll view, its container.
    var frameInContent: () -> CGRect = { .zero }
    var activate: (() -> Void)?

    override var accessibilityFrame: CGRect {
        get {
            guard let container = accessibilityContainer as? UIView,
                  let screen = container.window?.windowScene?.screen.coordinateSpace else { return .zero }
            return container.convert(frameInContent(), to: screen)
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        guard let activate else { return false }
        activate()
        return true
    }
}

extension GridAccessibilityElement: UILargeContentViewerItem {
    var showsLargeContentViewer: Bool { true }
    var largeContentTitle: String? { accessibilityLabel }
    var largeContentImage: UIImage? { nil }
    var scalesLargeContentImage: Bool { false }
    var largeContentImageInsets: UIEdgeInsets { .zero }
}

extension TeamGridCanvas: UILargeContentViewerInteractionDelegate {
    /// What is drawn on top wins: the pinned headers, names and corner, then the bars under them.
    func largeContentViewerInteraction(_ interaction: UILargeContentViewerInteraction,
                                       itemAt point: CGPoint) -> (any UILargeContentViewerItem)? {
        guard let screen = window?.windowScene?.screen.coordinateSpace else { return nil }
        let location = scrollView.convert(point, to: screen)
        let elements = scrollView.accessibilityElements ?? []
        for view in teamViews where view.accessibilityFrame.contains(location) {
            view.showsLargeContentViewer = true
            view.largeContentTitle = view.accessibilityLabel
            return view
        }
        let items = elements.compactMap { $0 as? GridAccessibilityElement }.filter { $0.accessibilityFrame.contains(location) }
        return items.first { $0.activate == nil } ?? items.first
    }

    func largeContentViewerInteraction(_ interaction: UILargeContentViewerInteraction,
                                       didEndOn item: (any UILargeContentViewerItem)?, at point: CGPoint) {
        if let header = item as? GridTeamHeaderView {
            header.sendActions(for: .primaryActionTriggered)
        } else {
            _ = (item as? GridAccessibilityElement)?.accessibilityActivate()
        }
    }
}
