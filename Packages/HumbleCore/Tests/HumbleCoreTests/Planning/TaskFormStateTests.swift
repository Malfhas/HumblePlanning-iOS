import Testing
@testable import HumbleCore

/// The form's life (spec 02 §6.3, §6.6, spec 01 §3.4): defaults, edit, copy, dirty check, save requests, `createdId`.
@Suite struct TaskFormStateTests {
    private let me = User(id: "me", name: "Me", teamId: "t1")
    private let mate = User(id: "mate", name: "Mate", teamId: "t1")
    private let far = User(id: "far", name: "Far", teamId: "t2")

    private func refs(_ permissions: [String] = ["tasks:create", "tasks:assign", "scope:modify_all"],
                      statuses: [TaskStatus] = [TaskStatus(id: "s1", name: "To do"), TaskStatus(id: "s2", name: "Planned", isDefault: true)])
        -> References {
        References(user: me, permissions: permissions, projects: [Project(id: "p1", name: "Roof")], statuses: statuses,
                   users: [far, mate, me])
    }

    private func existing(locked: Bool = false, root: Bool = false, occurrence: Bool = false) -> PlanningTask {
        var t = task("t1", "2026-11-05", title: "Visit", users: ["far", "outsider"])
        t.isLocked = locked
        t.placeText = " 1 rue A "
        t.parentId = root ? "t1" : occurrence ? "root" : nil
        t.recurType = root ? "weekly" : nil
        t.recurEndDate = root ? "2026-12-31" : nil
        t.project = Project(id: "p1", name: "Roof", ownerId: "far")
        return t
    }

    // MARK: New task

    @Test func aNewTaskTakesItsDefaultsWithoutBecomingChanged() {
        var state = TaskFormState(kind: .create(date: "2026-11-12"))
        #expect(!state.loading && state.isNew && !state.isCopy && state.sourceId == nil)
        state.referencesChanged(refs(), today: day("2026-11-09"))
        #expect(state.form.statusId == "s2")
        #expect(state.form.userIds == ["me"])
        #expect(state.form.startDate == "2026-11-12")
        #expect(!state.dirty)
        var noDate = TaskFormState(kind: .create())
        noDate.referencesChanged(refs(statuses: [TaskStatus(id: "s1", name: ""), TaskStatus(id: "s3", name: "")]), today: day("2026-11-09"))
        #expect(noDate.form.startDate == "2026-11-09" && noDate.form.statusId == "s1")
    }

    @Test func referencesArrivingLateFillTheDefaults() {
        var state = TaskFormState(kind: .create())
        state.referencesChanged(References(), today: day("2026-11-09"))
        #expect(state.form.statusId == "" && state.form.userIds.isEmpty && !state.dirty)
        state.referencesChanged(refs(), today: day("2026-11-09"))
        #expect(state.form.statusId == "s2" && state.form.userIds == ["me"] && !state.dirty)
    }

    @Test func defaultsNeverOverwriteWhatTheUserChose() {
        var state = TaskFormState(kind: .create())
        state.referencesChanged(refs(), today: day("2026-11-09"))
        state.update { $0.statusId = "s1"; $0.userIds = ["mate"] }
        state.referencesChanged(refs(), today: day("2026-11-10"))
        #expect(state.form.statusId == "s1" && state.form.userIds == ["mate"] && state.form.startDate == "2026-11-09")
        #expect(state.dirty)
    }

    @Test func theGridRowGivesThePersonWhenAssignable() {
        var row = TaskFormState(kind: .create(date: "2026-11-12", userId: "mate"))
        row.referencesChanged(refs(["tasks:create", "scope:modify_team"]))
        #expect(row.form.userIds == ["mate"])
        var other = TaskFormState(kind: .create(userId: "far"))
        other.referencesChanged(refs(["tasks:create", "scope:modify_team"]))
        #expect(other.form.userIds.isEmpty)
        var reader = TaskFormState(kind: .create())
        reader.referencesChanged(refs([]))
        #expect(reader.form.userIds.isEmpty)
    }

    @Test func aRestoredNewFormKeepsItsValues() {
        var form = TaskForm()
        form.title = "typed"
        var state = TaskFormState(kind: .create(), restored: TaskFormDraft(form: form, initial: TaskForm(), createdId: "c1"))
        state.referencesChanged(refs())
        #expect(state.form == form && state.form.statusId == "" && state.dirty && state.createdId == "c1")
    }

    // MARK: Edit and copy

    @Test func editingStartsUnchanged() {
        var state = TaskFormState(kind: .edit(id: "t1"))
        #expect(state.loading && !state.isNew && state.sourceId == "t1" && !state.canSave)
        state.loaded(existing(), references: refs())
        #expect(!state.loading && state.canSave && !state.dirty)
        #expect(state.existing?.id == "t1" && state.form.title == "Visit")
        state.update { $0.title = "Other" }
        #expect(state.dirty)
        state.update { $0.title = "Visit" }
        #expect(!state.dirty)
    }

    @Test func aCopyKeepsOnlyWhoICanAssignAndIsChangedFromTheStart() {
        var state = TaskFormState(kind: .duplicate(of: "t1"))
        #expect(state.isNew && state.isCopy && state.sourceId == "t1")
        var source = existing(locked: true, root: true)
        source.users = [far, me]
        state.loaded(source, references: refs(["tasks:create", "scope:modify_own"]))
        #expect(state.form.userIds == ["me"])
        #expect(!state.form.locked && !state.form.repeats && !state.form.applyToAll)
        #expect(state.existing == nil && state.dirty && state.initial == TaskForm())
        var all = TaskFormState(kind: .duplicate(of: "t1"))
        all.loaded(existing(), references: refs())
        #expect(all.form.userIds == ["far", "outsider"])
    }

    @Test func aRestoredEditKeepsTheTypedForm() {
        var typed = TaskForm(task: existing(), references: refs())
        typed.title = "typed"
        let draft = TaskFormDraft(form: typed, initial: TaskForm(task: existing(), references: refs()))
        var state = TaskFormState(kind: .edit(id: "t1"), restored: draft)
        state.loaded(existing(), references: refs())
        #expect(state.form.title == "typed" && state.dirty && state.existing != nil)
    }

    @Test func aFailedLoadOffersToGoBack() {
        var state = TaskFormState(kind: .edit(id: "t1"))
        state.loadingFailed()
        #expect(state.loadFailed && !state.loading && !state.canSave)
    }

    // MARK: Save

    @Test func anInvalidFormSendsNothing() {
        var state = TaskFormState(kind: .create())
        #expect(state.prepareSave(references: refs()) == nil)
        #expect(state.validationError == .projectRequired && !state.saving)
        state.update { $0.projectId = "p1" }
        #expect(state.validationError == nil)
    }

    @Test func aNewSeriesIsCreatedThenRepeated() {
        var state = TaskFormState(kind: .create(date: "2026-11-05"))
        state.referencesChanged(refs())
        state.update { $0.projectId = "p1"; $0.repeats = true; $0.recurType = "daily"; $0.recurEndDate = "2026-11-08"; $0.recurException = "include" }
        let save = state.prepareSave(references: refs())!
        #expect(state.saving && !state.canSave)
        #expect(save.taskId == nil && save.payload.isLocked == nil && !save.payload.clearPlaceCoordinates)
        #expect(save.repeatRequest == RepeatRequest(recurType: "daily", recurFrequency: 1, recurEndDate: "2026-11-08", recurException: "include"))
        // The create succeeded, the repeat failed: saving again updates the created task
        state.taskSaved(id: "new1")
        state.saveFailed()
        #expect(state.createdId == "new1" && state.draft.createdId == "new1" && state.canSave)
        let retry = state.prepareSave(references: refs())!
        #expect(retry.taskId == "new1" && retry.repeatRequest != nil)
        state.taskSaved(id: "new1")
        state.saveSucceeded()
        #expect(state.saved && !state.saving && state.createdId == "new1")
    }

    @Test func aPlainNewTaskHasNoRepeat() {
        var state = TaskFormState(kind: .create(date: "2026-11-05"))
        state.referencesChanged(refs())
        state.update { $0.projectId = "p1" }
        #expect(state.prepareSave(references: refs())?.repeatRequest == nil)
    }

    @Test func editingASeriesRootRepeatsOnlyWhenTheRuleChanged() {
        var state = TaskFormState(kind: .edit(id: "t1"))
        state.loaded(existing(root: true), references: refs())
        state.update { $0.title = "Renamed"; $0.applyToAll = true }
        let same = state.prepareSave(references: refs())!
        #expect(same.taskId == "t1" && same.applyToAll && same.repeatRequest == nil)
        state.saveFailed()
        state.update { $0.recurFrequency = 2 }
        #expect(state.prepareSave(references: refs())?.repeatRequest?.recurFrequency == 2)
        // An edit never records a created id
        state.taskSaved(id: "t1")
        #expect(state.createdId == nil)
    }

    @Test func editingAnOccurrenceOrAPlainTaskNeverRepeats() {
        var occurrence = TaskFormState(kind: .edit(id: "t1"))
        occurrence.loaded(existing(occurrence: true), references: refs())
        #expect(!occurrence.form.repeats)
        #expect(occurrence.prepareSave(references: refs())?.repeatRequest == nil)
    }

    @Test func lockAndAddressCoordinatesOnEdit() {
        var state = TaskFormState(kind: .edit(id: "t1"))
        state.loaded(existing(), references: refs())
        state.update { $0.placeText = "1 rue A" }
        let unchanged = state.prepareSave(references: refs())!
        #expect(!unchanged.payload.clearPlaceCoordinates && unchanged.payload.isLocked == nil)
        state.saveFailed()
        state.update { $0.placeText = "2 rue B" }
        let changed = state.prepareSave(references: refs(["tasks:lock", "scope:modify_all"]))!
        #expect(changed.payload.clearPlaceCoordinates && changed.payload.isLocked == false)
    }

    // MARK: What the screen shows

    @Test func controlsFollowTheRights() {
        let full = Access(refs(["tasks:assign", "tasks:lock", "scope:modify_all"]))
        let plain = Access(refs(["scope:modify_all"]))
        let created = TaskFormState(kind: .create())
        #expect(created.canChangePeople(plain) && !created.showsLock(full))
        #expect(created.showsRecurrence && created.canChangeRepeat && !created.showsApplyToAll)

        var locked = TaskFormState(kind: .edit(id: "t1"))
        locked.loaded(existing(locked: true), references: refs())
        #expect(!locked.canChangePeople(full) && locked.showsLock(full) && !locked.showsLock(plain))
        #expect(!locked.showsRecurrence && !locked.showsApplyToAll)

        var root = TaskFormState(kind: .edit(id: "t1"))
        root.loaded(existing(root: true), references: refs())
        #expect(root.showsRecurrence && !root.canChangeRepeat && root.showsApplyToAll && root.form.repeats)

        var occurrence = TaskFormState(kind: .edit(id: "t1"))
        occurrence.loaded(existing(occurrence: true), references: refs())
        #expect(!occurrence.showsRecurrence && occurrence.showsApplyToAll)
    }

    @Test func peopleChoicesKeepThoseAlreadyOnTheTask() {
        var state = TaskFormState(kind: .edit(id: "t1"))
        let team = refs(["tasks:assign", "scope:modify_team"])
        state.loaded(existing(), references: team)
        #expect(state.peopleChoices(team).map(\.id) == ["mate", "me", "far", "outsider"])
        #expect(state.singlePersonName(team) == nil)
        state.update { $0.userIds = ["outsider"] }
        #expect(state.singlePersonName(team) == "outsider")
        state.update { $0.userIds = ["mate"] }
        #expect(state.singlePersonName(team) == "Mate")
    }

    @Test func archivedProjectAndStatusShowFromTheTask() {
        var source = existing()
        source.projectId = "old"
        source.project = Project(id: "old", name: "Archived")
        source.statusId = "gone"
        source.status = TaskStatus(id: "gone", name: "Gone")
        source.resourceId = "van"
        source.resource = RefName(id: "van", name: "Van")
        var state = TaskFormState(kind: .edit(id: "t1"))
        state.loaded(source, references: refs())
        #expect(state.project(refs())?.name == "Archived")
        #expect(state.status(refs())?.name == "Gone")
        #expect(state.resourceName(refs()) == "Van")
        state.update { $0.projectId = "p1"; $0.statusId = "s1"; $0.resourceId = "" }
        #expect(state.project(refs())?.name == "Roof" && state.status(refs())?.name == "To do" && state.resourceName(refs()) == nil)
    }
}
