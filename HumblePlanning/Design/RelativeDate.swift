import Foundation

/// "now", "5 minutes ago", "3 hours ago", "2 days ago" from an ISO date-time of the server, in the
/// language of the app; the raw text when it cannot be read.
enum RelativeDate {
    static func text(_ iso: String?, now: Date = Date()) -> String {
        guard let iso, let date = parse(iso) else { return iso ?? "" }
        let seconds = now.timeIntervalSince(date)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        // "now" and "yesterday" rather than "in 0 seconds" and "1 day ago"
        formatter.dateTimeStyle = .named
        if seconds < 60 { return formatter.localizedString(from: DateComponents(second: 0)) }
        if seconds < 3600 { return formatter.localizedString(from: DateComponents(minute: -Int(seconds / 60))) }
        if seconds < 86_400 { return formatter.localizedString(from: DateComponents(hour: -Int(seconds / 3600))) }
        return formatter.localizedString(from: DateComponents(day: -Int(seconds / 86_400)))
    }

    static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}
