import Foundation
import HumbleCore

/// What the team grid shows, worked out from the planning. Compared as a whole: the grid lays itself out
/// again only when something it shows changed.
struct GridContent: Equatable {
    var period: DayRange
    var columns: [GridColumn]
    var groups: [GridGroup]
    var collapsed: Set<String>
    /// People on whose row a tap on an empty day creates a task.
    var creatable: Set<String>
    var me: String
    var references: References
    var titleMode: CardTitleMode
    var locale: Locale

    var showsTeamHeaders: Bool { GridLayout.showsTeamHeaders(groups) }
    var peopleCount: Int { groups.reduce(0) { $0 + $1.rows.count } }
}

/// Where the grid scrolls back to: a new period, another selected day, or "Today" again.
struct GridFocus: Equatable {
    var selected: CalendarDay
    var period: DayRange
    var request: Int
}

/// How a bar looks, whatever its width: also the key of the drawings of its content.
struct BarLook: Hashable {
    let title: String
    /// The colour of the project or of the status; nil = the accent.
    let color: RGBColor?
    let bold: Bool
    let italic: Bool
    let strikethrough: Bool
    let underline: Bool
    let locked: Bool

    init(_ task: PlanningTask, references: References, mode: CardTitleMode) {
        let status = task.statusOf(references)
        title = task.cardTitle(references, mode: mode)
        color = GridLayout.barColor(task, references: references)
        bold = status?.bold ?? false
        italic = status?.italic ?? false
        strikethrough = status?.strikethrough ?? false
        underline = status?.underline ?? false
        locked = task.isLocked
    }

    /// Dark text on light colours; the accent takes white text in both modes.
    var textIsDark: Bool { color?.contentColorIsDark ?? false }
}

/// The grid from top to bottom, in points from the top of the content (the days header first). Independent of
/// the width of the days: pinching only moves things sideways.
struct GridPlan {
    struct Header {
        let key: String
        let team: Team?
        let count: Int
        let collapsed: Bool
        let y: Double
        /// Bottom of its last row: the header stops sticking there.
        var end: Double
    }

    struct Row {
        let user: User
        let y: Double
        let height: Double
        let isMe: Bool
        let canCreate: Bool
        /// Its bars in `bars`.
        let bars: Range<Int>
    }

    struct Bar {
        let bar: GridBar
        let look: BarLook
    }

    /// Where a row is, without its person: what scrolling reads.
    struct RowSpan {
        let y: Double
        let height: Double
        let bars: Range<Int>
    }

    /// Which days a bar covers, without its task: what scrolling reads.
    struct BarSpan {
        let first: Int
        let days: Int
        let afternoon: Bool
    }

    private(set) var headers: [Header] = []
    private(set) var rows: [Row] = []
    private(set) var bars: [Bar] = []
    private(set) var rowSpans: [RowSpan] = []
    private(set) var barSpans: [BarSpan] = []
    private(set) var height = GridMetrics.dayHeaderHeight

    init() {}

    init(_ content: GridContent) {
        let showsHeaders = content.showsTeamHeaders
        var y = GridMetrics.dayHeaderHeight
        for group in content.groups {
            let collapsed = content.collapsed.contains(group.id)
            if showsHeaders {
                headers.append(Header(key: group.id, team: group.team, count: group.rows.count, collapsed: collapsed, y: y, end: 0))
                y += GridMetrics.teamHeaderHeight
            }
            if !collapsed {
                for row in group.rows {
                    let first = bars.count
                    for bar in row.bars {
                        bars.append(Bar(bar: bar, look: BarLook(bar.task, references: content.references, mode: content.titleMode)))
                        barSpans.append(BarSpan(first: bar.first, days: bar.last - bar.first + 1, afternoon: bar.part == .afternoon))
                    }
                    let height = GridMetrics.rowHeight(lanes: row.lanes)
                    rows.append(Row(user: row.user, y: y, height: height, isMe: row.user.id == content.me,
                                    canCreate: content.creatable.contains(row.user.id), bars: first..<bars.count))
                    rowSpans.append(RowSpan(y: y, height: height, bars: first..<bars.count))
                    y += height
                }
            }
            if showsHeaders { headers[headers.count - 1].end = y }
        }
        height = y
    }

    /// Index of the first row whose bottom is below `y`.
    func firstRow(below y: Double) -> Int {
        var low = 0, high = rowSpans.count
        while low < high {
            let middle = (low + high) / 2
            if rowSpans[middle].y + rowSpans[middle].height <= y { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The row under `y`, if any.
    func row(at y: Double) -> Int? {
        let index = firstRow(below: y)
        guard index < rowSpans.count, rowSpans[index].y <= y else { return nil }
        return index
    }
}
