import Foundation
import Synchronization

/// Dates, times and sizes as the planning shows them, in the language of the app (`locale`). Fixed patterns
/// rather than the region's templates, as on Android; days are always Gregorian.
public enum PlanningFormat {
    /// "Monday 9 November", fr "Lundi 9 novembre"; not capitalized inside a sentence.
    public static func longLabel(_ day: CalendarDay, locale: Locale, capitalized: Bool = true) -> String {
        let text = format(day, pattern: "EEEE d MMMM", locale: locale)
        return capitalized ? capitalize(text, locale: locale) : text
    }

    /// The region's medium date: "Nov 9, 2026" (en-US), "9 nov. 2026" (fr), "09.11.2026" (de).
    public static func mediumLabel(_ day: CalendarDay, locale: Locale) -> String {
        formatter(key: "medium", locale: locale, timeZone: utc) { $0.dateStyle = .medium; $0.timeStyle = .none }
            .string(from: day.date(in: utc))
    }

    /// "November 2026", fr "Novembre 2026" (stand-alone month name).
    public static func monthLabel(_ day: CalendarDay, locale: Locale) -> String {
        capitalize(format(day, pattern: "LLLL yyyy", locale: locale), locale: locale)
    }

    /// Full name of the weekday, capitalized: "Monday", fr "Lundi".
    public static func weekdayName(_ day: CalendarDay, locale: Locale) -> String {
        capitalize(format(day, pattern: "EEEE", locale: locale), locale: locale)
    }

    /// Short weekday (1 = Monday … 7 = Sunday) without its final dot, capitalized: "Mon", fr "Lun", de "Mo".
    public static func shortWeekday(_ weekday: Int, locale: Locale) -> String {
        var text = symbols(locale: locale).short[weekday % 7]
        while text.hasSuffix(".") { text.removeLast() }
        return capitalize(text, locale: locale)
    }

    /// One-letter weekday (1 = Monday … 7 = Sunday): "M", fr "L".
    public static func narrowWeekday(_ weekday: Int, locale: Locale) -> String {
        capitalize(symbols(locale: locale).narrow[weekday % 7], locale: locale)
    }

    /// Label of a day column of the grid: "M 9" when the column is wide enough, else "9".
    public static func gridDayLabel(_ day: CalendarDay, cellWidth: Double, locale: Locale) -> String {
        cellWidth >= GridMetrics.weekdayLabelMinWidth ? "\(narrowWeekday(day.weekday, locale: locale)) \(day.day)" : "\(day.day)"
    }

    /// Dates of a task read out on a grid bar: "Nov 9, 2026 – Nov 11, 2026" over several days, else the long label.
    public static func barDates(_ task: PlanningTask, locale: Locale) -> String? {
        guard let first = CalendarDay(task.startDate) else { return nil }
        if let last = CalendarDay(task.lastDate), last != first {
            return "\(mediumLabel(first, locale: locale)) – \(mediumLabel(last, locale: locale))"
        }
        return longLabel(first, locale: locale)
    }

    /// The region's short date and time, for "offline since": "09/11/2026 14:05" (fr).
    public static func shortDateTime(_ date: Date, locale: Locale, timeZone: TimeZone = .current) -> String {
        formatter(key: "short-short", locale: locale, timeZone: timeZone) { $0.dateStyle = .short; $0.timeStyle = .short }
            .string(from: date)
    }

    /// "1.2 MB" (fr "1,2 MB"), "12 KB", "512 B": binary units, names not translated, KB rounded down,
    /// MB rounded half up like Java's `%.1f`.
    public static func fileSize(_ bytes: Int64, locale: Locale) -> String {
        if bytes >= 1024 * 1024 {
            let style = FloatingPointFormatStyle<Double>(locale: locale).grouping(.never)
                .precision(.fractionLength(1)).rounded(rule: .toNearestOrAwayFromZero)
            return (Double(bytes) / (1024 * 1024)).formatted(style) + " MB"
        }
        let style = IntegerFormatStyle<Int64>(locale: locale).grouping(.never)
        return bytes >= 1024 ? (bytes / 1024).formatted(style) + " KB" : bytes.formatted(style) + " B"
    }

    /// `"08:35:00"` → `"08:35"`
    public static func hhmm(_ time: String) -> String { String(time.prefix(5)) }

    /// `"8:05"` → `"08:05"`: comparable as text.
    public static func paddedTime(_ time: String) -> String {
        let value = hhmm(time)
        return String(repeating: "0", count: max(0, 5 - value.count)) + value
    }

    // MARK: Formatters

    private static let utc = TimeZone(identifier: "UTC")!
    private static let cache = Mutex<[String: DateFormatter]>([:])

    private static func format(_ day: CalendarDay, pattern: String, locale: Locale) -> String {
        formatter(key: "p:" + pattern, locale: locale, timeZone: utc) { $0.dateFormat = pattern }.string(from: day.date(in: utc))
    }

    private static func formatter(key: String, locale: Locale, timeZone: TimeZone,
                                  configure: (DateFormatter) -> Void) -> DateFormatter {
        let id = "\(key)|\(locale.identifier)|\(timeZone.identifier)"
        return cache.withLock { formatters in
            if let formatter = formatters[id] { return formatter }
            let formatter = DateFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = timeZone
            configure(formatter)
            formatters[id] = formatter
            return formatter
        }
    }

    /// Weekday names indexed from Sunday (0) to Saturday (6), as Foundation gives them.
    private static func symbols(locale: Locale) -> (short: [String], narrow: [String]) {
        let formatter = formatter(key: "symbols", locale: locale, timeZone: utc) { _ in }
        return (formatter.shortWeekdaySymbols, formatter.veryShortWeekdaySymbols)
    }

    private static func capitalize(_ text: String, locale: Locale) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }
}
