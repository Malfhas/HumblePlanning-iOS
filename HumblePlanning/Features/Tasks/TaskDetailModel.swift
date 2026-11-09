import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import HumbleCore

/// Why an attachment was refused before anything was sent.
enum FileProblem: Equatable {
    /// Its extension is not in the list of the server.
    case type
    /// Larger than the server accepts.
    case size
    /// Its size or content could not be read.
    case read
}

/// Where a new attachment comes from.
enum UploadSource {
    /// Chosen in the Files app: read in place.
    case file(URL)
    /// Chosen in the photo library: copied out of it first.
    case photo(PhotosPickerItem)
}

/// The task of the detail, kept up to date, and what the detail does with it: delete, remove a person,
/// add, open and delete attachments.
@MainActor
@Observable
final class TaskDetailModel {
    let id: String
    private(set) var task: PlanningTask?
    private(set) var loading = true
    private(set) var loadError: (any Error)?
    /// Deleted from here: the screen goes back.
    private(set) var deleted = false
    private(set) var uploading = false
    /// The attachment being downloaded before it opens.
    private(set) var openingFileId: String?
    /// The downloaded attachment shown by Quick Look.
    var preview: URL?
    private(set) var fileProblem: FileProblem?
    /// A failed delete, removal, upload, download or file deletion.
    private(set) var actionError: String?

    private let repository: Repository

    init(id: String, repository: Repository) {
        self.id = id
        self.repository = repository
    }

    var notFound: Bool { (loadError as? APIError)?.isNotFound == true }

    /// A silent load keeps what is shown; a task deleted meanwhile turns into "not found".
    func load(silent: Bool = false) async {
        guard !deleted else { return }
        if !silent {
            loading = true
            loadError = nil
        }
        do {
            task = try await repository.task(id)
            loadError = nil
        } catch is CancellationError {
        } catch {
            if (error as? APIError)?.isNotFound == true { task = nil }
            loadError = error
        }
        loading = false
    }

    func delete(_ scope: DeleteScope) async {
        await act {
            try await repository.deleteTask(id, scope: scope)
            self.deleted = true
        }
    }

    /// The task stays, without this person.
    func removeUser(_ userId: String) async {
        await act { try await repository.removeUser(userId, from: id) }
    }

    func deleteFile(_ file: TaskFile) async {
        await act { try await repository.deleteFile(taskId: id, fileId: file.id) }
    }

    /// Downloads the attachment into the cache of attachments, then shows it; one at a time.
    func open(_ file: TaskFile) async {
        guard openingFileId == nil else { return }
        openingFileId = file.id
        fileProblem = nil
        actionError = nil
        do {
            preview = try await repository.download(file, taskId: id)
        } catch {
            actionError = screenMessage(error)
        }
        openingFileId = nil
    }

    /// Checks the extension and the size before anything is sent; the file is streamed, never held in memory.
    func upload(_ source: UploadSource, references: References) async {
        guard !uploading else { return }
        uploading = true
        fileProblem = nil
        actionError = nil
        defer { uploading = false }
        switch source {
        case .file(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await send(url, references: references)
        case .photo(let item):
            guard let photo = try? await item.loadTransferable(type: PickedPhoto.self) else {
                fileProblem = .read
                return
            }
            defer { try? FileManager.default.removeItem(at: photo.url.deletingLastPathComponent()) }
            await send(photo.url, references: references)
        }
    }

    private func send(_ url: URL, references: References) async {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey]),
              values.isRegularFile == true, let size = values.fileSize else {
            fileProblem = .read
            return
        }
        let name = safeFileName(url.lastPathComponent, fallback: "file")
        let allowed = references.uploadExtensions
        if !allowed.isEmpty && !allowed.contains(Self.fileExtension(name)) {
            fileProblem = .type
            return
        }
        if Int64(size) > references.maxUploadBytes {
            fileProblem = .size
            return
        }
        let type = values.contentType?.preferredMIMEType ?? "application/octet-stream"
        do {
            try await repository.uploadFile(taskId: id, file: url, name: name, contentType: type)
        } catch {
            actionError = screenMessage(error)
        }
    }

    private func act(_ work: () async throws -> Void) async {
        actionError = nil
        do {
            try await work()
        } catch {
            actionError = screenMessage(error)
        }
    }

    /// What follows the last dot, lower case; empty without a dot.
    static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}

/// A photo or a video of the library, copied by the picker into a folder of its own (removed after the upload).
/// Photos come in a compatible format (JPEG rather than HEIC), which the servers' lists of extensions accept.
nonisolated struct PickedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { try copy($0.file) }
        FileRepresentation(importedContentType: .movie) { try copy($0.file) }
    }

    private static func copy(_ file: URL) throws -> PickedPhoto {
        let folder = FileManager.default.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copy)
        return PickedPhoto(url: copy)
    }
}

extension PlanningTask {
    /// "Every week, until Dec 31, 2026" on the root of a series; its occurrences only say they belong to one.
    func recurrenceLabel(locale: Locale) -> String? {
        guard isRecurring else { return nil }
        let frequency = recurFrequency ?? 1
        let rule: String? = switch recurType {
        case "daily": frequency == 1 ? String(localized: .recurEveryDay) : String(localized: .recurEveryDays(frequency))
        case "weekly": frequency == 1 ? String(localized: .recurEveryWeek) : String(localized: .recurEveryWeeks(frequency))
        case "monthly": frequency == 1 ? String(localized: .recurEveryMonth) : String(localized: .recurEveryMonths(frequency))
        default: nil
        }
        guard isSeriesRoot, let rule else { return String(localized: .recurPartOfSeries) }
        guard let end = recurEndDate.flatMap(CalendarDay.init) else { return rule }
        return String(localized: .recurUntil(rule, PlanningFormat.mediumLabel(end, locale: locale)))
    }

    /// Where the maps open: the coordinates of the address, else those of the project, else its address.
    func mapTarget(project: Project?) -> MapTarget? {
        if let location = MapTarget.coordinates(placeTextLat, placeTextLng) { return location }
        if let location = MapTarget.coordinates(project?.addressLat, project?.addressLng) { return location }
        guard let address = project?.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { return nil }
        return .address(address)
    }
}

enum MapTarget: Equatable {
    case location(latitude: Double, longitude: Double)
    case address(String)

    static func coordinates(_ latitude: String?, _ longitude: String?) -> MapTarget? {
        guard let latitude = latitude.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
              let longitude = longitude.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) })
        else { return nil }
        return .location(latitude: latitude, longitude: longitude)
    }
}
