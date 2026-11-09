import Foundation

public struct RefName: Codable, Sendable, Hashable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct TaskFile: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    /// Stored name, used in the download URL.
    @DefaultEmptyString public var name: String
    /// Name shown.
    @DefaultEmptyString public var originalName: String
    @Default<Defaults.ZeroInt64> public var size: Int64
    @DefaultEmptyString public var mimeType: String
    public var uploadedAt: String?
}

/// A task of the planning: from the sync (notes cut to 200 characters, no files, link or recurrence)
/// or from `GET /api/tasks/{id}` (everything).
public struct PlanningTask: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    public var title: String?
    /// `YYYY-MM-DD`
    @DefaultEmptyString public var startDate: String
    public var endDate: String?
    /// Wall-clock `HH:MM:SS` without zone (may be `H:MM`).
    public var startTime: String?
    public var endTime: String?
    public var notes: String?
    public var link: String?
    @DefaultFalse public var isLocked: Bool
    @DefaultFalse public var isMilestone: Bool
    /// Set on every occurrence of a series, equal to `id` on its root.
    public var parentId: String?
    public var placeText: String?
    public var placeTextLat: String?
    public var placeTextLng: String?
    @DefaultEmptyString public var projectId: String
    @DefaultEmptyString public var statusId: String
    public var placeId: String?
    public var resourceId: String?
    public var creatorId: String?
    public var updatedAt: String?
    @DefaultZero public var fileCount: Int
    @DefaultEmpty<TaskFile> public var files: [TaskFile]
    public var recurType: String?
    public var recurFrequency: Int?
    public var recurEndDate: String?
    public var recurException: String?
    public var project: Project?
    public var status: TaskStatus?
    public var place: RefName?
    public var resource: RefName?
    @DefaultEmpty<User> public var users: [User]

    public init(id: String, title: String? = nil, startDate: String, endDate: String? = nil, startTime: String? = nil,
                endTime: String? = nil, notes: String? = nil, isLocked: Bool = false, isMilestone: Bool = false,
                parentId: String? = nil, placeText: String? = nil, projectId: String = "", statusId: String = "",
                creatorId: String? = nil, fileCount: Int = 0, project: Project? = nil, status: TaskStatus? = nil,
                place: RefName? = nil, users: [User] = []) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.isLocked = isLocked
        self.isMilestone = isMilestone
        self.parentId = parentId
        self.placeText = placeText
        self.projectId = projectId
        self.statusId = statusId
        self.creatorId = creatorId
        self.fileCount = fileCount
        self.project = project
        self.status = status
        self.place = place
        self.users = users
    }

    public var isRecurring: Bool { parentId != nil }
    public var isSeriesRoot: Bool { parentId == id }
    /// The last day of the task (its start date for a one-day task).
    public var lastDate: String { (endDate ?? "").isEmpty ? startDate : endDate! }
    public var isMultiDay: Bool { lastDate != startDate }
    public var hasAttachments: Bool { fileCount > 0 || !files.isEmpty }
    /// Notes with some text (the sync sends their first 200 characters).
    public var hasNotes: Bool { !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var placeLabel: String? {
        if let name = place?.name { return name }
        let text = (placeText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    public var userIds: [String] { users.map(\.id) }
    public var isAllDay: Bool { (startTime ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    /// Dates compared as text: ISO dates sort like days.
    public func occursOn(_ day: String) -> Bool { startDate <= day && day <= lastDate }

    /// `"08:00 – 12:00"`, `"08:00"` without an end, nil for an all-day task.
    public var timeRange: String? {
        let start = (startTime ?? "").prefix(5)
        guard !start.isEmpty else { return nil }
        let end = (endTime ?? "").prefix(5)
        return end.isEmpty ? String(start) : "\(start) – \(end)"
    }
}

extension Array where Element == PlanningTask {
    /// Order inside a day: tasks over several days, then all-day ones, then by start time, title, id.
    public func sortedForDay() -> [PlanningTask] {
        func kind(_ task: PlanningTask) -> Int { task.isMultiDay ? 0 : task.isAllDay ? 1 : 2 }
        func time(_ task: PlanningTask) -> String {
            let value = String((task.startTime ?? "").prefix(5))
            return String(repeating: "0", count: Swift.max(0, 5 - value.count)) + value
        }
        return sorted { a, b in
            if kind(a) != kind(b) { return kind(a) < kind(b) }
            if time(a) != time(b) { return time(a) < time(b) }
            let ta = (a.title ?? "").lowercased(), tb = (b.title ?? "").lowercased()
            if ta != tb { return ta < tb }
            return a.id < b.id
        }
    }
}

/// `GET /api/mobile/tasks/sync`
public struct TaskSync: Codable, Sendable {
    @DefaultEmptyString public var serverTime: String
    @DefaultEmpty<PlanningTask> public var changed: [PlanningTask]
    /// Every task of the range in the user's read scope: a missing id was deleted or left the range.
    @DefaultEmpty<String> public var ids: [String]
}

/// Body of `POST /api/tasks` and `PUT /api/tasks/{id}`: every field is written so that clearing clears,
/// except the ones the server must keep when absent.
public struct TaskPayload: Encodable, Sendable, Equatable {
    public var projectId: String
    public var userIds: [String]
    public var statusId: String
    public var startDate: String
    public var endDate: String?
    public var startTime: String?
    public var endTime: String?
    public var title: String
    public var notes: String
    public var link: String?
    public var placeId: String?
    public var placeText: String?
    /// Written (as null) only when the address of an existing task changed: the server keeps them otherwise.
    public var clearPlaceCoordinates: Bool
    public var resourceId: String?
    public var isMilestone: Bool
    /// Omitted unless editing a task the user may lock.
    public var isLocked: Bool?

    public init(projectId: String, userIds: [String], statusId: String, startDate: String, endDate: String? = nil,
                startTime: String? = nil, endTime: String? = nil, title: String = "", notes: String = "",
                link: String? = nil, placeId: String? = nil, placeText: String? = nil, clearPlaceCoordinates: Bool = false,
                resourceId: String? = nil, isMilestone: Bool = false, isLocked: Bool? = nil) {
        self.projectId = projectId
        self.userIds = userIds
        self.statusId = statusId
        self.startDate = startDate
        self.endDate = endDate
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.notes = notes
        self.link = link
        self.placeId = placeId
        self.placeText = placeText
        self.clearPlaceCoordinates = clearPlaceCoordinates
        self.resourceId = resourceId
        self.isMilestone = isMilestone
        self.isLocked = isLocked
    }

    enum CodingKeys: String, CodingKey {
        case projectId, userIds, statusId, startDate, endDate, startTime, endTime, title, notes, link, placeId,
             placeText, placeTextLat, placeTextLng, resourceId, isMilestone, isLocked
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectId, forKey: .projectId)
        try c.encode(userIds, forKey: .userIds)
        try c.encode(statusId, forKey: .statusId)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(title, forKey: .title)
        try c.encode(notes, forKey: .notes)
        try c.encode(link, forKey: .link)
        try c.encode(placeId, forKey: .placeId)
        try c.encode(placeText, forKey: .placeText)
        if clearPlaceCoordinates {
            try c.encodeNil(forKey: .placeTextLat)
            try c.encodeNil(forKey: .placeTextLng)
        }
        try c.encode(resourceId, forKey: .resourceId)
        try c.encode(isMilestone, forKey: .isMilestone)
        try c.encodeIfPresent(isLocked, forKey: .isLocked)
    }
}

/// `POST /api/tasks/{id}/repeat`
public struct RepeatRequest: Encodable, Sendable, Equatable {
    /// `daily`, `weekly` or `monthly`
    public var recurType: String
    /// 1…30
    public var recurFrequency: Int
    /// `YYYY-MM-DD`, after the start date
    public var recurEndDate: String
    /// `skip`, `shift` or `include`
    public var recurException: String

    public init(recurType: String, recurFrequency: Int, recurEndDate: String, recurException: String) {
        self.recurType = recurType
        self.recurFrequency = recurFrequency
        self.recurEndDate = recurEndDate
        self.recurException = recurException
    }
}

/// How much of a series a deletion takes.
public enum DeleteScope: String, Sendable {
    case single, after, all
}
