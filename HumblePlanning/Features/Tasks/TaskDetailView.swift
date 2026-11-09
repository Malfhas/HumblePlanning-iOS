import CoreLocation
import MapKit
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import HumbleCore

/// Every detail of a task, and what the account may do with it.
struct TaskDetailView: View {
    let id: String
    @Environment(AppModel.self) private var app
    @State private var model: TaskDetailModel?

    var body: some View {
        if let model {
            TaskDetailContent(model: model)
        } else {
            ProgressView()
                .onAppear { model = TaskDetailModel(id: id, repository: app.repository) }
        }
    }
}

private struct TaskDetailContent: View {
    /// The first step of a deletion: a series asks how much of it, a shared task whether only a person leaves.
    enum DeleteChoice { case confirm, series, shared }

    @Bindable var model: TaskDetailModel
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @State private var deleteChoice: DeleteChoice?
    @State private var removesPerson = false
    @State private var fileToDelete: TaskFile?
    @State private var importsFile = false
    @State private var picksPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var scrollOffset: CGFloat = 0
    @State private var width: CGFloat = 0

    private var references: References { app.repository.references }
    private var access: Access { app.repository.access }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { await model.load(silent: model.task != nil) }
            .onChange(of: app.repository.tasksChanged) { Task { await model.load(silent: true) } }
            .onChange(of: model.deleted) { if model.deleted { dismiss() } }
            .quickLookPreview($model.preview)
            .fileImporter(isPresented: $importsFile, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result { upload(.file(url)) }
            }
            .photosPicker(isPresented: $picksPhoto, selection: $photo, matching: .any(of: [.images, .videos]),
                          preferredItemEncoding: .compatible)
            .onChange(of: photo) {
                guard let photo else { return }
                self.photo = nil
                upload(.photo(photo))
            }
    }

    @ViewBuilder private var content: some View {
        if let task = model.task {
            details(task)
        } else if model.loading {
            ProgressView()
        } else if model.notFound {
            EmptyState(systemImage: "calendar.badge.exclamationmark", title: String(localized: .errTaskNotFound)) {
                Button(String(localized: .back)) { dismiss() }.buttonStyle(.glass)
            }
        } else {
            EmptyState(systemImage: "calendar.badge.exclamationmark",
                       title: model.loadError.flatMap(screenMessage) ?? String(localized: .errUnexpected)) {
                Button(String(localized: .retry)) { Task { await model.load() } }.buttonStyle(.glass)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let task = model.task {
            ToolbarItem(placement: .principal) {
                // Only there once the header scrolled away: an invisible title would still be measured by the
                // accessibility audit (an empty space keeps the system title away)
                Group {
                    if scrollOffset > 90 {
                        Text(title(task))
                            .font(.headline)
                            .lineLimit(1)
                            .transition(.opacity)
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                .accessibilityHidden(true)
                .animation(.easeInOut(duration: 0.2), value: scrollOffset > 90)
            }
            if access.canEdit(task) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: .edit), systemImage: "pencil") { app.formRoute = .edit(id: task.id) }
                        .accessibilityIdentifier("detail.edit")
                }
            }
            if access.canDuplicate(task) || access.canDelete(task) {
                ToolbarItem(placement: .topBarTrailing) { moreMenu(task) }
            }
        }
    }

    private func moreMenu(_ task: PlanningTask) -> some View {
        Menu {
            if access.canDuplicate(task) {
                Button(String(localized: .duplicate), systemImage: "plus.square.on.square") { app.formRoute = .duplicate(id: task.id) }
            }
            if access.canDelete(task) {
                Button(String(localized: .delete), systemImage: "trash", role: .destructive) {
                    deleteChoice = task.isRecurring ? .series : task.users.count > 1 ? .shared : .confirm
                }
            }
        } label: {
            Label(String(localized: .moreActions), systemImage: "ellipsis")
        }
        .accessibilityIdentifier("detail.more")
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleteChoice != nil }, set: { if !$0 { deleteChoice = nil } }),
                            titleVisibility: .visible, presenting: deleteChoice) { choice in
            switch choice {
            case .confirm:
                Button(String(localized: .delete), role: .destructive) { delete(.single) }
            case .series:
                Button(String(localized: .deleteThisOccurrence), role: .destructive) { delete(.single) }
                Button(String(localized: .deleteThisAndFollowing), role: .destructive) { delete(.after) }
                Button(String(localized: .deleteWholeSeries), role: .destructive) { delete(.all) }
            case .shared:
                Button(String(localized: .deleteForEveryone), role: .destructive) { delete(.single) }
                if access.canAssign(task) {
                    Button(String(localized: .deleteRemoveUser)) { removesPerson = true }
                }
            }
            Button(String(localized: .cancel), role: .cancel) {}
        } message: { choice in
            if choice == .confirm { Text(.deleteText) }
        }
        .confirmationDialog(String(localized: .deleteRemoveUser), isPresented: $removesPerson, titleVisibility: .visible) {
            ForEach(task.users) { user in
                Button(user.displayName) { Task { await model.removeUser(user.id) } }
            }
            Button(String(localized: .cancel), role: .cancel) {}
        }
    }

    private var deleteTitle: String {
        switch deleteChoice {
        case .confirm: String(localized: .deleteTitle)
        case .series: String(localized: .deleteSeriesTitle)
        case .shared: String(localized: .deleteSharedTitle)
        case nil: ""
        }
    }

    private func delete(_ scope: DeleteScope) {
        Task { await model.delete(scope) }
    }

    // MARK: Content

    private func details(_ task: PlanningTask) -> some View {
        let projectColor = Color(serverHex: task.projectOf(references)?.color) ?? Color(.systemGray3)
        return List {
            Section { header(task, color: projectColor) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            if let actionError = model.actionError {
                bannerRow(Banner(text: actionError, tone: .error))
            }
            if let problem = model.fileProblem {
                bannerRow(Banner(text: message(problem), tone: .error))
            }
            Section { detailRows(task) }
            if let notes = task.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Text(notes).textSelection(.enabled)
                } header: {
                    Label(String(localized: .fieldNotes), systemImage: "text.alignleft")
                }
            }
            if references.filesEnabled && access.canViewFiles {
                attachments(task)
            }
        }
        .listSectionSpacing(.compact)
        // A readable width on a large screen (the colour of the project still fills it)
        .safeAreaPadding(.horizontal, max(0, (width - 800) / 2))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scrollContentBackground(.hidden)
        .background(alignment: .top) {
            LinearGradient(colors: [projectColor.opacity(0.32), projectColor.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .offset(y: -max(0, scrollOffset))
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            scrollOffset = offset
        }
        .navigationTitle(title(task))
    }

    /// The task's own title, else its project.
    private func title(_ task: PlanningTask) -> String {
        task.ownTitle ?? task.projectOf(references)?.label ?? ""
    }

    /// Project group and project above the title; the project only when the task has its own title.
    private func header(_ task: PlanningTask, color: Color) -> some View {
        let project = task.projectOf(references)
        let group = project?.group?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = [group?.isEmpty == false ? group : nil, task.ownTitle != nil ? project?.label : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        let status = task.statusOf(references)
        return VStack(alignment: .leading, spacing: 8) {
            if !context.isEmpty {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 12, height: 12)
                    // Over the colour of the project, the grey of the system would be too pale: a stronger one
                    Text(context).font(.subheadline.weight(.semibold)).foregroundStyle(.primary.opacity(0.75)).lineLimit(2)
                }
            }
            Text(title(task))
                .styled(by: status)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if status != nil || task.isMilestone || task.isLocked {
                AdaptiveStack(spacing: 10) {
                    if let status { StatusChip(status: status) }
                    if task.isMilestone {
                        Label {
                            Text(.milestone)
                        } icon: {
                            Image(systemName: "flag.fill").foregroundStyle(Palette.danger)
                        }
                    }
                    if task.isLocked {
                        Label(String(localized: .a11YLocked), systemImage: "lock.fill").foregroundStyle(.primary.opacity(0.75))
                    }
                }
                .font(.caption.weight(.medium))
                .labelStyle(CompactLabelStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bannerRow(_ banner: Banner) -> some View {
        Section { banner }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private func detailRows(_ task: PlanningTask) -> some View {
        detailRow(String(localized: .fieldDate), systemImage: "calendar", value: dates(task))
        detailRow(String(localized: .fieldTime), systemImage: "clock", value: task.timeRange ?? String(localized: .allDay))
        if let recurrence = task.recurrenceLabel(locale: locale) {
            detailRow(String(localized: .fieldRecurrence), systemImage: "repeat", value: recurrence)
        }
        ForEach(task.users) { user in
            Label {
                Text(user.displayName)
            } icon: {
                UserAvatar(user: user, size: 24)
            }
        }
        if let place = task.placeLabel {
            if let target = task.mapTarget(project: task.projectOf(references)) {
                Button { openMaps(target, label: place) } label: {
                    detailRow(String(localized: .fieldPlace), systemImage: "mappin.and.ellipse", value: place, isLink: true)
                }
            } else {
                detailRow(String(localized: .fieldPlace), systemImage: "mappin.and.ellipse", value: place)
            }
        }
        if let resource = task.resource?.name ?? references.resource(task.resourceId)?.name {
            detailRow(String(localized: .fieldResource), systemImage: "shippingbox", value: resource)
        }
        if let link = task.link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A link is only followed to a web page
            let web = link.lowercased().hasPrefix("http://") || link.lowercased().hasPrefix("https://")
            if web, let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Button { openURL(url) } label: {
                    detailRow(String(localized: .fieldLink), systemImage: "link", value: link, isLink: true)
                }
            } else {
                detailRow(String(localized: .fieldLink), systemImage: "link", value: link)
            }
        }
    }

    private func detailRow(_ label: String, systemImage: String, value: String, isLink: Bool = false) -> some View {
        // The grey of the label stays grey in a link row (`.secondary` would take the tint, too pale to read)
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(Color(.secondaryLabel))
                Text(value).foregroundStyle(isLink ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color(.secondaryLabel))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "From Monday 9 November to Tuesday 10 November" over several days, else the long label of the day.
    private func dates(_ task: PlanningTask) -> String {
        guard let start = task.startDay else { return task.startDate }
        if task.isMultiDay, let end = task.lastDay {
            return String(localized: .fromTo(PlanningFormat.longLabel(start, locale: locale, capitalized: false),
                                             PlanningFormat.longLabel(end, locale: locale, capitalized: false)))
        }
        return PlanningFormat.longLabel(start, locale: locale)
    }

    private func openMaps(_ target: MapTarget, label: String) {
        switch target {
        case .location(let latitude, let longitude):
            let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
            item.name = label
            item.openInMaps()
        case .address(let address):
            var components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: address)]
            if let url = components.url { openURL(url) }
        }
    }

    // MARK: Attachments

    /// Shown when the task has files or the account may add some; adding and deleting follow the right to
    /// modify the task, not to edit it: a locked task still takes files.
    @ViewBuilder private func attachments(_ task: PlanningTask) -> some View {
        let canAdd = access.canUploadFiles && access.canModify(task)
        let canDelete = access.canDeleteFiles && access.canModify(task)
        if !task.files.isEmpty || canAdd {
            Section {
                if task.files.isEmpty {
                    Text(.attachmentsNone).foregroundStyle(.secondary)
                }
                ForEach(task.files) { file in
                    fileRow(file, canDelete: canDelete)
                }
                if canAdd {
                    Menu {
                        Button(String(localized: .fileFromPhotos), systemImage: "photo.on.rectangle") { picksPhoto = true }
                        Button(String(localized: .fileFromFiles), systemImage: "folder") { importsFile = true }
                    } label: {
                        // The whole row opens the menu, not only its text
                        Label(String(localized: .fileAdd), systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .disabled(model.uploading)
                    .accessibilityIdentifier("detail.addFile")
                }
            } header: {
                HStack {
                    Label(String(localized: .attachments), systemImage: "paperclip")
                    Spacer()
                    if model.uploading { ProgressView().controlSize(.small) }
                }
            } footer: {
                if canAdd { Text(uploadHint) }
            }
            .confirmationDialog(String(localized: .fileDeleteTitle), isPresented: Binding(get: { fileToDelete != nil }, set: { if !$0 { fileToDelete = nil } }),
                                titleVisibility: .visible, presenting: fileToDelete) { file in
                Button(String(localized: .delete), role: .destructive) { Task { await model.deleteFile(file) } }
                Button(String(localized: .cancel), role: .cancel) {}
            } message: { file in
                Text(file.shownName)
            }
        }
    }

    private func fileRow(_ file: TaskFile, canDelete: Bool) -> some View {
        HStack(spacing: 12) {
            Button { Task { await model.open(file) } } label: {
                HStack(spacing: 12) {
                    Group {
                        if model.openingFileId == file.id {
                            ProgressView()
                        } else {
                            Image(systemName: file.symbol).foregroundStyle(.tint)
                        }
                    }
                    .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.shownName).lineLimit(2)
                        if file.size > 0 {
                            Text(PlanningFormat.fileSize(file.size, locale: locale)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(model.openingFileId != nil)
            if canDelete {
                Button { fileToDelete = file } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: .fileDeleteLabel(file.shownName)))
            }
        }
        .swipeActions {
            if canDelete {
                Button(String(localized: .delete), systemImage: "trash", role: .destructive) { fileToDelete = file }
            }
        }
    }

    /// "pdf, docx, png · 10 MB at most", or the size alone when every type is accepted.
    private var uploadHint: String {
        let size = String(localized: .filesMaxSize(Int(references.maxUploadBytes / (1024 * 1024))))
        let extensions = references.uploadExtensions
        return extensions.isEmpty ? size : extensions.joined(separator: ", ") + " · " + size
    }

    private func message(_ problem: FileProblem) -> String {
        switch problem {
        case .type: String(localized: .errFileType(references.uploadExtensions.joined(separator: ", ")))
        case .size: String(localized: .errFileSize(Int(references.maxUploadBytes / (1024 * 1024))))
        case .read: String(localized: .errFileRead)
        }
    }

    private func upload(_ source: UploadSource) {
        let references = references
        Task { await model.upload(source, references: references) }
    }
}

extension TaskFile {
    /// The name given at upload, else the stored one.
    var shownName: String { originalName.trimmingCharacters(in: .whitespaces).isEmpty ? name : originalName }

    var symbol: String {
        guard let type = UTType(mimeType: mimeType) ?? UTType(filenameExtension: TaskDetailModel.fileExtension(shownName)) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        return "doc.text"
    }
}
