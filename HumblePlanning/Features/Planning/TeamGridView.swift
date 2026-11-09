import SwiftUI
import HumbleCore

/// The team grid: one row per person, grouped by team, one column per day of the whole weeks of the
/// selected month. Above it, the months and the width of the days; the grid itself is drawn by UIKit
/// (`TeamGridCanvas`).
struct TeamGridView: View {
    let model: PlanningModel
    let onOpenTask: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            GridToolbar(model: model)
            if model.filter.people == .mine { OnlyYouStrip(model: model) }
            GridArea(model: model, onOpenTask: onOpenTask)
        }
    }
}

/// ‹ › months, the pinch hint and the width menu.
private struct GridToolbar: View {
    let model: PlanningModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button(String(localized: .gridPreviousMonth), systemImage: "chevron.left") { model.moveMonth(-1) }
                Button(String(localized: .gridNextMonth), systemImage: "chevron.right") { model.moveMonth(1) }
                // A hint only: it gives its room to the buttons with the accessibility sizes
                if typeSize.isAccessibilitySize {
                    Spacer()
                } else {
                    Text(.gridPinchHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
                Menu {
                    Picker(String(localized: .gridWidth), selection: width) {
                        Text(.gridWidthCompact).tag(GridMetrics.compactCellWidth)
                        Text(.gridWidthNormal).tag(GridMetrics.defaultCellWidth)
                        Text(.gridWidthWide).tag(GridMetrics.wideCellWidth)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(String(localized: .gridWidth), systemImage: "arrow.left.and.right")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// The nearest preset is ticked; choosing one sets and saves it.
    private var width: Binding<Double> {
        Binding(get: { GridMetrics.nearestPreset(to: model.cellWidth) }, set: { model.setCellWidth($0) })
    }
}

/// The default filter shows only the user's row: say so, and offer everyone.
private struct OnlyYouStrip: View {
    let model: PlanningModel

    var body: some View {
        AdaptiveStack(spacing: 8) {
            Text(.gridOnlyYou)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: .gridShowEveryone)) {
                model.setFilter(model.filter.choosingPeople(.all, me: model.me))
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .padding(.horizontal, 16)
    }
}

/// The grid, or what to do when nobody matches the filters.
private struct GridArea: View {
    let model: PlanningModel
    let onOpenTask: (String) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @AppStorage("card_title") private var cardTitle = CardTitleMode.project.rawValue
    @State private var bottomInset = 0.0

    var body: some View {
        let content = content
        TeamGridRepresentable(
            content: content,
            cellWidth: model.cellWidth,
            focus: GridFocus(selected: model.selected, period: content.period, request: model.focusRequest),
            bottomInset: bottomInset,
            actions: actions
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .onGeometryChange(for: Double.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .overlay {
            if content.groups.isEmpty, model.loaded?.contains(content.period.lowerBound) == true, !model.loading {
                EmptyState(systemImage: "person.3", title: String(localized: .gridNobody),
                           subtitle: String(localized: .gridNobodyHelp))
                    .padding(.top, GridMetrics.dayHeaderHeight)
            }
        }
    }

    private var content: GridContent {
        let references = model.references
        let period = model.gridRange
        let people = GridLayout.people(references.users, filter: model.filter, me: model.me, teams: references.teams)
        return GridContent(
            period: period,
            columns: GridLayout.columns(period, today: .today(), holidays: references.holidays),
            groups: GridLayout.groups(people, teams: references.teams, tasks: model.tasks, filter: model.filter,
                                      start: period.lowerBound, days: period.count),
            collapsed: model.collapsedTeams,
            creatable: GridLayout.creatableUserIds(app.repository.access, users: references.users),
            me: model.me,
            references: references,
            titleMode: CardTitleMode(rawValue: cardTitle) ?? .project,
            locale: locale
        )
    }

    private var actions: GridActions {
        let model = model, app = app
        return GridActions(
            openTask: onOpenTask,
            create: { day, userId in app.formRoute = .create(date: day, userId: userId) },
            toggleTeam: { key in
                if model.collapsedTeams.contains(key) { model.collapsedTeams.remove(key) } else { model.collapsedTeams.insert(key) }
            },
            commitWidth: { model.setCellWidth($0) },
            refresh: { await model.refresh() },
            avatar: { user in
                guard let url = avatarURL(server: app.repository.session?.serverURL ?? "", image: user.image) else { return nil }
                return await app.images.image(url, repository: app.repository)
            }
        )
    }
}

/// `TeamGridCanvas` in SwiftUI.
private struct TeamGridRepresentable: UIViewRepresentable {
    let content: GridContent
    let cellWidth: Double
    let focus: GridFocus
    let bottomInset: Double
    let actions: GridActions

    func makeUIView(context: Context) -> TeamGridCanvas { TeamGridCanvas() }

    func updateUIView(_ canvas: TeamGridCanvas, context: Context) {
        canvas.actions = actions
        canvas.bottomInset = bottomInset
        canvas.update(content: content, cellWidth: cellWidth, focus: focus)
    }
}
