import Foundation

/// What survives the app being ended while the form is open: the form, the form it started from, and the id
/// of a task already created.
public struct TaskFormDraft: Codable, Sendable, Equatable {
    public var form: TaskForm
    public var initial: TaskForm
    public var createdId: String?

    public init(form: TaskForm, initial: TaskForm, createdId: String? = nil) {
        self.form = form
        self.initial = initial
        self.createdId = createdId
    }
}

/// The requests of a save, sent by the caller in this order.
public struct TaskSave: Sendable, Equatable {
    /// nil: `POST /api/tasks`; else `PUT /api/tasks/{taskId}` (with `?applyToAll=true` when `applyToAll`).
    public let taskId: String?
    public let payload: TaskPayload
    public let applyToAll: Bool
    /// Then `POST /api/tasks/{id of the saved task}/repeat`, when not nil: the series is rebuilt only when
    /// its rule changed or when there is none yet.
    public let repeatRequest: RepeatRequest?
}

/// The task form without its screen: create, edit or duplicate a task. The caller loads the task
/// (`GET /api/tasks/{id}`, never from the offline copy), sends the requests of `prepareSave` and reports back.
public struct TaskFormState: Sendable {
    public enum Kind: Sendable, Equatable {
        /// `date`: the planning's selected day (today when nil); `userId`: the grid row it was opened from.
        case create(date: String? = nil, userId: String? = nil)
        case edit(id: String)
        case duplicate(of: String)
    }

    public let kind: Kind
    public var form: TaskForm
    /// The form as loaded: changes are measured against it.
    public private(set) var initial: TaskForm
    /// The task being edited; nil for a new task or a copy.
    public private(set) var existing: PlanningTask?
    /// A new task already sent, if its recurrence then failed: saving again updates it instead of creating another.
    public private(set) var createdId: String?
    public private(set) var loading: Bool
    public private(set) var loadFailed = false
    public private(set) var saving = false
    public private(set) var saved = false
    public var validationError: FormError?

    private let restored: TaskFormDraft?

    public init(kind: Kind, restored: TaskFormDraft? = nil) {
        self.kind = kind
        self.restored = restored
        form = restored?.form ?? TaskForm()
        initial = restored?.initial ?? TaskForm()
        createdId = restored?.createdId
        loading = kind.sourceId != nil
    }

    public var isNew: Bool { if case .edit = kind { false } else { true } }
    public var isCopy: Bool { if case .duplicate = kind { true } else { false } }
    /// Id to load before showing the form: the edited task or the one copied.
    public var sourceId: String? { kind.sourceId }
    /// Leaving asks for confirmation. A copy is changed from the start: saving it creates a task.
    public var dirty: Bool { form != initial }
    public var draft: TaskFormDraft { TaskFormDraft(form: form, initial: initial, createdId: createdId) }
    /// The Save button is enabled.
    public var canSave: Bool { !saving && !loading && !loadFailed }

    // MARK: Loading

    /// The task to edit or to copy is there. A copy keeps only the people the user may assign, is never locked
    /// nor a series, and starts from an empty form so that it counts as changed.
    public mutating func loaded(_ task: PlanningTask, references: References) {
        if let restored {
            form = restored.form
        } else {
            form = TaskForm(task: task, references: references)
            if isCopy {
                form.locked = false
                form.applyToAll = false
                form.repeats = false
                form.userIds = Access(references).assignableAmong(form.userIds, all: references.users)
            }
        }
        initial = restored?.initial ?? (isCopy ? TaskForm() : form)
        existing = isCopy ? nil : task
        loading = false
    }

    /// The task could not be read (offline included): the screen offers to go back.
    public mutating func loadingFailed() {
        loading = false
        loadFailed = true
    }

    /// New task: defaults filled in as the reference data arrives (call it on each change), without making the
    /// form changed if the user has not touched it. Nothing is filled in a restored form.
    public mutating func referencesChanged(_ references: References, today: CalendarDay = .today()) {
        guard case let .create(date, userId) = kind, restored == nil else { return }
        let untouched = !dirty
        if form.statusId.isEmpty {
            form.statusId = (references.statuses.first { $0.isDefault } ?? references.statuses.first)?.id ?? ""
        }
        if form.userIds.isEmpty {
            let assignable = Set(Access(references).assignableUsers(references.users).map(\.id))
            form.userIds = [userId ?? references.user.id].filter(assignable.contains)
        }
        if form.startDate.isEmpty { form.startDate = date ?? today.iso }
        if untouched { initial = form }
    }

    // MARK: Editing

    /// A change of the form clears the validation message (the caller clears its request error too).
    public mutating func update(_ change: (inout TaskForm) -> Void) {
        change(&form)
        validationError = nil
    }

    // MARK: Saving

    /// The requests to send, or nil with `validationError` set when the form breaks a rule.
    public mutating func prepareSave(references: References) -> TaskSave? {
        if let error = form.validationError {
            validationError = error
            return nil
        }
        let access = Access(references)
        let placeTextChanged = existing.map {
            form.placeText.trimmingCharacters(in: .whitespacesAndNewlines)
                != ($0.placeText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? false
        let payload = form.payload(references: references, canLock: existing.map(access.canLock) ?? false,
                                   placeTextChanged: placeTextChanged)
        let ruleChanged = (existing.map { !$0.isSeriesRoot } ?? true) || !form.hasSameRule(as: initial)
        saving = true
        return TaskSave(taskId: editedId ?? createdId, payload: payload, applyToAll: form.applyToAll,
                        repeatRequest: form.repeats && ruleChanged ? form.repeatRequest : nil)
    }

    /// The create or update answered with the task `id`: kept for a retry when the task is new.
    public mutating func taskSaved(id: String) {
        if editedId == nil && createdId == nil { createdId = id }
    }

    /// Every request succeeded: the screen closes.
    public mutating func saveSucceeded() {
        saving = false
        saved = true
    }

    /// A request failed: the form stays as it is, ready for another try.
    public mutating func saveFailed() { saving = false }

    // MARK: What the screen shows

    /// People may be changed: a new task, or one the user may assign (not locked).
    public func canChangePeople(_ access: Access) -> Bool { existing.map(access.canAssign) ?? true }

    /// The people offered: those the user may assign, then those already on the task outside that list.
    public func peopleChoices(_ references: References) -> [User] {
        let assignable = Access(references).assignableUsers(references.users)
        let ids = Set(assignable.map(\.id))
        return assignable + (existing?.users ?? []).filter { !ids.contains($0.id) }
    }

    /// Name shown for the people: the person when there is one (nil = show the count).
    public func singlePersonName(_ references: References) -> String? {
        guard form.userIds.count == 1, let id = form.userIds.first else { return nil }
        return (references.person(id) ?? existing?.users.first { $0.id == id })?.displayName
    }

    /// The project shown, also when archived (then only on the task).
    public func project(_ references: References) -> Project? {
        references.project(form.projectId) ?? existing?.project.flatMap { $0.id == form.projectId ? $0 : nil }
    }

    public func status(_ references: References) -> TaskStatus? {
        references.status(form.statusId) ?? existing?.status.flatMap { $0.id == form.statusId ? $0 : nil }
    }

    public func resourceName(_ references: References) -> String? {
        references.resource(form.resourceId)?.name ?? existing?.resource.flatMap { $0.id == form.resourceId ? $0.name : nil }
    }

    /// The lock switch: when editing a task the user may lock, never on a new task or a copy.
    public func showsLock(_ access: Access) -> Bool { existing.map(access.canLock) ?? false }

    /// "Apply to the whole series", on any task of a series.
    public var showsApplyToAll: Bool { existing?.isRecurring == true }

    /// The recurrence section: new task, copy, or the root of a series (not a plain task nor an occurrence).
    public var showsRecurrence: Bool { existing.map(\.isSeriesRoot) ?? true }

    /// The repeat switch can be changed only on a new task or a copy: a series stays a series.
    public var canChangeRepeat: Bool { existing == nil }

    private var editedId: String? { if case let .edit(id) = kind { id } else { nil } }
}

extension TaskFormState.Kind {
    var sourceId: String? {
        switch self {
        case .create: nil
        case let .edit(id): id
        case let .duplicate(id): id
        }
    }
}
