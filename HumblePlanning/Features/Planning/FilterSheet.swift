import SwiftUI
import HumbleCore

/// Who and what the planning shows. Edits a copy: closing without applying changes nothing.
struct FilterSheet: View {
    let model: PlanningModel
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var filter: PlanningFilter
    @State private var picker: Picker?

    enum Picker: Identifiable {
        case people, teams, projects, statuses
        var id: Self { self }
    }

    init(model: PlanningModel) {
        self.model = model
        _filter = State(initialValue: model.filter)
    }

    private var references: References { app.repository.references }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: .filterPeople)) {
                    SwiftUI.Picker(String(localized: .filterPeople), selection: Binding(get: { filter.people }, set: { choosePeople($0) })) {
                        Text(.filterMe).tag(PeopleFilter.mine)
                        Text(.filterEveryone).tag(PeopleFilter.all)
                        Text(.filterPick).tag(PeopleFilter.specific)
                    }
                    .pickerStyle(.segmented)
                    if filter.people == .specific {
                        choice(String(localized: .nPeople(filter.userIds.count))) { picker = .people }
                    }
                }
                if !references.teams.isEmpty {
                    specific(title: String(localized: .filterTeams), all: String(localized: .filterAllTeams),
                             isOn: \.specificTeams, count: String(localized: .nTeams(filter.teamIds.count)), picker: .teams)
                }
                specific(title: String(localized: .filterProjects), all: String(localized: .filterAllProjects),
                         isOn: \.specificProjects, count: String(localized: .nProjects(filter.projectIds.count)), picker: .projects)
                specific(title: String(localized: .filterStatuses), all: String(localized: .filterAllStatuses),
                         isOn: \.specificStatuses, count: String(localized: .nStatuses(filter.statusIds.count)), picker: .statuses)
            }
            .navigationTitle(String(localized: .filters))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(String(localized: .reset)) { filter = PlanningFilter() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .apply), role: .confirm) {
                        model.setFilter(filter)
                        dismiss()
                    }
                }
            }
            .sheet(item: $picker) { sheet($0) }
        }
    }

    private func choosePeople(_ people: PeopleFilter) {
        filter = filter.choosingPeople(people, me: model.me)
        if people == .specific { picker = .people }
    }

    private func specific(title: String, all: String, isOn: WritableKeyPath<PlanningFilter, Bool>, count: String, picker: Picker) -> some View {
        Section(title) {
            Toggle(all, isOn: Binding(get: { !filter[keyPath: isOn] }, set: { everything in
                filter[keyPath: isOn] = !everything
                if !everything { self.picker = picker }
            }))
            if filter[keyPath: isOn] {
                choice(count) { self.picker = picker }
            }
        }
    }

    private func choice(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func sheet(_ picker: Picker) -> some View {
        switch picker {
        case .people:
            PickerSheet(title: String(localized: .filterPeople), items: references.users.map { user in
                PickerItem(id: user.id, label: user.displayName, color: user.color,
                           group: references.teams.first { $0.id == user.teamId }?.name)
            }, selected: filter.userIds, multiple: true) { filter.userIds = $0 }
        case .teams:
            PickerSheet(title: String(localized: .filterTeams), items: references.teams.map { PickerItem(id: $0.id, label: $0.name, color: $0.color) },
                        selected: filter.teamIds, multiple: true) { filter.teamIds = $0 }
        case .projects:
            PickerSheet(title: String(localized: .filterProjects), items: references.projects.map {
                PickerItem(id: $0.id, label: $0.label, color: $0.color, group: $0.group?.name)
            }, selected: filter.projectIds, multiple: true) { filter.projectIds = $0 }
        case .statuses:
            PickerSheet(title: String(localized: .filterStatuses), items: references.statuses.map { PickerItem(id: $0.id, label: $0.name, color: $0.color) },
                        selected: filter.statusIds, multiple: true) { filter.statusIds = $0 }
        }
    }
}
