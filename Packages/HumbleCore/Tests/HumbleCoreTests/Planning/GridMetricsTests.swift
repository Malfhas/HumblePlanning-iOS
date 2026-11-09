import Testing
@testable import HumbleCore

/// Sizes of the grid (spec 02 §2.10.1, §2.10.6, §2.10.7).
@Suite struct GridMetricsTests {
    private func bar(first: Int, last: Int, lane: Int = 0, part: DayPart = .whole) -> GridBar {
        GridBar(task: task("a", "2026-11-02"), first: first, last: last, lane: lane, part: part,
                continuesBefore: false, continuesAfter: false)
    }

    @Test func rowsGrowWithTheirLanes() {
        #expect(GridMetrics.rowHeight(lanes: 0) == 44)
        #expect(GridMetrics.rowHeight(lanes: 1) == 44)
        #expect(GridMetrics.rowHeight(lanes: 2) == 57)
        #expect(GridMetrics.rowHeight(lanes: 3) == 82)
    }

    @Test func barsCoverTheirDaysOrHalfDays() {
        let whole = GridMetrics.geometry(of: bar(first: 1, last: 2), cellWidth: 56)
        #expect(whole == GridBarGeometry(x: 56, y: 5, width: 112))
        #expect(whole.frame == (57, 5, 110, 22))
        #expect(GridMetrics.geometry(of: bar(first: 0, last: 0, part: .morning), cellWidth: 56) == GridBarGeometry(x: 0, y: 5, width: 28))
        #expect(GridMetrics.geometry(of: bar(first: 3, last: 3, lane: 2, part: .afternoon), cellWidth: 56)
                == GridBarGeometry(x: 196, y: 55, width: 28))
    }

    @Test func narrowBarsLoseTheirTitleThenTheirLock() {
        let half = GridMetrics.geometry(of: bar(first: 0, last: 0, part: .morning), cellWidth: 56)
        #expect(!half.showsTitle && !half.showsLock(true))
        let day = GridMetrics.geometry(of: bar(first: 0, last: 0), cellWidth: 32)
        #expect(day.showsTitle && !day.showsLock(true))
        let wide = GridMetrics.geometry(of: bar(first: 0, last: 0), cellWidth: 40)
        #expect(wide.showsLock(true) && !wide.showsLock(false))
    }

    @Test func theTitleFollowsTheVisibleEdge() {
        let long = GridMetrics.geometry(of: bar(first: 1, last: 5), cellWidth: 56)
        #expect(long.contentStart == 61)
        #expect(long.contentShift(scrollX: 0) == 0)
        #expect(!long.startHidden(scrollX: 61) && long.startHidden(scrollX: 62))
        #expect(long.contentShift(scrollX: 161) == 100)
        // It stops 30 points before the end of the bar
        #expect(long.contentShift(scrollX: 1_000) == 280 - 2 - 8 - 30)
        let short = GridMetrics.geometry(of: bar(first: 0, last: 0, part: .morning), cellWidth: 24)
        #expect(short.contentShift(scrollX: 500) == 0)
    }

    @Test func aTapFindsItsDay() {
        #expect(GridMetrics.column(atX: 0, cellWidth: 56, days: 35) == 0)
        #expect(GridMetrics.column(atX: 55.9, cellWidth: 56, days: 35) == 0)
        #expect(GridMetrics.column(atX: 56, cellWidth: 56, days: 35) == 1)
        #expect(GridMetrics.column(atX: 10_000, cellWidth: 56, days: 35) == 34)
        #expect(GridMetrics.column(atX: -3, cellWidth: 56, days: 35) == 0)
    }

    @Test func theDayBeforeTheSelectedOneComesFirst() {
        let period = PlanningPeriod.grid(of: day("2026-11-11"))
        #expect(GridMetrics.focusOffset(selected: day("2026-11-11"), period: period, cellWidth: 56) == 15 * 56)
        #expect(GridMetrics.focusOffset(selected: day("2026-10-26"), period: period, cellWidth: 56) == 0)
        #expect(GridMetrics.focusOffset(selected: day("2026-10-27"), period: period, cellWidth: 56) == 0)
        #expect(GridMetrics.focusOffset(selected: day("2027-03-01"), period: period, cellWidth: 32) == 40 * 32)
    }

    @Test func pinchingKeepsTheContentUnderTheFingers() {
        let zoomed = GridMetrics.zoom(cellWidth: 56, scale: 2, focusX: 100, scrollX: 200)
        #expect(zoomed.cellWidth == 112 && zoomed.scrollX == 500)
        let capped = GridMetrics.zoom(cellWidth: 56, scale: 10, focusX: 0, scrollX: 100)
        #expect(capped.cellWidth == 140 && capped.scrollX == 250)
        #expect(GridMetrics.zoom(cellWidth: 30, scale: 0.1, focusX: 0, scrollX: 0).cellWidth == 24)
    }

    @Test func widthsAndPresets() {
        #expect(GridMetrics.defaultCellWidth == 56 && GridMetrics.minCellWidth == 24 && GridMetrics.maxCellWidth == 140)
        #expect(GridMetrics.presets == [32, 56, 96])
        #expect(GridMetrics.nearestPreset(to: 44) == 32)
        #expect(GridMetrics.nearestPreset(to: 60) == 56)
        #expect(GridMetrics.nearestPreset(to: 80) == 96)
        #expect(GridMetrics.nearestPreset(to: 140) == 96)
        #expect(GridMetrics.clampedCellWidth(10) == 24 && GridMetrics.clampedCellWidth(200) == 140)
        #expect(GridMetrics.nameColumnWidth(contentWidth: 599) == 108 && GridMetrics.nameColumnWidth(contentWidth: 600) == 168)
    }
}
