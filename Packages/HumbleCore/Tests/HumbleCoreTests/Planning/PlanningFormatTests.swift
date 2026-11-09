import Foundation
import Testing
@testable import HumbleCore

/// `FormatTest` (tests 54–56) and the labels of `Format.kt` in the four languages of the app.
@Suite struct PlanningFormatTests {
    private let today = "2026-11-05"

    @Test func multiDayFirstThenAllDayThenByStartTime() {
        let sorted = [
            task("late", today, from: "14:00:00", to: "16:00:00"),
            task("allday", today),
            task("early", today, from: "08:00:00", to: "12:00:00"),
            task("multi", "2026-11-04", "2026-11-07", from: "16:00:00"),
        ].sortedForDay()
        #expect(sorted.map(\.id) == ["multi", "allday", "early", "late"])
    }

    @Test func anUnpaddedTimeSortsLikeThePaddedOne() {
        let sorted = [task("ten", today, from: "10:00"), task("nine", today, from: "9:00")].sortedForDay()
        #expect(sorted.map(\.id) == ["nine", "ten"])
    }

    @Test func sameTimeSortsByTitle() {
        let sorted = [task("b", today, from: "08:00:00", title: "beta"), task("a", today, from: "08:00:00", title: "Alpha")]
            .sortedForDay()
        #expect(sorted.map(\.id) == ["a", "b"])
    }

    @Test func timeRangeKeepsTheTimesAndHasNoneForAWholeDay() {
        #expect(task("a", today, from: "08:00:00", to: "12:00:00").timeRange == "08:00 – 12:00")
        #expect(task("a", today, from: "08:00:00").timeRange == "08:00")
        #expect(task("a", today).timeRange == nil)
        #expect(task("a", today, from: "").timeRange == nil)
    }

    @Test func hasNotesOnlyWithSomeText() {
        var note = task("a", today)
        #expect(!note.hasNotes)
        note.notes = " \n\t "
        #expect(!note.hasNotes)
        note.notes = "  Call before  "
        #expect(note.hasNotes)
    }

    @Test func occursOnEveryDayOfItsSpan() {
        let span = task("a", "2026-11-04", "2026-11-06")
        #expect(!span.occursOn(day("2026-11-03")))
        #expect(span.occursOn(day("2026-11-04")))
        #expect(span.occursOn(day("2026-11-06")))
        #expect(!span.occursOn(day("2026-11-07")))
        #expect(task("b", today).occursOn(day(today)))
    }

    @Test func timesAreCutAndPadded() {
        #expect(PlanningFormat.hhmm("08:35:00") == "08:35")
        #expect(PlanningFormat.paddedTime("9:00") == "09:00")
        #expect(PlanningFormat.paddedTime("8:05:00") == "8:05:")
        #expect(PlanningFormat.paddedTime("") == "00000")
    }

    @Test func longLabelHasAFixedPattern() {
        let monday = day("2026-11-09")
        #expect(PlanningFormat.longLabel(monday, locale: en) == "Monday 9 November")
        #expect(PlanningFormat.longLabel(monday, locale: fr) == "Lundi 9 novembre")
        #expect(PlanningFormat.longLabel(monday, locale: es) == "Lunes 9 noviembre")
        #expect(PlanningFormat.longLabel(monday, locale: de) == "Montag 9 November")
        #expect(PlanningFormat.longLabel(monday, locale: fr, capitalized: false) == "lundi 9 novembre")
    }

    @Test func mediumLabelFollowsTheRegion() {
        let monday = day("2026-11-09")
        #expect(PlanningFormat.mediumLabel(monday, locale: en) == "Nov 9, 2026")
        #expect(PlanningFormat.mediumLabel(monday, locale: fr) == "9 nov. 2026")
        #expect(PlanningFormat.mediumLabel(monday, locale: es) == "9 nov 2026")
        #expect(PlanningFormat.mediumLabel(monday, locale: de) == "09.11.2026")
    }

    @Test func monthAndWeekdayNames() {
        let monday = day("2026-11-09")
        #expect(PlanningFormat.monthLabel(monday, locale: en) == "November 2026")
        #expect(PlanningFormat.monthLabel(monday, locale: fr) == "Novembre 2026")
        #expect(PlanningFormat.monthLabel(monday, locale: es) == "Noviembre 2026")
        #expect(PlanningFormat.monthLabel(monday, locale: de) == "November 2026")
        #expect(PlanningFormat.weekdayName(monday, locale: fr) == "Lundi")
        #expect(PlanningFormat.shortWeekday(1, locale: en) == "Mon")
        #expect(PlanningFormat.shortWeekday(1, locale: fr) == "Lun")
        #expect(PlanningFormat.shortWeekday(1, locale: es) == "Lun")
        #expect(PlanningFormat.shortWeekday(1, locale: de) == "Mo")
        #expect(PlanningFormat.shortWeekday(7, locale: fr) == "Dim")
        #expect((1...7).map { PlanningFormat.narrowWeekday($0, locale: en) } == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(PlanningFormat.narrowWeekday(1, locale: fr) == "L")
    }

    @Test func gridDayLabelDependsOnTheWidth() {
        #expect(PlanningFormat.gridDayLabel(day("2026-11-09"), cellWidth: 56, locale: en) == "M 9")
        #expect(PlanningFormat.gridDayLabel(day("2026-11-09"), cellWidth: 40, locale: fr) == "L 9")
        #expect(PlanningFormat.gridDayLabel(day("2026-11-09"), cellWidth: 32, locale: en) == "9")
    }

    @Test func barDatesReadOutTheSpan() {
        #expect(PlanningFormat.barDates(task("a", "2026-11-09", "2026-11-11"), locale: en) == "Nov 9, 2026 – Nov 11, 2026")
        #expect(PlanningFormat.barDates(task("a", "2026-11-09"), locale: en) == "Monday 9 November")
        #expect(PlanningFormat.barDates(task("a", "soon"), locale: en) == nil)
    }

    @Test func fileSizesInBinaryUnits() {
        #expect(PlanningFormat.fileSize(0, locale: en) == "0 B")
        #expect(PlanningFormat.fileSize(1023, locale: en) == "1023 B")
        #expect(PlanningFormat.fileSize(2047, locale: en) == "1 KB")
        #expect(PlanningFormat.fileSize(1024 * 1023, locale: en) == "1023 KB")
        #expect(PlanningFormat.fileSize(1_258_291, locale: en) == "1.2 MB")
        #expect(PlanningFormat.fileSize(1_258_291, locale: fr) == "1,2 MB")
        // Half up, like Java's %.1f
        #expect(PlanningFormat.fileSize(1_310_720, locale: en) == "1.3 MB")
        #expect(PlanningFormat.fileSize(5_000 * 1024 * 1024, locale: en) == "5000.0 MB")
    }

    @Test func offlineBannerDate() {
        let date = ISO8601DateFormatter().date(from: "2026-11-09T13:05:00Z")!
        #expect(PlanningFormat.shortDateTime(date, locale: fr, timeZone: paris) == "09/11/2026 14:05")
        #expect(PlanningFormat.shortDateTime(date, locale: de, timeZone: paris) == "09.11.26, 14:05")
    }
}
