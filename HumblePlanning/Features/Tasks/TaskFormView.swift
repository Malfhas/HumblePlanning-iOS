import SwiftUI
import HumbleCore

/// Creating, editing or duplicating a task. The form survives the app being ended by the system while it is
/// open (with the task already created, if only its recurrence failed).
struct TaskFormView: View {
    let route: TaskFormRoute

    private enum Pick: Identifiable {
        case project, people, status, place, resource
        var id: Self { self }
    }

    /// A date or a time whose picker is open under its row.
    private enum Expanded: Hashable {
        case date(TaskForm.DateField)
        case time(TaskForm.TimeField)
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @SceneStorage("task_form_draft") private var storedDraft: Data?
    @State private var state: TaskFormState
    @State private var started = false
    @State private var loadError: String?
    @State private var apiError: String?
    @State private var picking: Pick?
    @State private var expanded: Expanded?
    @State private var confirmsDiscard = false
    /// Bumped by a refusal: the message is at the top of the form.
    @State private var errorShown = 0

    init(route: TaskFormRoute) {
        self.route = route
        _state = State(initialValue: TaskFormState(kind: route.kind))
    }

    private var references: References { app.repository.references }
    /// A draft left on another server or by another account (sign-out, then another sign-in) is never restored.
    private var draftOwner: String { "\(app.repository.session?.serverURL ?? "")|\(references.user.id)" }
    private var access: Access { app.repository.access }
    private var form: TaskForm { state.form }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(state.dirty && !state.saved)
        .sheet(item: $picking) { picker($0).presentationDetents([.medium, .large]) }
        .task { await start() }
        .onChange(of: references) { state.referencesChanged(references) }
        .onChange(of: state.draft) { keepDraft() }
        .onDisappear { storedDraft = nil }
    }

    private var navigationTitle: String {
        if state.isCopy { return String(localized: .formTitleCopy) }
        return state.isNew ? String(localized: .newTask) : String(localized: .formTitleEdit)
    }

    @ViewBuilder private var content: some View {
        if state.loading {
            ProgressView()
        } else if state.loadFailed {
            EmptyState(systemImage: "calendar.badge.exclamationmark", title: loadError ?? String(localized: .errUnexpected)) {
                Button(String(localized: .back)) { dismiss() }.buttonStyle(.glass)
            }
        } else {
            ScrollViewReader { proxy in
                fields
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: errorShown) { withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel, action: close)
                .accessibilityIdentifier("form.cancel")
                .confirmationDialog(String(localized: .formDiscardTitle), isPresented: $confirmsDiscard, titleVisibility: .visible) {
                    Button(String(localized: .formDiscard), role: .destructive) { dismiss() }
                    Button(String(localized: .formKeepEditing), role: .cancel) {}
                } message: {
                    Text(.formDiscardText)
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            if state.saving {
                ProgressView()
            } else {
                Button(String(localized: .save), role: .confirm, action: save)
                    .disabled(!state.canSave)
                    .accessibilityIdentifier("form.save")
            }
        }
    }

    // MARK: Fields

    private var fields: some View {
        Form {
            if state.validationError != nil || apiError != nil {
                Section {
                    if let error = state.validationError { Banner(text: Self.message(error), tone: .error).id("top") }
                    if let apiError { Banner(text: apiError, tone: .error).id("top") }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                let project = state.project(references)
                pickRow(.project, label: String(localized: .fieldProject), systemImage: "folder", required: true,
                        value: project?.label, color: project?.color, error: state.validationError?.field == .project)
                pickRow(.people, label: String(localized: .fieldUsers), systemImage: "person.2", required: true,
                        value: peopleLabel, error: state.validationError?.field == .users,
                        enabled: state.canChangePeople(access))
                let status = state.status(references)
                pickRow(.status, label: String(localized: .fieldStatus), systemImage: "slider.horizontal.3", required: true,
                        value: status?.name, color: status?.color, error: state.validationError?.field == .status)
            }
            whenSection
            Section {
                Label {
                    TextField(String(localized: .fieldTitle), text: Binding(get: { form.title }, set: { text in edit { $0.setTitle(text) } }))
                        .accessibilityIdentifier("form.title")
                } icon: {
                    Image(systemName: "textformat").foregroundStyle(.secondary)
                }
                if references.placesEnabled {
                    let place = references.place(form.placeId)
                    pickRow(.place, label: String(localized: .fieldPlace), systemImage: "mappin.and.ellipse", value: place?.name, color: place?.color)
                    Label {
                        TextField(String(localized: .fieldPlaceText), text: Binding(get: { form.placeText }, set: { text in edit { $0.setPlaceText(text) } }))
                            .textContentType(.fullStreetAddress)
                    } icon: {
                        Image(systemName: "signpost.right").foregroundStyle(.secondary)
                    }
                }
                if references.resourcesEnabled {
                    let resource = references.resource(form.resourceId)
                    pickRow(.resource, label: String(localized: .fieldResource), systemImage: "shippingbox",
                            value: state.resourceName(references), color: resource?.color)
                }
                Label {
                    TextField(String(localized: .fieldLink), text: binding(\.link))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } icon: {
                    Image(systemName: "link").foregroundStyle(state.validationError?.field == .link ? Palette.danger : .secondary)
                }
            }
            Section {
                switchRow(String(localized: .milestone), subtitle: String(localized: .milestoneHelp), systemImage: "flag", isOn: binding(\.milestone))
                if state.showsLock(access) {
                    switchRow(String(localized: .formLock), subtitle: String(localized: .formLockHelp), systemImage: "lock", isOn: binding(\.locked))
                }
            }
            Section {
                Label {
                    TextField(String(localized: .fieldNotes), text: binding(\.notes), axis: .vertical)
                        .lineLimit(3...)
                } icon: {
                    Image(systemName: "text.alignleft").foregroundStyle(.secondary)
                }
            }
            recurrenceSections
            if state.isNew {
                Section {} footer: { Text(.formFilesAfter) }
            }
        }
    }

    /// The person when there is one, else how many.
    private var peopleLabel: String? {
        guard !form.userIds.isEmpty else { return nil }
        return state.singlePersonName(references) ?? String(localized: .nPeople(form.userIds.count))
    }

    private func pickRow(_ pick: Pick, label: String, systemImage: String, required: Bool = false, value: String?,
                         color: String? = nil, error: Bool = false, enabled: Bool = true) -> some View {
        Button { picking = pick } label: {
            HStack(spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(required ? label + " *" : label)
                            .font(.caption)
                            .foregroundStyle(error ? Palette.danger : .secondary)
                        HStack(spacing: 8) {
                            if value != nil, color != nil { ColorDot(hex: color) }
                            Text(value ?? String(localized: .choose))
                                .foregroundStyle(value == nil ? .secondary : .primary)
                                .lineLimit(2)
                        }
                    }
                } icon: {
                    Image(systemName: systemImage).foregroundStyle(error ? Palette.danger : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .disabled(!enabled)
        .accessibilityIdentifier("form.\(pick)")
    }

    /// Text with its icon in the secondary colour, aligned with the other rows.
    private func iconLabel(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
    }

    private func switchRow(_ title: String, subtitle: String? = nil, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: systemImage).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: When

    private var whenSection: some View {
        Section(String(localized: .formWhen)) {
            dateRow(.start, label: String(localized: .fieldStart) + " *", value: dayLabel(form.startDate))
            dateRow(.end, label: String(localized: .fieldEnd), value: dayLabel(form.endDate) ?? String(localized: .formSameDay),
                    clear: form.endDate.isEmpty ? nil : { edit { $0.setEndDate(nil) } })
            Picker(String(localized: .formWhen), selection: binding(\.mode)) {
                Text(.allDay).tag(DayMode.allDay)
                Text(.morning).tag(DayMode.morning)
                Text(.afternoon).tag(DayMode.afternoon)
                Text(.formTimes).tag(DayMode.times)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch form.mode {
            case .allDay:
                EmptyView()
            case .morning:
                iconLabel("\(references.morningStart) – \(references.morningEnd)", systemImage: "clock").foregroundStyle(.secondary)
            case .afternoon:
                iconLabel("\(references.afternoonStart) – \(references.afternoonEnd)", systemImage: "clock").foregroundStyle(.secondary)
            case .times:
                timeRow(.start, label: String(localized: .fieldStartTime))
                timeRow(.end, label: String(localized: .fieldEndTime))
            }
        }
    }

    private func dayLabel(_ iso: String) -> String? {
        CalendarDay(iso).map { PlanningFormat.mediumLabel($0, locale: locale) }
    }

    /// A row showing the date, the calendar opening under it.
    @ViewBuilder private func dateRow(_ field: TaskForm.DateField, label: String, value: String?, placeholder: String? = nil,
                                      clear: (() -> Void)? = nil) -> some View {
        let open = expanded == .date(field)
        HStack(spacing: 8) {
            Button { toggle(.date(field)) } label: {
                AdaptiveStack {
                    iconLabel(label, systemImage: field == .recurrenceEnd ? "calendar.badge.clock" : "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ValueCapsule(text: value ?? placeholder ?? "", active: open)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .accessibilityValue(value ?? placeholder ?? "")
            .accessibilityIdentifier("form.date.\(field)")
            if let clear {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: .formClearEnd))
            }
        }
        if open {
            DatePicker(label, selection: dateBinding(field), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
    }

    /// A row showing the time, the 24-hour wheel opening under it at the server's morning hours when empty.
    @ViewBuilder private func timeRow(_ field: TaskForm.TimeField, label: String) -> some View {
        let value = field == .start ? form.startTime : form.endTime
        let open = expanded == .time(field)
        Button {
            if value.isEmpty {
                let start = form.timePickerStart(field, references: references)
                edit { $0.setTime(field, hour: start.hour, minute: start.minute) }
            }
            toggle(.time(field))
        } label: {
            AdaptiveStack {
                iconLabel(label, systemImage: "clock")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ValueCapsule(text: value.isEmpty ? "--:--" : value, active: open)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityValue(value)
        if open {
            DatePicker(label, selection: timeBinding(field), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Self.twentyFourHours(locale))
                .frame(maxWidth: .infinity)
        }
    }

    private func toggle(_ picker: Expanded) {
        withAnimation { expanded = expanded == picker ? nil : picker }
    }

    // MARK: Recurrence

    /// "Apply to all" on any task of a series; the repeat block on a new task, a copy or the root of a series.
    @ViewBuilder private var recurrenceSections: some View {
        if state.showsApplyToAll {
            Section {
                switchRow(String(localized: .formApplyAll), subtitle: String(localized: .formApplyAllHelp), systemImage: "square.stack",
                          isOn: binding(\.applyToAll))
                    .accessibilityIdentifier("form.applyToAll")
            }
        }
        if state.showsRecurrence {
            Section {
                // A series exists from its root on: it cannot be turned back into a single task here
                switchRow(String(localized: .formRepeat), systemImage: "repeat", isOn: binding(\.repeats))
                    .disabled(!state.canChangeRepeat)
                    .accessibilityIdentifier("form.repeat")
                if form.repeats {
                    Picker(String(localized: .formRepeat), selection: binding(\.recurType)) {
                        Text(.recurDaily).tag("daily")
                        Text(.recurWeekly).tag("weekly")
                        Text(.recurMonthly).tag("monthly")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    LabeledContent {
                        TextField(text: binding(\.frequencyText), prompt: Text(verbatim: "1")) { Text(.formRepeatEvery) }
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(.formRepeatEvery)
                                    .foregroundStyle(state.validationError?.field == .frequency ? Palette.danger : .primary)
                                Text(.formRepeatEveryHelp).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.trianglehead.2.clockwise").foregroundStyle(.secondary)
                        }
                    }
                    dateRow(.recurrenceEnd, label: String(localized: .formRepeatUntil) + " *", value: dayLabel(form.recurEndDate),
                            placeholder: String(localized: .choose))
                    Picker(selection: binding(\.recurException)) {
                        Text(.formExceptionSkip).tag("skip")
                        Text(.formExceptionShift).tag("shift")
                        Text(.formExceptionInclude).tag("include")
                    } label: {
                        iconLabel(String(localized: .formRepeatException), systemImage: "calendar.badge.minus")
                    }
                }
            }
        }
    }

    // MARK: Pickers

    @ViewBuilder private func picker(_ pick: Pick) -> some View {
        switch pick {
        case .project:
            PickerSheet(title: String(localized: .fieldProject),
                        items: references.projects.map { PickerItem(id: $0.id, label: $0.label, color: $0.color, group: $0.group?.name) },
                        selected: [form.projectId], multiple: false) { ids in
                edit { $0.projectId = ids.first ?? "" }
            }
        case .people:
            let choices = state.peopleChoices(references)
            PickerSheet(title: String(localized: .fieldUsers),
                        items: choices.map { user in
                            PickerItem(id: user.id, label: user.displayName, color: user.color,
                                       group: references.teams.first { $0.id == user.teamId }?.name)
                        },
                        selected: Set(form.userIds), multiple: true) { ids in
                edit { $0.userIds = choices.map(\.id).filter(ids.contains) }
            }
        case .status:
            PickerSheet(title: String(localized: .fieldStatus),
                        items: references.statuses.map { PickerItem(id: $0.id, label: $0.name, color: $0.color) },
                        selected: [form.statusId], multiple: false) { ids in
                edit { $0.statusId = ids.first ?? "" }
            }
        case .place:
            PickerSheet(title: String(localized: .fieldPlace),
                        items: references.places.map { PickerItem(id: $0.id, label: $0.name, color: $0.color) },
                        selected: form.placeId.isEmpty ? [] : [form.placeId], multiple: false, allowNone: true) { ids in
                edit { $0.setPlace(ids.first) }
            }
        case .resource:
            PickerSheet(title: String(localized: .fieldResource),
                        items: references.resources.map { PickerItem(id: $0.id, label: $0.name, color: $0.color) },
                        selected: form.resourceId.isEmpty ? [] : [form.resourceId], multiple: false, allowNone: true) { ids in
                edit { $0.resourceId = ids.first ?? "" }
            }
        }
    }

    // MARK: Bindings

    /// Every change clears the messages of the last save.
    private func edit(_ change: (inout TaskForm) -> Void) {
        state.update(change)
        apiError = nil
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TaskForm, Value>) -> Binding<Value> {
        Binding(get: { state.form[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    /// Picking a day closes the calendar.
    private func dateBinding(_ field: TaskForm.DateField) -> Binding<Date> {
        Binding(get: { form.datePickerStart(field, today: .today()).date() }, set: { date in
            let day = CalendarDay(date)
            edit {
                switch field {
                case .start: $0.setStartDate(day)
                case .end: $0.setEndDate(day)
                case .recurrenceEnd: $0.setRecurrenceEnd(day)
                }
            }
            withAnimation { expanded = nil }
        })
    }

    private func timeBinding(_ field: TaskForm.TimeField) -> Binding<Date> {
        Binding(get: {
            let time = form.timePickerStart(field, references: references)
            return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            edit { $0.setTime(field, hour: parts.hour ?? 0, minute: parts.minute ?? 0) }
        })
    }

    /// The wheel in the language of the app, on the 24-hour clock.
    private static func twentyFourHours(_ locale: Locale) -> Locale {
        var components = Locale.Components(locale: locale)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

    // MARK: Actions

    /// Loads the task to edit or to copy (never from the offline copy), or fills the defaults of a new one.
    private func start() async {
        guard !started else { return }
        started = true
        if let data = storedDraft, let stored = try? JSONDecoder().decode(StoredDraft.self, from: data),
           stored.route == route.id, stored.owner == draftOwner {
            state = TaskFormState(kind: route.kind, restored: stored.draft)
        }
        guard let id = state.sourceId else {
            state.referencesChanged(references)
            return
        }
        do {
            let task = try await app.repository.taskToEdit(id)
            state.loaded(task, references: references)
        } catch {
            loadError = screenMessage(error)
            state.loadingFailed()
        }
    }

    /// Kept only once the task is loaded: an empty form must never come back over a task.
    private func keepDraft() {
        guard !state.loading, !state.loadFailed, !state.saved else { return }
        storedDraft = try? JSONEncoder().encode(StoredDraft(route: route.id, owner: draftOwner, draft: state.draft))
    }

    private func close() {
        if state.dirty && !state.saved {
            confirmsDiscard = true
        } else {
            dismiss()
        }
    }

    /// Creates or updates the task, then builds its series when the rule is new or changed. A new task created
    /// before its series failed is updated by the next try, not created twice.
    private func save() {
        apiError = nil
        withAnimation { expanded = nil }
        guard let request = state.prepareSave(references: references) else {
            errorShown += 1
            return
        }
        let repository = app.repository
        Task {
            do {
                let saved = if let id = request.taskId {
                    try await repository.updateTask(id, request.payload, applyToAll: request.applyToAll)
                } else {
                    try await repository.createTask(request.payload)
                }
                state.taskSaved(id: saved.id)
                if let rule = request.repeatRequest {
                    try await repository.repeatTask(saved.id, rule)
                }
                state.saveSucceeded()
                dismiss()
            } catch {
                state.saveFailed()
                apiError = screenMessage(error)
                if apiError != nil { errorShown += 1 }
            }
        }
    }

    static func message(_ error: FormError) -> String {
        switch error {
        case .projectRequired: String(localized: .valProject)
        case .usersRequired: String(localized: .valUsers)
        case .statusRequired: String(localized: .valStatus)
        case .startDateRequired: String(localized: .valStart)
        case .endDateBeforeStart: String(localized: .valEndBeforeStart)
        case .timesRequired: String(localized: .valTimes)
        case .endTimeBeforeStart: String(localized: .valEndTime)
        case .textTooLong: String(localized: .valTextLong)
        case .linkInvalid: String(localized: .valLink)
        case .recurrenceEndRequired: String(localized: .valRecurEnd)
        case .recurrenceEndBeforeStart: String(localized: .valRecurEndBefore)
        case .recurrenceFrequency: String(localized: .valRecurFrequency)
        }
    }
}

/// The form kept for the route it belongs to, on the server and for the account it was filled with.
private struct StoredDraft: Codable {
    let route: String
    let owner: String
    let draft: TaskFormDraft
}

extension TaskFormRoute {
    var kind: TaskFormState.Kind {
        switch self {
        case .create(let date, let userId): .create(date: date?.iso, userId: userId)
        case .edit(let id): .edit(id: id)
        case .duplicate(let id): .duplicate(of: id)
        }
    }
}

/// The value of a date or time row, like the system's compact pickers.
private struct ValueCapsule: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }
}
