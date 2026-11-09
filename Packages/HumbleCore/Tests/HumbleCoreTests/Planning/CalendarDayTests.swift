import Foundation
import Testing
@testable import HumbleCore

@Suite struct CalendarDayTests {
    @Test func readsOnlyFullISODates() {
        #expect(CalendarDay("2026-11-05") == CalendarDay(year: 2026, month: 11, day: 5))
        #expect(CalendarDay("2024-02-29") != nil)
        #expect(CalendarDay("2000-02-29") != nil)
        for bad in ["2026-11-5", "2026-02-29", "1900-02-29", "2026-04-31", "2026-13-01", "2026-00-10", "2026-11-00",
                    "2026-11-05T08:00:00", "", "soon", "abcd-ef-gh", "2026/11/05", "+2026-11-05", "２０２６-11-05"] {
            #expect(CalendarDay(bad) == nil, "\(bad)")
        }
    }

    @Test func writesTheISOFormBack() {
        #expect(day("2026-01-09").iso == "2026-01-09")
        #expect(CalendarDay(year: 33, month: 3, day: 3)?.iso == "0033-03-03")
        #expect(day("2026-11-05").description == "2026-11-05")
    }

    @Test func epochDayMatchesUnixDays() {
        #expect(day("1970-01-01").epochDay == 0)
        #expect(day("1969-12-31").epochDay == -1)
        #expect(day("2026-11-09").epochDay == 20_766)
    }

    @Test func addingDaysNeverShiftsADay() {
        // Around both daylight saving changes of 2026 in Europe
        #expect(day("2026-03-28").adding(days: 1) == day("2026-03-29"))
        #expect(day("2026-03-29").adding(days: 1) == day("2026-03-30"))
        #expect(day("2026-10-24").adding(days: 1) == day("2026-10-25"))
        #expect(day("2026-10-25").adding(days: 1) == day("2026-10-26"))
        #expect(day("2026-12-31").adding(days: 1) == day("2027-01-01"))
        #expect(day("2024-02-28").adding(days: 1) == day("2024-02-29"))
        #expect(day("2026-03-01").adding(days: -1) == day("2026-02-28"))
        #expect(day("2026-11-05").adding(days: -30) == day("2026-10-06"))
        #expect(day("2026-11-05").adding(days: 90) == day("2027-02-03"))
        #expect(day("2026-11-02").days(to: day("2026-11-09")) == 7)
        #expect(day("2026-11-09").days(to: day("2026-11-02")) == -7)
    }

    @Test func addingMonthsKeepsTheDayWhenItExists() {
        #expect(day("2026-01-31").adding(months: 1) == day("2026-02-28"))
        #expect(day("2024-01-31").adding(months: 1) == day("2024-02-29"))
        #expect(day("2026-12-15").adding(months: 1) == day("2027-01-15"))
        #expect(day("2026-01-10").adding(months: -1) == day("2025-12-10"))
        #expect(day("2026-01-10").adding(months: -13) == day("2024-12-10"))
        #expect(day("2026-11-01").months(to: day("2027-01-01")) == 2)
        #expect(day("2026-11-01").months(to: day("2026-09-01")) == -2)
        #expect(day("2026-01-31").months(to: day("2026-02-28")) == 0)
    }

    /// Test 57: previous-or-same Monday.
    @Test func mondayOfAWeek() {
        #expect(day("2026-11-05").monday == day("2026-11-02"))
        #expect(day("2026-11-02").monday == day("2026-11-02"))
        #expect(day("2026-11-08").monday == day("2026-11-02"))
        #expect(day("2026-11-09").weekday == 1)
        #expect(day("2026-11-08").weekday == 7)
        #expect(day("2026-11-07").isWeekend && day("2026-11-08").isWeekend && !day("2026-11-06").isWeekend)
    }

    @Test func isoWeekNumbers() {
        #expect(day("2026-11-09").isoWeek == 46)
        #expect(day("2026-01-01").isoWeek == 1)
        #expect(day("2026-12-31").isoWeek == 53)
        #expect(day("2027-01-01").isoWeek == 53)
        #expect(day("2027-01-01").isoWeekYear == 2026)
        #expect(day("2024-12-30").isoWeek == 1)
        #expect(day("2024-12-30").isoWeekYear == 2025)
        #expect(day("2021-01-03").isoWeek == 53)
    }

    @Test func agreesWithFoundationOverFortyYears() {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone(identifier: "UTC")!
        var current = day("2000-01-01")
        while current < day("2040-01-01") {
            let date = current.date(in: iso.timeZone)
            let parts = iso.dateComponents([.year, .month, .day, .weekOfYear, .yearForWeekOfYear, .weekday], from: date)
            #expect(parts.year == current.year && parts.month == current.month && parts.day == current.day)
            #expect(parts.weekOfYear == current.isoWeek && parts.yearForWeekOfYear == current.isoWeekYear)
            #expect((parts.weekday! + 5) % 7 + 1 == current.weekday)
            current = current.adding(days: 3)
        }
    }

    @Test func todayIsTheDayOfTheWallClock() {
        let now = ISO8601DateFormatter().date(from: "2026-11-08T23:30:00Z")!
        #expect(CalendarDay.today(in: paris, now: now) == day("2026-11-09"))
        #expect(CalendarDay.today(in: TimeZone(identifier: "UTC")!, now: now) == day("2026-11-08"))
        #expect(CalendarDay.today(in: TimeZone(identifier: "America/Los_Angeles")!, now: now) == day("2026-11-08"))
    }

    @Test func aDateOfThePickerComesBackToTheSameDay() {
        let zones = ["Europe/Paris", "America/Sao_Paulo", "Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata"]
        for zone in zones.compactMap(TimeZone.init(identifier:)) {
            for iso in ["2026-03-29", "2026-10-25", "2026-11-01", "2026-12-31", "2027-02-28"] {
                #expect(CalendarDay(day(iso).date(in: zone), timeZone: zone) == day(iso), "\(iso) \(zone.identifier)")
            }
        }
    }

    @Test func monthsAndWeeksOfSwipes() {
        #expect(day("2026-11-05").firstOfMonth == day("2026-11-01"))
        #expect(day("2026-02-05").lastOfMonth == day("2026-02-28"))
        #expect(day("2024-02-05").daysInMonth == 29)
        #expect(day("2026-11-05").dayOfYear == 309)
        // Swiping a week keeps the weekday, swiping a month keeps the day of the month
        #expect(day("2026-11-05").sameWeekday(inWeekOf: day("2026-11-12")) == day("2026-11-12"))
        #expect(day("2026-11-08").sameWeekday(inWeekOf: day("2026-11-09")) == day("2026-11-15"))
        #expect(day("2026-01-31").sameDay(inMonthOf: day("2026-02-01")) == day("2026-02-28"))
        #expect(day("2026-01-15").sameDay(inMonthOf: day("2026-03-01")) == day("2026-03-15"))
    }

    @Test func rangesOfDays() {
        let range: DayRange = day("2026-10-26")...day("2026-11-15")
        #expect(range.count == 21)
        #expect(Array(range).first == day("2026-10-26") && Array(range).last == day("2026-11-15"))
        #expect(range.covers(day("2026-11-02")...day("2026-11-08")))
        #expect(!range.covers(day("2026-11-09")...day("2026-11-16")))
    }

    @Test func codedAsItsISOText() throws {
        let data = try JSONEncoder().encode([day("2026-11-05")])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-11-05"]"#)
        #expect(try JSONDecoder().decode([CalendarDay].self, from: data) == [day("2026-11-05")])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([CalendarDay].self, from: Data(#"["2026-11-31"]"#.utf8)) }
    }
}
