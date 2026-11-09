import Testing
@testable import HumbleCore

/// `AccessTest` (tests 20–30): me = `me`, my team `t1`; by default a task created by `other`, with one assignee
/// `other` of team `t2`, in a project owned by `other`.
@Suite struct AccessTests {
    private let me = "me"

    private func access(_ permissions: String..., admin: Bool = false, team: String? = "t1") -> Access {
        Access(userId: me, teamId: team, permissions: Set(permissions), isAdmin: admin)
    }

    private func task(creator: String? = "other", users: [User] = [User(id: "other", name: "", teamId: "t2")],
                      owner: String? = "other", locked: Bool = false) -> PlanningTask {
        PlanningTask(id: "x", startDate: "2026-11-05", isLocked: locked, creatorId: creator,
                     project: Project(id: "p", name: "", ownerId: owner), users: users)
    }

    @Test func adminMayDoEverything() {
        let a = access(admin: true)
        #expect(a.canModify(task()) && a.canCreateTask && a.canDelete(task()) && a.canLock(task()))
    }

    @Test func scopeAllModifiesAnyTask() {
        #expect(access("scope:modify_all").canModify(task()))
    }

    @Test func scopeTeamNeedsAnAssigneeOfTheTeam() {
        let a = access("scope:modify_team")
        #expect(!a.canModify(task()))
        #expect(a.canModify(task(users: [User(id: "colleague", name: "", teamId: "t1")])))
    }

    @Test func scopeTeamWithoutATeamModifiesNothing() {
        #expect(!access("scope:modify_team", team: nil).canModify(task(users: [User(id: "somebody", name: "")])))
    }

    @Test func scopeOwnProjectNeedsToOwnTheProject() {
        let a = access("scope:modify_own_project")
        #expect(!a.canModify(task()))
        #expect(a.canModify(task(owner: me)))
    }

    @Test func scopeOwnNeedsToBeCreatorOrAssignee() {
        let a = access("scope:modify_own")
        #expect(!a.canModify(task()))
        #expect(a.canModify(task(creator: me)))
        #expect(a.canModify(task(users: [User(id: me, name: "")])))
    }

    @Test func noScopeIsReadOnly() {
        let a = access("tasks:create", "tasks:delete")
        #expect(!a.canModify(task(creator: me, owner: me)))
        #expect(!a.canCreateTask)
    }

    @Test func widestScopeWins() {
        #expect(access("scope:modify_own", "scope:modify_all").canModify(task()))
    }

    @Test func lockedTaskCannotBeDeletedAssignedOrCopied() {
        let a = access("scope:modify_all", "tasks:delete", "tasks:assign", "tasks:create")
        let locked = task(locked: true)
        #expect(!a.canDelete(locked) && !a.canAssign(locked) && !a.canDuplicate(locked))
        #expect(a.canDelete(task()) && a.canAssign(task()) && a.canDuplicate(task()))
    }

    @Test func lockedTaskCanOnlyBeEditedByWhoMayLock() {
        let locked = task(locked: true)
        #expect(!access("scope:modify_all").canEdit(locked))
        #expect(access("scope:modify_all", "tasks:lock").canEdit(locked))
        #expect(access("scope:modify_all").canEdit(task()))
    }

    @Test func filesFollowTheirPermissions() {
        #expect(access("files:view").canViewFiles)
        #expect(access("pages:files").canViewFiles)
        #expect(!access().canViewFiles)
        #expect(access("files:upload").canUploadFiles)
        #expect(!access("files:view").canUploadFiles)
        #expect(access("files:delete").canDeleteFiles)
    }

    @Test func assignableUsersFollowTheScope() {
        let all = [User(id: me, name: "", teamId: "t1"), User(id: "colleague", name: "", teamId: "t1"),
                   User(id: "other", name: "", teamId: "t2")]
        #expect(access("scope:modify_all").assignableUsers(all).count == 3)
        #expect(access("scope:modify_own_project").assignableUsers(all).count == 3)
        #expect(access("scope:modify_team").assignableUsers(all).map(\.id) == [me, "colleague"])
        #expect(access("scope:modify_own").assignableUsers(all).map(\.id) == [me])
        #expect(access().assignableUsers(all).isEmpty)
        // A copy keeps the assignable people, else me
        #expect(access("scope:modify_team").assignableAmong(["other", "colleague"], all: all) == ["colleague"])
        #expect(access("scope:modify_team").assignableAmong(["other"], all: all) == [me])
        #expect(access().assignableAmong(["other"], all: all).isEmpty)
        #expect(access("scope:modify_all").assignableAmong(["ghost"], all: all) == ["ghost"])
    }

    /// `DisplayNameTest` (test 31) and the project label.
    @Test func namesOfPeopleAndProjects() {
        #expect(User(id: "u", name: "Turner", firstName: "Liam").displayName == "Liam Turner")
        #expect(User(id: "u", name: "Liam Turner", firstName: "Liam").displayName == "Liam Turner")
        #expect(User(id: "u", name: "Turner").displayName == "Turner")
        #expect(User(id: "u", name: "Turner", firstName: " ").displayName == "Turner")
        #expect(Project(id: "p", name: "Roof", businessNumber: "42").label == "[42] Roof")
        #expect(Project(id: "p", name: "Roof", businessNumber: " ").label == "Roof")
    }
}
