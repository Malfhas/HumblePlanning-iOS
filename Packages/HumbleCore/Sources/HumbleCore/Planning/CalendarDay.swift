import Foundation

/// A day of the Gregorian calendar, without time or zone, as the server writes it (`YYYY-MM-DD`).
/// The arithmetic works on day numbers: adding days never shifts a day, whatever the time zone or a
/// daylight saving change. Weeks start on Monday and are numbered as in ISO 8601, whatever the region.
public struct CalendarDay: Hashable, Comparable, Strideable, Sendable, CustomStringConvertible {
    public let year: Int
    /// 1…12
    public let month: Int
    /// 1…31
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= Self.daysIn(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD` only, like `LocalDate.parse`; nil for anything else (a date-time, a missing zero, a 31 April).
    public init?(_ iso: String) {
        let chars = Array(iso.utf8)
        guard chars.count == 10, chars[4] == UInt8(ascii: "-"), chars[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let c = chars[index]
                guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(c - UInt8(ascii: "0"))
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day of `date` on the wall clock of `timeZone`.
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(unchecked: parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Today on the device (or in `timeZone`).
    public static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> CalendarDay {
        CalendarDay(now, timeZone: timeZone)
    }

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    private init(epochDay: Int) {
        // civil_from_days (H. Hinnant)
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(unchecked: yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// `YYYY-MM-DD`, the form the server reads; ISO dates sort like days when compared as text.
    public var iso: String {
        func padded(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
        }
        return "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
    }

    public var description: String { iso }

    /// Days since 1970-01-01.
    public var epochDay: Int {
        // days_from_civil (H. Hinnant)
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Noon of this day in `timeZone`: on this day whatever a daylight saving change, for date pickers.
    public func date(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: Arithmetic

    public func adding(days: Int) -> CalendarDay { days == 0 ? self : CalendarDay(epochDay: epochDay + days) }

    /// Same day of another month, cut to the length of that month (31 January + 1 month = 28 or 29 February).
    public func adding(months: Int) -> CalendarDay {
        let total = year * 12 + (month - 1) + months
        let newYear = total >= 0 ? total / 12 : (total - 11) / 12
        let newMonth = total - newYear * 12 + 1
        return CalendarDay(unchecked: newYear, newMonth, Swift.min(day, Self.daysIn(month: newMonth, year: newYear)))
    }

    /// Days from this day to `other` (negative when `other` is before).
    public func days(to other: CalendarDay) -> Int { other.epochDay - epochDay }

    /// Whole months from this day to `other`, like `ChronoUnit.MONTHS.between`.
    public func months(to other: CalendarDay) -> Int {
        let a = (year * 12 + month - 1) * 32 + day
        let b = (other.year * 12 + other.month - 1) * 32 + other.day
        return (b - a) / 32
    }

    public func distance(to other: CalendarDay) -> Int { days(to: other) }
    public func advanced(by n: Int) -> CalendarDay { adding(days: n) }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Weeks and months

    /// ISO day of the week: 1 = Monday … 7 = Sunday.
    public var weekday: Int {
        let value = (epochDay + 3) % 7
        return (value < 0 ? value + 7 : value) + 1
    }

    public var isMonday: Bool { weekday == 1 }
    public var isWeekend: Bool { weekday >= 6 }

    /// The Monday of its week (the day itself on a Monday).
    public var monday: CalendarDay { adding(days: 1 - weekday) }

    /// ISO 8601 week number (1…53): the week of the year that holds its Thursday.
    public var isoWeek: Int { (thursday.dayOfYear - 1) / 7 + 1 }

    /// Year the ISO week belongs to (31 December may be in week 1 of the next year).
    public var isoWeekYear: Int { thursday.year }

    private var thursday: CalendarDay { adding(days: 4 - weekday) }

    /// 1…366
    public var dayOfYear: Int { epochDay - CalendarDay(unchecked: year, 1, 1).epochDay + 1 }

    public var daysInMonth: Int { Self.daysIn(month: month, year: year) }
    public var firstOfMonth: CalendarDay { CalendarDay(unchecked: year, month, 1) }
    public var lastOfMonth: CalendarDay { CalendarDay(unchecked: year, month, daysInMonth) }

    /// The same weekday in the week of `day`: swiping weeks keeps the day of the week.
    public func sameWeekday(inWeekOf day: CalendarDay) -> CalendarDay { day.monday.adding(days: weekday - 1) }

    /// The same day of the month in the month of `day`, cut to its length: swiping months keeps the day.
    public func sameDay(inMonthOf day: CalendarDay) -> CalendarDay {
        CalendarDay(unchecked: day.year, day.month, Swift.min(self.day, day.daysInMonth))
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

extension CalendarDay: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = CalendarDay(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD date: \(text)")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

/// A period of whole days, both ends included.
public typealias DayRange = ClosedRange<CalendarDay>

extension ClosedRange where Bound == CalendarDay {
    /// Both ends of `other` are inside: nothing of it is left to load.
    public func covers(_ other: DayRange) -> Bool { contains(other.lowerBound) && contains(other.upperBound) }
}
