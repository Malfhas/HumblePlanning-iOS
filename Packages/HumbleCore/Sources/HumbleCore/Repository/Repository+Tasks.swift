import Foundation

extension Repository {
    /// Tasks of a period: one period is kept and brought up to date with the changes since its last
    /// read; without network, my tasks from the offline copy.
    public func tasks(in range: DayRange) async throws -> TasksResult {
        try await tasks(start: range.lowerBound.iso, end: range.upperBound.iso)
    }

    func tasks(start: String, end: String) async throws -> TasksResult {
        do {
            return TasksResult(tasks: try await syncRange(start: start, end: end), offlineSince: nil, isOffline: false)
        } catch let error as APIError where error.isNetwork {
            guard let cached = files.read([PlanningTask].self, .tasks) else { throw error }
            return TasksResult(tasks: cached.filter { $0.startDate <= end && $0.lastDate >= start },
                               offlineSince: preferences.offlineDate, isOffline: true)
        }
    }

    private func syncRange(start: String, end: String) async throws -> [PlanningTask] {
        let known = taskRange.flatMap { $0.start == start && $0.end == end ? $0 : nil }
        let sync = try await call { try await $0.syncTasks(start: start, end: end, since: known?.serverTime) }
        var merged = known?.tasks ?? [:]
        for task in sync.changed { merged[task.id] = task }
        let ids = Set(sync.ids)
        merged = merged.filter { ids.contains($0.key) }
        taskRange = (start, end, sync.serverTime, merged)
        return Array(merged.values)
    }

    /// The task, or its offline copy without network.
    public func task(_ id: String) async throws -> PlanningTask {
        do {
            return try await call { try await $0.task(id) }
        } catch let error as APIError where error.isNetwork {
            guard let cached = files.read([PlanningTask].self, .tasks)?.first(where: { $0.id == id }) else { throw error }
            return cached
        }
    }

    /// The whole task, for the form: never the offline copy, which lacks fields.
    public func taskToEdit(_ id: String) async throws -> PlanningTask {
        try await call { try await $0.task(id) }
    }

    /// My tasks from 30 days ago to 90 days ahead, kept encrypted for offline use.
    public func refreshOfflineData(today: CalendarDay = .today()) async {
        let me = userId
        let range = PlanningPeriod.offlineCopy(today: today)
        guard let sync = try? await call({ try await $0.syncTasks(start: range.lowerBound.iso, end: range.upperBound.iso, since: nil) })
        else { return }
        try? files.write(sync.changed.filter { $0.userIds.contains(me) }, .tasks)
        preferences.offlineDate = Date()
    }

    // MARK: Writes (each one reloads the screens)

    public func createTask(_ payload: TaskPayload) async throws -> PlanningTask {
        let task = try await call { try await $0.createTask(payload) }
        tasksDidChange()
        return task
    }

    public func updateTask(_ id: String, _ payload: TaskPayload, applyToAll: Bool) async throws -> PlanningTask {
        let task = try await call { try await $0.updateTask(id, payload, applyToAll: applyToAll) }
        tasksDidChange()
        return task
    }

    public func repeatTask(_ id: String, _ rule: RepeatRequest) async throws {
        try await call { try await $0.repeatTask(id, rule) }
        tasksDidChange()
    }

    public func deleteTask(_ id: String, scope: DeleteScope) async throws {
        try await call { try await $0.deleteTask(id, scope: scope) }
        tasksDidChange()
    }

    public func removeUser(_ userId: String, from taskId: String) async throws {
        try await call { try await $0.removeUser(userId, from: taskId) }
        tasksDidChange()
    }

    public func uploadFile(taskId: String, file: URL, name: String, contentType: String) async throws {
        try await call { try await $0.uploadFile(taskId: taskId, file: file, name: name, contentType: contentType) }
        tasksDidChange()
    }

    public func deleteFile(taskId: String, fileId: String) async throws {
        try await call { try await $0.deleteFile(taskId: taskId, fileId: fileId) }
        tasksDidChange()
    }

    /// Downloads an attachment into the cache of attachments (emptied at sign-out).
    public func download(_ file: TaskFile, taskId: String) async throws -> URL {
        let folder = Self.attachmentsDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: safeFileName(file.originalName.isEmpty ? file.name : file.originalName, fallback: file.id))
        try await call { try await $0.downloadFile(taskId: taskId, name: file.name, to: destination) }
        return destination
    }

    public static var attachmentsDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "attachments", directoryHint: .isDirectory)
    }
}
