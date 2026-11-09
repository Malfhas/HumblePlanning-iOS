import Foundation

/// What the account may do, from the permissions of its role: the same rules as the web
/// (`use-permissions.ts`). The server checks everything anyway; this only shapes the screens.
public struct Access: Sendable, Equatable {
    public enum Scope: String, Sendable { case all, team, ownProject = "own_project", own, readonly }

    public let userId: String
    public let teamId: String?
    public let permissions: Set<String>
    public let isAdmin: Bool

    public init(userId: String, teamId: String?, permissions: Set<String>, isAdmin: Bool) {
        self.userId = userId
        self.teamId = teamId
        self.permissions = permissions
        self.isAdmin = isAdmin
    }

    public init(_ references: References) {
        self.init(userId: references.user.id, teamId: references.user.teamId,
                  permissions: Set(references.permissions), isAdmin: references.isAdmin)
    }

    public func has(_ permission: String) -> Bool { isAdmin || permissions.contains(permission) }

    /// The widest scope wins.
    public var modifyScope: Scope {
        if isAdmin || permissions.contains("scope:modify_all") { return .all }
        if permissions.contains("scope:modify_team") { return .team }
        if permissions.contains("scope:modify_own_project") { return .ownProject }
        if permissions.contains("scope:modify_own") { return .own }
        return .readonly
    }

    public var canCreateTask: Bool { has("tasks:create") && modifyScope != .readonly }

    public func canModify(_ task: PlanningTask) -> Bool {
        switch modifyScope {
        case .all: true
        case .team: teamId != nil && task.users.contains { $0.teamId == teamId }
        case .ownProject: task.project?.ownerId == userId
        case .own: task.creatorId == userId || task.users.contains { $0.id == userId }
        case .readonly: false
        }
    }

    public func canDelete(_ task: PlanningTask) -> Bool { has("tasks:delete") && canModify(task) && !task.isLocked }
    public func canAssign(_ task: PlanningTask) -> Bool { has("tasks:assign") && canModify(task) && !task.isLocked }
    public func canLock(_ task: PlanningTask) -> Bool { has("tasks:lock") && canModify(task) }
    public func canEdit(_ task: PlanningTask) -> Bool { canModify(task) && (!task.isLocked || canLock(task)) }
    public func canDuplicate(_ task: PlanningTask) -> Bool { canCreateTask && !task.isLocked }

    public var canViewFiles: Bool { has("files:view") || has("pages:files") }
    public var canUploadFiles: Bool { has("files:upload") }
    public var canDeleteFiles: Bool { has("files:delete") }

    /// The people the account may put on a task.
    public func assignableUsers(_ all: [User]) -> [User] {
        switch modifyScope {
        case .team: all.filter { $0.teamId != nil && $0.teamId == teamId }
        case .own: all.filter { $0.id == userId }
        case .readonly: []
        case .all, .ownProject: all
        }
    }

    /// The people a copy of a task keeps: the assignable ones, else the account itself if it may.
    public func assignableAmong(_ ids: [String], all: [User]) -> [String] {
        if modifyScope == .all { return ids }
        let allowed = Set(assignableUsers(all).map(\.id))
        let kept = ids.filter { allowed.contains($0) }
        return kept.isEmpty ? [userId].filter { allowed.contains($0) } : kept
    }
}
