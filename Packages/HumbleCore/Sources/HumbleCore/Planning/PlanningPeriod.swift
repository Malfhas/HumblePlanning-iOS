import Foundation

/// Views of the planning; the raw value is what is kept from one launch to the next.
public enum PlanningMode: String, Codable, CaseIterable, Sendable {
    case day = "Day", week = "Week", month = "Month", grid = "Grid"
}

/// The periods each screen asks the server for (`startDate`…`endDate`, both included).
public enum PlanningPeriod {
    /// Days of the Upcoming screen after today.
    public static let upcomingDays = 30

    /// Day and Week: the shown week and its neighbours, so that swiping to the next day or week is instant.
    /// Month: the 6 weeks drawn. Grid: the whole weeks of the month.
    public static func loaded(for mode: PlanningMode, selected: CalendarDay) -> DayRange {
        switch mode {
        case .day, .week:
            let monday = selected.monday
            return monday.adding(days: -7)...monday.adding(days: 13)
        case .month: return month(of: selected)
        case .grid: return grid(of: selected)
        }
    }

    /// What must already be loaded to show the view: the shown week (Day, Week) or the whole period (Month, Grid).
    public static func needed(for mode: PlanningMode, selected: CalendarDay) -> DayRange {
        switch mode {
        case .day, .week: selected.monday...selected.monday.adding(days: 6)
        case .month, .grid: loaded(for: mode, selected: selected)
        }
    }

    /// After a change of day or view: the period to load, nil when the loaded one already holds what is shown.
    public static func toLoad(for mode: PlanningMode, selected: CalendarDay, loaded current: DayRange?) -> DayRange? {
        if let current, current.covers(needed(for: mode, selected: selected)) { return nil }
        return loaded(for: mode, selected: selected)
    }

    /// The 42 cells of the month view, from the Monday of the week of the 1st.
    public static func month(of day: CalendarDay) -> DayRange {
        let start = day.firstOfMonth.monday
        return start...start.adding(days: 41)
    }

    /// The team grid: from the Monday of the week of the 1st to the Sunday of the week of the last day (28 to 42 days).
    public static func grid(of day: CalendarDay) -> DayRange {
        day.firstOfMonth.monday...day.lastOfMonth.monday.adding(days: 6)
    }

    /// Today and the next 30 days.
    public static func upcoming(today: CalendarDay) -> DayRange { today...today.adding(days: upcomingDays) }

    /// The copy kept on the phone for offline use (always read in full, only the user's own tasks kept).
    public static func offlineCopy(today: CalendarDay) -> DayRange { today.adding(days: -30)...today.adding(days: 90) }

    /// Tasks the reminders are planned from.
    public static func reminders(today: CalendarDay) -> DayRange { today...today.adding(days: 14) }
}

/// The endless pagers of the Day, Week and Month views: a fixed anchor day (today, this Monday, the 1st of this
/// month) on the centre page.
public enum PlanningPager {
    public enum Unit: Sendable { case day, week, month }

    public static let pageCount = 20_000
    public static let centerPage = pageCount / 2

    public static func page(of day: CalendarDay, anchor: CalendarDay, unit: Unit) -> Int {
        switch unit {
        case .day: centerPage + anchor.days(to: day)
        case .week: centerPage + anchor.monday.days(to: day.monday) / 7
        case .month: centerPage + anchor.firstOfMonth.months(to: day.firstOfMonth)
        }
    }

    /// The day of a page: the day itself, the Monday of the week, or the 1st of the month.
    public static func day(at page: Int, anchor: CalendarDay, unit: Unit) -> CalendarDay {
        switch unit {
        case .day: anchor.adding(days: page - centerPage)
        case .week: anchor.monday.adding(days: (page - centerPage) * 7)
        case .month: anchor.firstOfMonth.adding(months: page - centerPage)
        }
    }

    /// More than 2 pages away the pager jumps instead of scrolling through every page.
    public static func jumps(from current: Int, to target: Int) -> Bool { abs(current - target) > 2 }
}
