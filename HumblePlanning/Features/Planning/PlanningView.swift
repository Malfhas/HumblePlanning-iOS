import SwiftUI
import HumbleCore

/// The schedule in four views: day, week, month and the team grid.
struct PlanningView: View {
    let model: PlanningModel
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var choosingDate = false
    @State private var filtering = false
    @State private var openedTask: TaskRoute?
    @State private var started = false

    var body: some View {
        let agenda = model.agenda
        content(agenda)
            .safeAreaBar(edge: .top) { topBar }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if sizeClass == .compact { toolbar } }
            .navigationDestination(item: $openedTask) { TaskDetailView(id: $0.id) }
            .sheet(isPresented: $choosingDate) { DateChooser(day: model.selected) { model.select($0) } }
            .sheet(isPresented: $filtering) { FilterSheet(model: model) }
            .onAppear {
                if !started {
                    started = true
                    model.start()
                } else {
                    model.reload(silent: true)
                }
            }
            .onChange(of: app.repository.tasksChanged) { model.reload(silent: true) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { model.reload(silent: true) } }
    }

    @ViewBuilder
    private func content(_ agenda: PlanningAgenda) -> some View {
        switch model.mode {
        case .day: DayPlanning(model: model, agenda: agenda)
        case .week: WeekPlanning(model: model, agenda: agenda)
        case .month: MonthPlanning(model: model, agenda: agenda)
        case .grid: TeamGridView(model: model) { openedTask = TaskRoute(id: $0) }
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            // On a large screen the tab bar takes the top: the controls of the planning come down here
            if sizeClass != .compact {
                HStack(spacing: 10) {
                    monthButton.buttonStyle(.glass).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Spacer()
                    Button(String(localized: .today)) { model.goToday() }
                        .buttonStyle(.glass)
                        .keyboardShortcut("t", modifiers: .command)
                    if app.repository.access.canCreateTask { newTaskButton }
                }
            }
            HStack(spacing: 8) {
                Picker(String(localized: .chooseDate), selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                    Text(.viewDay).tag(PlanningMode.day)
                    Text(.viewWeek).tag(PlanningMode.week)
                    Text(.viewMonth).tag(PlanningMode.month)
                    Text(.viewGrid).tag(PlanningMode.grid)
                }
                .pickerStyle(.segmented)
                Button { filtering = true } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.body.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .overlay(alignment: .topTrailing) {
                            if model.filter.activeCount > 0 {
                                Text("\(model.filter.activeCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.accentColor, in: .circle)
                                    .offset(x: 10, y: -10)
                            }
                        }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                // Same size as the segmented control next to it, which keeps its size too: touch and hold shows it large
                .dynamicTypeSize(...DynamicTypeSize.large)
                .accessibilityLabel(String(localized: .filters))
                .accessibilityValue(model.filter.activeCount > 0 ? "\(model.filter.activeCount)" : "")
                .accessibilityShowsLargeContentViewer()
            }
            if model.isOffline || app.repository.offline {
                OfflineBanner(since: model.offlineSince)
            } else if let error = model.error {
                Banner(text: error, tone: .error)
            }
            if model.loading && !model.refreshing {
                ProgressView().progressViewStyle(.linear).frame(height: 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.default, value: model.error)
    }

    private var monthButton: some View {
        Button { choosingDate = true } label: {
            HStack(spacing: 4) {
                Text(PlanningFormat.monthLabel(model.selected, locale: locale))
                    .font(.headline)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .padding(.horizontal, 4)
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: .chooseDate))
        .accessibilityValue(PlanningFormat.monthLabel(model.selected, locale: locale))
        .accessibilityShowsLargeContentViewer { Label(PlanningFormat.monthLabel(model.selected, locale: locale), systemImage: "calendar") }
    }

    private var newTaskButton: some View {
        Button(String(localized: .newTask), systemImage: "plus") {
            app.formRoute = .create(date: model.selected, userId: nil)
        }
        .buttonStyle(.glassProminent)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Like the titles and buttons of a navigation bar, the month keeps its size: Today and New task stay in the bar
        ToolbarItem(placement: .topBarLeading) { monthButton.dynamicTypeSize(...DynamicTypeSize.large) }
        ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: .today)) { model.goToday() }
                .keyboardShortcut("t", modifiers: .command)
        }
        if app.repository.access.canCreateTask {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) { newTaskButton }
        }
    }
}

/// A date chooser in a sheet.
private struct DateChooser: View {
    let onChoose: (CalendarDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(day: CalendarDay, onChoose: @escaping (CalendarDay) -> Void) {
        self.onChoose = onChoose
        _date = State(initialValue: day.date())
    }

    var body: some View {
        NavigationStack {
            DatePicker(String(localized: .chooseDate), selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle(String(localized: .chooseDate))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                            onChoose(CalendarDay(date))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Day

private struct DayPlanning: View {
    let model: PlanningModel
    let agenda: PlanningAgenda
    @Environment(\.locale) private var locale
    @State private var dayPage: Int?
    @State private var weekPage: Int?
    private let anchor = CalendarDay.today()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(-520...520, id: \.self) { week in
                        WeekStrip(monday: anchor.monday.adding(days: week * 7), model: model, agenda: agenda)
                            .containerRelativeFrame(.horizontal)
                            .id(week)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $weekPage)
            .scrollIndicators(.hidden)
            .frame(height: 76)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(-3650...3650, id: \.self) { offset in
                        DayPage(day: anchor.adding(days: offset), model: model, agenda: agenda)
                            .containerRelativeFrame(.horizontal)
                            .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $dayPage)
            .scrollIndicators(.hidden)
        }
        .onAppear { follow(model.selected, animated: false) }
        .onChange(of: model.selected) { _, day in follow(day, animated: true) }
        .onChange(of: dayPage) { _, page in
            guard let page else { return }
            let day = anchor.adding(days: page)
            if day != model.selected { model.select(day) }
        }
        .onChange(of: weekPage) { _, page in
            guard let page else { return }
            let monday = anchor.monday.adding(days: page * 7)
            if monday != model.selected.monday { model.select(model.selected.sameWeekday(inWeekOf: monday)) }
        }
    }

    private func follow(_ day: CalendarDay, animated: Bool) {
        let page = anchor.days(to: day)
        let week = anchor.monday.days(to: day.monday) / 7
        let jump = abs((dayPage ?? page) - page) > 2 || !animated
        withAnimation(jump ? nil : .default) {
            if dayPage != page { dayPage = page }
            if weekPage != week { weekPage = week }
        }
    }
}

/// Seven days to tap, with a dot per project of the day.
private struct WeekStrip: View {
    let monday: CalendarDay
    let model: PlanningModel
    let agenda: PlanningAgenda
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                let day = monday.adding(days: index)
                let selected = day == model.selected
                let today = day == .today()
                Button { model.select(day) } label: {
                    VStack(spacing: 3) {
                        Text(PlanningFormat.shortWeekday(day.weekday, locale: locale))
                            .font(.caption2)
                            .foregroundStyle(selected ? Color.white : .secondary)
                        Text("\(day.day)")
                            .font(.headline.weight(today || selected ? .bold : .medium))
                            .foregroundStyle(selected ? Color.white : today ? Color.accentColor : .primary)
                        HStack(spacing: 2) {
                            ForEach(0..<min(agenda.stripDots(on: day), 3), id: \.self) { _ in
                                Circle().frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 5)
                        .foregroundStyle(selected ? Color.white : .secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(selected ? Color.accentColor : .clear, in: .rect(cornerRadius: 14))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PlanningFormat.longLabel(day, locale: locale))
                .accessibilityValue(agenda.spokenSummary(of: day, references: model.references))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(.horizontal, 12)
        // Seven days across the screen: past this size the strip keeps its size, touch and hold shows a day large
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The tasks of one day.
private struct DayPage: View {
    let day: CalendarDay
    let model: PlanningModel
    let agenda: PlanningAgenda
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale

    var body: some View {
        let tasks = agenda.tasks(on: day)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                AdaptiveStack(alignment: .firstTextBaseline) {
                    Text(PlanningFormat.longLabel(day, locale: locale))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    if !tasks.isEmpty {
                        Text(.nTasks(tasks.count)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                if let holiday = app.repository.references.holiday(on: day) { HolidayLabel(holiday: holiday) }
                if tasks.isEmpty && agenda.covers(day) && !model.loading {
                    EmptyState(systemImage: "calendar.badge.checkmark", title: String(localized: .nothingPlanned),
                               subtitle: String(localized: .nothingPlannedHelp))
                }
                ForEach(tasks) { task in
                    NavigationLink(value: TaskRoute(id: task.id)) {
                        TaskCard(task: task, day: day, showsPeople: model.filter.showsPeople)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await model.refresh() }
    }
}

// MARK: - Week

private struct WeekPlanning: View {
    let model: PlanningModel
    let agenda: PlanningAgenda
    @State private var page: Int?
    private let anchor = CalendarDay.today().monday

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(-520...520, id: \.self) { week in
                    WeekPage(monday: anchor.adding(days: week * 7), model: model, agenda: agenda)
                        .containerRelativeFrame(.horizontal)
                        .id(week)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .onAppear { page = anchor.days(to: model.selected.monday) / 7 }
        .onChange(of: model.selected) { _, day in
            let target = anchor.days(to: day.monday) / 7
            if page != target { withAnimation(abs((page ?? target) - target) > 2 ? nil : .default) { page = target } }
        }
        .onChange(of: page) { _, page in
            guard let page else { return }
            let monday = anchor.adding(days: page * 7)
            if monday != model.selected.monday { model.select(model.selected.sameWeekday(inWeekOf: monday)) }
        }
    }
}

private struct WeekPage: View {
    let monday: CalendarDay
    let model: PlanningModel
    let agenda: PlanningAgenda
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The circle of the day number grows with the text.
    @ScaledMetric(relativeTo: .headline) private var circle: CGFloat = 40

    /// The cards stand back from the day numbers, except with the accessibility sizes where they need the width.
    private var indent: CGFloat { typeSize.isAccessibilitySize ? 0 : 52 }

    var body: some View {
        let references = app.repository.references
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text(.weekOf(PlanningFormat.longLabel(monday, locale: locale, capitalized: false), monday.isoWeek))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                ForEach(agenda.weekDays(of: monday, references: references), id: \.self) { day in
                    // One block per day: a task over several days shows under each of them
                    VStack(alignment: .leading, spacing: 8) {
                        let tasks = agenda.tasks(on: day)
                        dayHeader(day, count: tasks.count, holiday: references.holiday(on: day))
                        if tasks.isEmpty {
                            Text(agenda.covers(day) ? String(localized: .nothingPlanned) : String(localized: .loading))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, indent)
                                .padding(.bottom, 8)
                        } else {
                            ForEach(tasks) { task in
                                NavigationLink(value: TaskRoute(id: task.id)) {
                                    TaskCard(task: task, day: day, compact: true, showsPeople: model.filter.showsPeople)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, indent)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await model.refresh() }
    }

    private func dayHeader(_ day: CalendarDay, count: Int, holiday: Holiday?) -> some View {
        let today = day == .today()
        let selected = day == model.selected
        return Button { model.select(day) } label: {
            HStack(spacing: 12) {
                Text("\(day.day)")
                    .font(.headline)
                    .foregroundStyle(today ? Color.white : .primary)
                    .frame(width: circle, height: circle)
                    .background(today ? Color.accentColor : selected ? Color(.tertiarySystemFill) : .clear, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlanningFormat.weekdayName(day, locale: locale)).font(.subheadline.weight(.semibold))
                    if let holiday { HolidayLabel(holiday: holiday) }
                    if count > 0 && typeSize.isAccessibilitySize { taskCount(count) }
                }
                Spacer(minLength: 0)
                if count > 0 && !typeSize.isAccessibilitySize { taskCount(count) }
            }
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlanningFormat.longLabel(day, locale: locale))
        .accessibilityValue(agenda.spokenSummary(of: day, references: app.repository.references))
        .accessibilityAddTraits(selected ? [.isHeader, .isSelected] : .isHeader)
    }

    private func taskCount(_ count: Int) -> some View {
        Text(.nTasks(count)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }
}

// MARK: - Month

private struct MonthPlanning: View {
    let model: PlanningModel
    let agenda: PlanningAgenda
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @State private var page: Int?
    private let anchor = CalendarDay.today().firstOfMonth

    var body: some View {
        let tasks = agenda.tasks(on: model.selected)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(PlanningFormat.narrowWeekday(weekday, locale: locale))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(-120...120, id: \.self) { month in
                            MonthGrid(first: anchor.adding(months: month), model: model, agenda: agenda)
                                .containerRelativeFrame(.horizontal)
                                .id(month)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                VStack(alignment: .leading, spacing: 10) {
                    Text(PlanningFormat.longLabel(model.selected, locale: locale))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let holiday = app.repository.references.holiday(on: model.selected) { HolidayLabel(holiday: holiday) }
                    if tasks.isEmpty && agenda.covers(model.selected) && !model.loading {
                        Text(.nothingPlanned).foregroundStyle(.secondary)
                    }
                    ForEach(tasks) { task in
                        NavigationLink(value: TaskRoute(id: task.id)) {
                            TaskCard(task: task, day: model.selected, showsPeople: model.filter.showsPeople)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .refreshable { await model.refresh() }
        .onAppear { page = anchor.months(to: model.selected.firstOfMonth) }
        .onChange(of: model.selected) { _, day in
            let target = anchor.months(to: day.firstOfMonth)
            if page != target { withAnimation(abs((page ?? target) - target) > 2 ? nil : .default) { page = target } }
        }
        .onChange(of: page) { _, page in
            guard let page else { return }
            let first = anchor.adding(months: page)
            if first != model.selected.firstOfMonth { model.select(model.selected.sameDay(inMonthOf: first)) }
        }
    }
}

/// Six weeks of a month, with the colours of the projects of each day.
private struct MonthGrid: View {
    let first: CalendarDay
    let model: PlanningModel
    let agenda: PlanningAgenda
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale

    var body: some View {
        let start = first.monday
        let references = app.repository.references
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        cell(start.adding(days: row * 7 + column), references: references)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func cell(_ day: CalendarDay, references: References) -> some View {
        let selected = day == model.selected
        let today = day == .today()
        let holiday = references.holiday(on: day)
        let dots = agenda.monthDots(on: day, references: references)
        return Button { model.select(day) } label: {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(.subheadline.weight(today || selected ? .bold : .regular))
                    .foregroundStyle(selected ? Color.white : today ? Color.accentColor : day.month == first.month ? .primary : .secondary)
                HStack(spacing: 2) {
                    ForEach(Array(dots.colors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color.map(Color.init) ?? Color(.separator)).frame(width: 6, height: 6)
                    }
                    if dots.more > 0 {
                        Text("+\(dots.more)").font(.caption2).foregroundStyle(selected ? Color.white : .secondary)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
            .padding(.top, 6)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor : holiday.map { Color($0.tint).opacity(0.19) } ?? .clear)
            }
            .overlay {
                if today && !selected { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            }
            .padding(2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlanningFormat.longLabel(day, locale: locale))
        .accessibilityValue(agenda.spokenSummary(of: day, references: references))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
        // Seven days across the screen: past this size the month keeps its size, touch and hold shows a day large
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

extension PlanningAgenda {
    /// What VoiceOver says of a day after its date: today, its holiday, and how many tasks once they are loaded.
    func spokenSummary(of day: CalendarDay, references: References) -> String {
        var parts: [String] = []
        if day == .today() { parts.append(String(localized: .today)) }
        if let holiday = references.holiday(on: day) { parts.append(holiday.shownLabel ?? String(localized: .holiday)) }
        if covers(day) {
            let count = tasks(on: day).count
            parts.append(count == 0 ? String(localized: .nothingPlanned) : String(localized: .nTasks(count)))
        }
        return parts.joined(separator: ", ")
    }
}
