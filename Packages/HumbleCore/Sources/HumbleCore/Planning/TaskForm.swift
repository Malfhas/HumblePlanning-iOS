import Foundation

/// When in the day a task takes place.
public enum DayMode: String, Codable, CaseIterable, Sendable {
    case allDay = "AllDay", morning = "Morning", afternoon = "Afternoon", times = "Times"
}

/// A field the form shows in error.
public enum TaskFormField: Sendable, Hashable {
    case project, users, status, link, frequency
}

/// Input errors checked before sending, in the order they are checked; the raw value is the key of the message.
public enum FormError: String, Error, CaseIterable, Sendable {
    case projectRequired = "val_project"
    case usersRequired = "val_users"
    case statusRequired = "val_status"
    case startDateRequired = "val_start"
    case endDateBeforeStart = "val_end_before_start"
    case timesRequired = "val_times"
    case endTimeBeforeStart = "val_end_time"
    case textTooLong = "val_text_long"
    case linkInvalid = "val_link"
    case recurrenceEndRequired = "val_recur_end"
    case recurrenceEndBeforeStart = "val_recur_end_before"
    case recurrenceFrequency = "val_recur_frequency"

    /// The field highlighted with the message, if any.
    public var field: TaskFormField? {
        switch self {
        case .projectRequired: .project
        case .usersRequired: .users
        case .statusRequired: .status
        case .linkInvalid: .link
        case .recurrenceFrequency: .frequency
        default: nil
        }
    }
}

/// What the task form edits. Dates are `YYYY-MM-DD` and compared as text, times `HH:mm`.
public struct TaskForm: Codable, Sendable, Hashable {
    public enum TimeField: Sendable { case start, end }
    public enum DateField: Sendable { case start, end, recurrenceEnd }

    /// Longest title and address.
    public static let maxTextLength = 255

    public var projectId = ""
    public var userIds: [String] = []
    public var statusId = ""
    public var startDate = ""
    /// Empty for a single day.
    public var endDate = ""
    public var mode = DayMode.allDay
    /// Filled in `.times` mode only.
    public var startTime = ""
    public var endTime = ""
    public var title = ""
    public var placeId = ""
    /// Free address, exclusive with `placeId`.
    public var placeText = ""
    public var resourceId = ""
    public var link = ""
    public var milestone = false
    public var locked = false
    public var notes = ""
    /// Make a series of it (the switch "Repeat").
    public var repeats = false
    /// `daily`, `weekly` or `monthly`
    public var recurType = "weekly"
    /// 0 while the field is empty.
    public var recurFrequency = 1
    public var recurEndDate = ""
    /// `skip`, `shift` or `include`
    public var recurException = "skip"
    /// Change every occurrence of the series.
    public var applyToAll = false

    public init() {}

    /// A loaded task: times equal to the server's half days are the morning or the afternoon, other times are custom.
    public init(task: PlanningTask, references: References) {
        let start = Self.nonBlank(task.startTime).map(PlanningFormat.hhmm) ?? ""
        let end = Self.nonBlank(task.endTime).map(PlanningFormat.hhmm) ?? ""
        let padded = (PlanningFormat.paddedTime(start), PlanningFormat.paddedTime(end))
        mode = if start.isEmpty {
            .allDay
        } else if padded == (PlanningFormat.paddedTime(references.morningStart), PlanningFormat.paddedTime(references.morningEnd)) {
            .morning
        } else if padded == (PlanningFormat.paddedTime(references.afternoonStart), PlanningFormat.paddedTime(references.afternoonEnd)) {
            .afternoon
        } else {
            .times
        }
        projectId = task.projectId
        userIds = task.userIds
        statusId = task.statusId
        startDate = task.startDate
        endDate = task.endDate == task.startDate ? "" : task.endDate ?? ""
        startTime = mode == .times ? start : ""
        endTime = mode == .times ? end : ""
        title = task.title ?? ""
        placeId = task.placeId ?? ""
        placeText = task.placeText ?? ""
        resourceId = task.resourceId ?? ""
        link = task.link ?? ""
        milestone = task.isMilestone
        locked = task.isLocked
        notes = task.notes ?? ""
        repeats = task.isSeriesRoot
        recurType = task.recurType ?? "weekly"
        recurFrequency = task.recurFrequency ?? 1
        recurEndDate = task.recurEndDate ?? ""
        recurException = task.recurException ?? "skip"
    }

    // MARK: Checks and requests

    /// The first rule broken, nil when the form may be sent (the server checks again).
    public var validationError: FormError? {
        let singleDay = endDate.isEmpty || endDate == startDate
        if projectId.isEmpty { return .projectRequired }
        if userIds.isEmpty { return .usersRequired }
        if statusId.isEmpty { return .statusRequired }
        if startDate.isEmpty { return .startDateRequired }
        if !endDate.isEmpty && endDate < startDate { return .endDateBeforeStart }
        if mode == .times && (!Self.isTime(startTime) || !Self.isTime(endTime)) { return .timesRequired }
        // Over several days the end may be earlier in the day
        if mode == .times && singleDay && PlanningFormat.paddedTime(endTime) <= PlanningFormat.paddedTime(startTime) {
            return .endTimeBeforeStart
        }
        if title.utf16.count > Self.maxTextLength || placeText.utf16.count > Self.maxTextLength { return .textTooLong }
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLink.isEmpty && !WebLink.isValid(trimmedLink) { return .linkInvalid }
        if repeats && recurEndDate.isEmpty { return .recurrenceEndRequired }
        if repeats && recurEndDate <= startDate { return .recurrenceEndBeforeStart }
        if repeats && !(1...30).contains(recurFrequency) { return .recurrenceFrequency }
        return nil
    }

    /// Body of the request. Optional text goes out as null, except the title and the notes, which the server
    /// refuses as null: they go out empty. `isLocked` only with the right to lock; the coordinates of the address
    /// are cleared only when an existing task's address changed.
    public func payload(references: References, canLock: Bool, placeTextChanged: Bool = false) -> TaskPayload {
        let times: (String?, String?) = switch mode {
        case .allDay: (nil, nil)
        case .morning: (references.morningStart, references.morningEnd)
        case .afternoon: (references.afternoonStart, references.afternoonEnd)
        case .times: (PlanningFormat.paddedTime(startTime), PlanningFormat.paddedTime(endTime))
        }
        return TaskPayload(
            projectId: projectId,
            userIds: userIds,
            statusId: statusId,
            startDate: startDate,
            endDate: endDate.isEmpty || endDate == startDate ? nil : endDate,
            startTime: times.0,
            endTime: times.1,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            link: Self.nonEmpty(link.trimmingCharacters(in: .whitespacesAndNewlines)),
            placeId: Self.nonEmpty(placeId),
            placeText: Self.nonEmpty(placeText.trimmingCharacters(in: .whitespacesAndNewlines)),
            clearPlaceCoordinates: placeTextChanged,
            resourceId: Self.nonEmpty(resourceId),
            isMilestone: milestone,
            isLocked: canLock ? locked : nil
        )
    }

    /// Body of `POST /api/tasks/{id}/repeat`.
    public var repeatRequest: RepeatRequest {
        RepeatRequest(recurType: recurType, recurFrequency: recurFrequency, recurEndDate: recurEndDate,
                      recurException: recurException)
    }

    /// Same recurrence rule (type, frequency, end, exception).
    public func hasSameRule(as other: TaskForm) -> Bool {
        (recurType, recurFrequency, recurEndDate, recurException)
            == (other.recurType, other.recurFrequency, other.recurEndDate, other.recurException)
    }

    // MARK: Edits as the screen makes them

    /// A new start; the end goes when it would now be before it.
    public mutating func setStartDate(_ day: CalendarDay) {
        startDate = day.iso
        if !endDate.isEmpty && endDate < startDate { endDate = "" }
    }

    /// The start day itself, or nil, means a single day.
    public mutating func setEndDate(_ day: CalendarDay?) {
        endDate = day.map(\.iso) == startDate ? "" : day?.iso ?? ""
    }

    public mutating func setRecurrenceEnd(_ day: CalendarDay) { recurEndDate = day.iso }

    /// Cut to 255 characters while typing.
    public mutating func setTitle(_ text: String) { title = Self.cut(text) }

    /// Cut to 255 characters; typed text replaces the chosen place.
    public mutating func setPlaceText(_ text: String) {
        placeText = Self.cut(text)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { placeId = "" }
    }

    /// A chosen place replaces the typed address; nil = none.
    public mutating func setPlace(_ id: String?) {
        placeId = id ?? ""
        if !placeId.isEmpty { placeText = "" }
    }

    /// The "repeat every" field: empty for 0, digits only, 2 at most.
    public var frequencyText: String {
        get { recurFrequency == 0 ? "" : String(recurFrequency) }
        set { recurFrequency = Int(String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(2))) ?? 0 }
    }

    /// A time picked on the 24-hour clock, stored `HH:mm`.
    public mutating func setTime(_ field: TimeField, hour: Int, minute: Int) {
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        let value = "\(two(hour)):\(two(minute))"
        switch field {
        case .start: startTime = value
        case .end: endTime = value
        }
    }

    /// Where the time picker opens: the value, else the server's morning start (or end), else 08:00.
    public func timePickerStart(_ field: TimeField, references: References) -> (hour: Int, minute: Int) {
        let value = field == .start ? startTime : endTime
        let current = Self.nonBlank(value) ?? (field == .start ? references.morningStart : references.morningEnd)
        let parts = current.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let hour = Int(parts[0]) ?? 8
        let minute = Int(String((parts.count > 1 ? parts[1] : parts[0]).prefix(2))) ?? 0
        return (min(max(hour, 0), 23), min(max(minute, 0), 59))
    }

    /// Where the date picker opens: the value, else the start date, else today.
    public func datePickerStart(_ field: DateField, today: CalendarDay) -> CalendarDay {
        let value = switch field {
        case .start: startDate
        case .end: endDate.isEmpty ? startDate : endDate
        case .recurrenceEnd: recurEndDate.isEmpty ? startDate : recurEndDate
        }
        return CalendarDay(value) ?? today
    }

    // MARK: Helpers

    /// `^([01]?\d|2[0-3]):[0-5]\d$`, ASCII digits only.
    static func isTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let hour = Array(parts[0].utf8), minute = Array(parts[1].utf8)
        func digit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }
        let hourOK = switch hour.count {
        case 1: digit(hour[0])
        case 2: digit(hour[0]) && digit(hour[1]) && (hour[0] <= UInt8(ascii: "1") || hour[0] == UInt8(ascii: "2") && hour[1] <= UInt8(ascii: "3"))
        default: false
        }
        return hourOK && minute.count == 2 && digit(minute[0]) && minute[0] <= UInt8(ascii: "5") && digit(minute[1])
    }

    private static func cut(_ text: String) -> String {
        guard text.utf16.count > maxTextLength else { return text }
        var result = "", length = 0
        for character in text {
            length += character.utf16.count
            if length > maxTextLength { break }
            result.append(character)
        }
        return result
    }

    private static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
