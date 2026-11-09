import Testing
@testable import HumbleCore

/// Spec 01 §5.3: the period each screen asks for.
@Suite struct PlanningPeriodTests {
    @Test func dayAndWeekLoadThreeWeeks() {
        let expected = day("2026-10-26")...day("2026-11-15")
        #expect(PlanningPeriod.loaded(for: .day, selected: day("2026-11-05")) == expected)
        #expect(PlanningPeriod.loaded(for: .week, selected: day("2026-11-08")) == expected)
        #expect(PlanningPeriod.needed(for: .day, selected: day("2026-11-05")) == day("2026-11-02")...day("2026-11-08"))
    }

    @Test func monthLoadsTheSixWeeksDrawn() {
        let range = PlanningPeriod.loaded(for: .month, selected: day("2026-11-20"))
        #expect(range == day("2026-10-26")...day("2026-12-06"))
        #expect(range.count == 42)
        #expect(PlanningPeriod.needed(for: .month, selected: day("2026-11-20")) == range)
    }

    @Test func gridLoadsTheWholeWeeksOfTheMonth() {
        #expect(PlanningPeriod.loaded(for: .grid, selected: day("2026-11-20")) == day("2026-10-26")...day("2026-12-06"))
        // February 2021 starts on a Monday and ends on a Sunday: 4 weeks only
        let february = PlanningPeriod.grid(of: day("2021-02-10"))
        #expect(february == day("2021-02-01")...day("2021-02-28"))
        #expect(february.count == 28)
        #expect(PlanningPeriod.grid(of: day("2026-03-15")).count == 42)
    }

    @Test func upcomingOfflineAndReminders() {
        let today = day("2026-11-05")
        #expect(PlanningPeriod.upcoming(today: today) == today...day("2026-12-05"))
        #expect(PlanningPeriod.upcoming(today: today).count == 31)
        #expect(PlanningPeriod.offlineCopy(today: today) == day("2026-10-06")...day("2027-02-03"))
        #expect(PlanningPeriod.reminders(today: today) == today...day("2026-11-19"))
    }

    @Test func nothingIsLoadedWhenTheShownPeriodIsThere() {
        let loaded = PlanningPeriod.loaded(for: .day, selected: day("2026-11-05"))
        // Swiping to the next or the previous week is instant
        #expect(PlanningPeriod.toLoad(for: .day, selected: day("2026-11-12"), loaded: loaded) == nil)
        #expect(PlanningPeriod.toLoad(for: .week, selected: day("2026-10-26"), loaded: loaded) == nil)
        #expect(PlanningPeriod.toLoad(for: .day, selected: day("2026-11-16"), loaded: loaded)
                == day("2026-11-09")...day("2026-11-29"))
        // The month needs its six weeks
        #expect(PlanningPeriod.toLoad(for: .month, selected: day("2026-11-05"), loaded: loaded)
                == day("2026-10-26")...day("2026-12-06"))
        let month = PlanningPeriod.loaded(for: .month, selected: day("2026-11-05"))
        #expect(PlanningPeriod.toLoad(for: .grid, selected: day("2026-11-30"), loaded: month) == nil)
        #expect(PlanningPeriod.toLoad(for: .week, selected: day("2026-11-30"), loaded: month) == nil)
        #expect(PlanningPeriod.toLoad(for: .day, selected: day("2026-11-05"), loaded: nil) != nil)
    }

    @Test func pagersMapPagesAndDays() {
        let anchor = day("2026-11-09")
        #expect(PlanningPager.page(of: anchor, anchor: anchor, unit: .day) == PlanningPager.centerPage)
        #expect(PlanningPager.day(at: PlanningPager.centerPage - 1, anchor: anchor, unit: .day) == day("2026-11-08"))
        #expect(PlanningPager.page(of: day("2026-11-22"), anchor: anchor, unit: .week) == PlanningPager.centerPage + 1)
        #expect(PlanningPager.page(of: day("2026-11-08"), anchor: anchor, unit: .week) == PlanningPager.centerPage - 1)
        #expect(PlanningPager.day(at: PlanningPager.centerPage + 1, anchor: anchor, unit: .week) == day("2026-11-16"))
        #expect(PlanningPager.page(of: day("2027-01-31"), anchor: anchor, unit: .month) == PlanningPager.centerPage + 2)
        #expect(PlanningPager.day(at: PlanningPager.centerPage - 11, anchor: anchor, unit: .month) == day("2025-12-01"))
        #expect(PlanningPager.jumps(from: 10_000, to: 10_003))
        #expect(!PlanningPager.jumps(from: 10_000, to: 9_998))
    }

    @Test func modesKeepTheirAndroidNames() {
        #expect(PlanningMode.allCases.map(\.rawValue) == ["Day", "Week", "Month", "Grid"])
    }
}
