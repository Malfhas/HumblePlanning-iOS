import Foundation

public struct Role: Codable, Sendable, Hashable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    @DefaultFalse public var isAdmin: Bool
}

/// A person of the planning (also the signed-in user, and the people assigned to a task).
public struct User: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var firstName: String?
    public var username: String?
    public var email: String?
    public var color: String?
    /// Avatar path, see `avatarURL(server:image:)`.
    public var image: String?
    public var teamId: String?
    public var businessUnitId: String?
    public var phone: String?
    public var mobile: String?
    public var job: String?
    @DefaultTrue public var active: Bool
    /// Order inside its team on the grid.
    @DefaultZero public var sortOrder: Int
    public var role: Role?
    @DefaultFalse public var twoFactorEnabled: Bool
    @DefaultFalse public var forceTwoFactor: Bool
    @DefaultFalse public var forcePasswordChange: Bool
    /// Alerts on the phone allowed by an administrator.
    @DefaultTrue public var mobilePushNotifications: Bool
    /// The user's own choice.
    @DefaultTrue public var mobilePushNotificationsUser: Bool

    public init(id: String, name: String, firstName: String? = nil, color: String? = nil, image: String? = nil,
                teamId: String? = nil, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.firstName = firstName
        self.color = color
        self.image = image
        self.teamId = teamId
        self.sortOrder = sortOrder
    }

    /// "First Last", without repeating a first name already in `name` (assignees of a task come with
    /// `name` = "First Last").
    public var displayName: String {
        let first = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty || name == first || name.hasPrefix(first + " ") { return name }
        return first + " " + name
    }
}

public struct ProjectGroup: Codable, Sendable, Hashable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var color: String?
    @DefaultZero public var sortOrder: Int
}

public struct BusinessUnit: Codable, Sendable, Hashable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var number: String?
    public var color: String?
}

public struct Project: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var color: String?
    public var businessNumber: String?
    public var businessUnitId: String?
    public var ownerId: String?
    public var status: String?
    public var address: String?
    public var addressLat: String?
    public var addressLng: String?
    public var group: ProjectGroup?
    public var businessUnit: BusinessUnit?

    public init(id: String, name: String, color: String? = nil, businessNumber: String? = nil, ownerId: String? = nil,
                status: String? = nil, group: ProjectGroup? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.businessNumber = businessNumber
        self.ownerId = ownerId
        self.status = status
        self.group = group
    }

    /// "[number] name", or the name alone.
    public var label: String {
        let number = (businessNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? name : "[\(number)] \(name)"
    }
}

public struct TaskStatus: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var color: String?
    @DefaultFalse public var isDefault: Bool
    @DefaultTrue public var showInList: Bool
    @DefaultZero public var sortOrder: Int
    @DefaultFalse public var bold: Bool
    @DefaultFalse public var italic: Bool
    @DefaultFalse public var strikethrough: Bool
    @DefaultFalse public var underline: Bool

    public init(id: String, name: String, color: String? = nil, isDefault: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }
}

public struct Place: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var color: String?
}

public struct PlanningResource: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var color: String?
    public var status: String?
    public var businessUnitId: String?
}

public struct Team: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    @DefaultEmptyString public var name: String
    public var color: String?
    @DefaultZero public var sortOrder: Int
    @DefaultEmpty<String> public var userIds: [String]

    public init(id: String, name: String, color: String? = nil, sortOrder: Int = 0, userIds: [String] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.userIds = userIds
    }
}

public struct Holiday: Codable, Sendable, Hashable, Identifiable {
    @DefaultEmptyString public var id: String
    /// `YYYY-MM-DD`
    @DefaultEmptyString public var date: String
    public var label: String?
    public var color: String?

    public init(id: String, date: String, label: String? = nil, color: String? = nil) {
        self.id = id
        self.date = date
        self.label = label
        self.color = color
    }
}

public struct AssistantAccess: Codable, Sendable, Hashable {
    @DefaultFalse public var available: Bool
    @DefaultFalse public var canWrite: Bool

    public init(available: Bool = false, canWrite: Bool = false) {
        self.available = available
        self.canWrite = canWrite
    }
}

/// `GET /api/mobile/bootstrap`. A list the role cannot read is `null`, taken as empty.
public struct Bootstrap: Codable, Sendable {
    @DefaultEmptyString public var serverTime: String
    public var user: User?
    @DefaultEmpty<String> public var permissions: [String]
    @DefaultFalse public var isAdmin: Bool
    @Default<Defaults.EmptyMap<String?>> public var config: [String: String?]
    public var assistant: AssistantAccess?
    public var statuses: [TaskStatus]?
    public var places: [Place]?
    public var projects: [Project]?
    public var users: [User]?
    public var teams: [Team]?
    public var businessUnits: [BusinessUnit]?
    public var holidays: [Holiday]?
    public var resources: [PlanningResource]?
}

/// Reference data of the account: kept in memory, and encrypted on the phone for offline use.
public struct References: Codable, Sendable, Equatable {
    public var user: User
    public var permissions: [String]
    public var isAdmin: Bool
    public var config: [String: String?]
    public var assistant: AssistantAccess
    public var projects: [Project]
    public var statuses: [TaskStatus]
    public var users: [User]
    public var teams: [Team]
    public var places: [Place]
    public var resources: [PlanningResource]
    public var holidays: [Holiday]

    public init(user: User = User(id: "", name: ""), permissions: [String] = [], isAdmin: Bool = false,
                config: [String: String?] = [:], assistant: AssistantAccess = AssistantAccess(),
                projects: [Project] = [], statuses: [TaskStatus] = [], users: [User] = [], teams: [Team] = [],
                places: [Place] = [], resources: [PlanningResource] = [], holidays: [Holiday] = []) {
        self.user = user
        self.permissions = permissions
        self.isAdmin = isAdmin
        self.config = config
        self.assistant = assistant
        self.projects = projects
        self.statuses = statuses
        self.users = users
        self.teams = teams
        self.places = places
        self.resources = resources
        self.holidays = holidays
    }

    /// Sorted and filtered as the screens show them.
    public init(_ boot: Bootstrap) {
        let user = boot.user ?? User(id: "", name: "")
        var users = boot.users ?? []
        // A user hidden from the planning still sees their own tasks
        if !user.id.isEmpty, !users.contains(where: { $0.id == user.id }) { users.append(user) }
        self.init(
            user: user,
            permissions: boot.permissions,
            isAdmin: boot.isAdmin,
            config: boot.config,
            assistant: boot.assistant ?? AssistantAccess(),
            projects: (boot.projects ?? []).filter { $0.status != "archived" }.sorted {
                let a = $0.group?.sortOrder ?? Int.max, b = $1.group?.sortOrder ?? Int.max
                return a != b ? a < b : $0.name.lowercased() < $1.name.lowercased()
            },
            statuses: (boot.statuses ?? []).sorted { $0.sortOrder < $1.sortOrder },
            users: users.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() },
            teams: (boot.teams ?? []).sorted { $0.sortOrder < $1.sortOrder },
            places: (boot.places ?? []).sorted { $0.name.lowercased() < $1.name.lowercased() },
            resources: (boot.resources ?? []).sorted { $0.name.lowercased() < $1.name.lowercased() },
            holidays: boot.holidays ?? []
        )
    }

    public func project(_ id: String?) -> Project? { id.flatMap { id in projects.first { $0.id == id } } }
    public func status(_ id: String?) -> TaskStatus? { id.flatMap { id in statuses.first { $0.id == id } } }
    public func person(_ id: String?) -> User? { id.flatMap { id in users.first { $0.id == id } } }

    // MARK: Settings of the server

    /// `"true"` or `"1"` → true; any other present value → false; missing or null → the default.
    public func flag(_ key: String, default value: Bool) -> Bool {
        guard let stored = config[key], let text = stored else { return value }
        return text == "true" || text == "1"
    }

    private func text(_ key: String, default value: String) -> String {
        let stored = (config[key] ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? value : stored
    }

    public var placesEnabled: Bool { flag("MODULE_PLACES", default: true) }
    public var resourcesEnabled: Bool { flag("MODULE_RESOURCES", default: true) }
    public var filesEnabled: Bool { flag("ENABLE_FILE_UPLOAD", default: true) }
    public var morningStart: String { text("AM_START", default: "08:00") }
    public var morningEnd: String { text("AM_END", default: "12:00") }
    public var afternoonStart: String { text("PM_START", default: "14:00") }
    public var afternoonEnd: String { text("PM_END", default: "17:00") }
    public var maxUploadBytes: Int64 {
        (Int64((config["MAX_UPLOAD_SIZE_MB"] ?? nil)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 10) * 1024 * 1024
    }
    /// Empty = every extension allowed.
    public var uploadExtensions: [String] {
        ((config["WHITELIST_UPLOAD"] ?? nil) ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
    public var alertsSettingVisible: Bool { (config["MOBILE_PUSH_ENABLED"] ?? nil) != "false" }
}
