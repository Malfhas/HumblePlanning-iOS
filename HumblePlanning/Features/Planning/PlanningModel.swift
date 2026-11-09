import SwiftUI
import HumbleCore

/// The state of the planning: view, selected day, filter, the tasks of the period loaded, and the
/// width of a day on the team grid. Kept for the life of the main screen.
@MainActor
@Observable
final class PlanningModel {
    private(set) var mode: PlanningMode
    private(set) var selected = CalendarDay.today()
    private(set) var filter: PlanningFilter
    private(set) var tasks: [PlanningTask] = []
    /// The period actually loaded.
    private(set) var loaded: DayRange?
    private(set) var loading = false
    var refreshing = false
    private(set) var error: String?
    private(set) var offlineSince: Date?
    private(set) var isOffline = false
    /// Width of a day on the grid (points).
    private(set) var cellWidth: Double
    /// Bumped by "Today": the grid scrolls back even when the day did not change.
    private(set) var focusRequest = 0
    /// Teams folded on the grid (team id, or "none").
    var collapsedTeams: Set<String> = []

    private let repository: Repository
    private var loadTask: Task<Void, Never>?

    init(repository: Repository) {
        self.repository = repository
        let preferences = repository.preferences
        mode = preferences.planningView.flatMap(PlanningMode.init(rawValue:)) ?? .day
        filter = preferences.planningFilter.flatMap { try? JSONDecoder().decode(PlanningFilter.self, from: $0) } ?? PlanningFilter()
        cellWidth = GridMetrics.clampedCellWidth(preferences.gridCellWidth ?? GridMetrics.defaultCellWidth)
    }

    var me: String { repository.userId }
    var references: References { repository.references }

    /// The tasks of the lists (Day, Week, Month), filtered.
    var agenda: PlanningAgenda {
        PlanningAgenda(tasks: tasks, filter: filter, me: me, teams: references.teams, loaded: loaded)
    }

    var gridRange: DayRange { PlanningPeriod.grid(of: selected) }

    // MARK: Actions

    func start() {
        refreshBackground()
        reload(silent: false)
    }

    func setMode(_ new: PlanningMode) {
        guard new != mode else { return }
        mode = new
        repository.preferences.planningView = new.rawValue
        ensureLoaded()
    }

    func select(_ day: CalendarDay) {
        guard day != selected else { return }
        selected = day
        ensureLoaded()
    }

    func goToday() {
        focusRequest += 1
        select(.today())
    }

    func moveMonth(_ months: Int) {
        select(selected.firstOfMonth.adding(months: months))
    }

    func setFilter(_ new: PlanningFilter) {
        filter = new
        repository.preferences.planningFilter = try? JSONEncoder().encode(new)
    }

    func setCellWidth(_ width: Double, save: Bool = true) {
        cellWidth = GridMetrics.clampedCellWidth(width)
        if save { repository.preferences.gridCellWidth = cellWidth }
    }

    /// Pull to refresh: the tasks, and in the background the reference data and the offline copy.
    func refresh() async {
        refreshing = true
        refreshBackground()
        reload(silent: true)
        await loadTask?.value
    }

    func reload(silent: Bool) {
        load(PlanningPeriod.loaded(for: mode, selected: selected), silent: silent)
    }

    private func ensureLoaded() {
        if let range = PlanningPeriod.toLoad(for: mode, selected: selected, loaded: loaded) {
            load(range, silent: false)
        }
    }

    private func refreshBackground() {
        Task {
            try? await repository.loadReferences()
            await repository.refreshOfflineData()
        }
    }

    private func load(_ range: DayRange, silent: Bool) {
        loadTask?.cancel()
        loading = !silent
        error = nil
        loadTask = Task {
            do {
                let result = try await repository.tasks(in: range)
                guard !Task.isCancelled else { return }
                tasks = result.tasks
                offlineSince = result.offlineSince
                isOffline = result.isOffline
                loaded = range
            } catch {
                guard !Task.isCancelled else { return }
                self.error = screenMessage(error)
            }
            loading = false
            refreshing = false
        }
    }
}
