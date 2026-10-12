import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import Observation
import os

/// Library file-system problems (diagnostics only, never shown to the user).
private let libraryLog = Logger(subsystem: "com.hmdalajmi.noor", category: "Library")

// MARK: - Storage usage

/// Bytes Noor keeps on the device, for Settings → Storage.
struct LibraryStorageUsage: Equatable, Sendable {
    /// Originals and their recipes (Application Support/Library). Backed up with the device.
    var originals: Int64
    /// Display thumbnails (Caches/Thumbnails). Safe to delete; regenerated on demand.
    var thumbnails: Int64
}

// MARK: - Library

/// Noor's photo library: every imported original, its recipe and its display thumbnail.
///
/// Storage (all inside the app container; nothing in the Photos library is ever modified):
///   * `Application Support/Library/<id>/` - the original file (exact bytes, original name and
///     extension) and `project.json` (`PhotoProject`). A project folder is assembled under
///     `Library/.Staging/` and renamed into place, so it appears atomically or not at all.
///   * `Caches/Thumbnails/<id>-<recipe digest>.jpg` - ~600 px display thumbnails. These are the only
///     8-bit images Noor writes, are never exported, and are regenerated whenever the recipe changes.
///
/// Threading: the store is main-actor state. Decoding, inspecting, copying and thumbnail rendering run
/// on background queues; `project.json` writes go through one serial queue so they stay ordered.
/// `originalURL(for:)` and `document(for:)` are `nonisolated`, so the editor can open a document off
/// the main thread.
@MainActor
@Observable
final class LibraryStore {

    // MARK: Observable state

    /// Newest first (by import time), stable across launches.
    private(set) var projects: [PhotoProject] = []
    /// True while any import batch is running.
    private(set) var isImporting = false
    /// Human-readable problems from the current / last import (or a failed duplicate).
    private(set) var importErrors: [String] = []
    /// False until the project folders have been scanned at launch.
    private(set) var isLoaded = false
    /// Items in the running import batches, and how many of them are finished (for "3 of 10").
    private(set) var importTotal = 0
    private(set) var importCompleted = 0

    // MARK: Private state

    @ObservationIgnored private let pipeline = LibraryThumbnailPipeline()
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "com.hmdalajmi.noor.library.io", qos: .utility)
    /// One observable slot per project, so a finished thumbnail refreshes only its own cell.
    @ObservationIgnored private var slots: [UUID: LibraryThumbnailSlot] = [:]
    /// Stable recipe digests, cached per project (recomputed only when the recipe changes).
    @ObservationIgnored private var thumbnailDigests: [UUID: (recipe: EditRecipe, digest: String)] = [:]
    /// Thumbnails waiting for the editor to settle before they re-render.
    @ObservationIgnored private var deferredRefreshes: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var accessTick: UInt64 = 0
    @ObservationIgnored private var activeImports = 0
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?

    /// Thumbnail slots kept in memory (~1-1.4 MB of decoded bitmap each); least recently requested
    /// go first. 120 is about 2.5 screens of the largest iPad grid while staying near 150 MB, because
    /// the grid stays alive (and keeps its slots) underneath the editor.
    private static let slotLimit = 120
    /// The editor saves about once a second while the user works; re-render the library thumbnail
    /// only once edits pause, so it never competes with the live preview.
    private static let refreshDelay: Duration = .milliseconds(1500)

    // MARK: Init

    /// Prepares the folders and scans the existing projects in the background.
    init() {
        // Synchronous and before any import can start: half-built projects from an interrupted run
        // are discarded (the user never saw them).
        LibraryFiles.prepareForLaunch()

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMemoryWarning() }
        }

        Task { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                LibraryFiles.loadProjects()
            }.value
            guard let self else { return }
            self.finishLoading(scanned)
            let known = Set(self.projects.map(\.id))
            Task.detached(priority: .background) {
                LibraryFiles.cleanUp(keepingThumbnailsOf: known)
            }
        }
    }

    /// Publishes the scanned projects, keeping any imported while the scan ran.
    private func finishLoading(_ scanned: [PhotoProject]) {
        let present = Set(projects.map(\.id))
        var merged = projects
        merged.append(contentsOf: scanned.filter { !present.contains($0.id) })
        merged.sort(by: PhotoProject.libraryOrder)
        projects = merged
        isLoaded = true
    }

    // MARK: Lookup

    /// The current value of a project (the library's copy is the source of truth).
    func project(id: PhotoProject.ID) -> PhotoProject? {
        projects.first { $0.id == id }
    }

    /// Location of the stored original. Never write to it.
    nonisolated func originalURL(for project: PhotoProject) -> URL {
        LibraryFiles.originalURL(id: project.id, fileName: project.originalFileName)
    }

    /// Opens the original for rendering (metadata inspection only; no pixels are decoded).
    /// `nonisolated`: call it from a background task when opening the editor.
    nonisolated func document(for project: PhotoProject) throws -> PhotoDocument {
        try PhotoDocument(url: originalURL(for: project))
    }

    // MARK: Thumbnails

    /// The project's display thumbnail, from memory or disk, rendered through its current recipe.
    /// Returns nil until it is ready, then the calling view refreshes (the slot is observable). While a
    /// changed recipe re-renders, the previous thumbnail is returned.
    func thumbnail(for project: PhotoProject) -> UIImage? {
        requestThumbnail(project).image
    }

    /// True when no thumbnail could be made for the project (e.g. its original is damaged).
    func thumbnailFailed(for project: PhotoProject) -> Bool {
        requestThumbnail(project).hasFailed
    }

    /// Finds or creates the project's slot and starts loading / rendering when its image is stale.
    /// Only touches unobserved bookkeeping synchronously, so it is safe to call from a view's body.
    @discardableResult
    private func requestThumbnail(_ project: PhotoProject) -> LibraryThumbnailSlot {
        accessTick &+= 1
        let slot: LibraryThumbnailSlot
        if let existing = slots[project.id] {
            slot = existing
            slot.lastAccess = accessTick
        } else {
            // Trim first, so the slot being created can never be evicted by its own insertion.
            trimSlotsIfNeeded()
            slot = LibraryThumbnailSlot()
            slot.lastAccess = accessTick
            slots[project.id] = slot
        }

        let digest = thumbnailDigest(for: project)
        guard slot.imageDigest != digest,
              slot.pendingDigest != digest,
              slot.failedDigest != digest,
              deferredRefreshes[project.id] == nil
        else { return slot }

        slot.pendingDigest = digest
        let id = project.id
        let request = LibraryThumbnailRequest(id: id, digest: digest,
                                              originalURL: originalURL(for: project),
                                              recipe: project.recipe)
        pipeline.load(request) { [weak self] image in
            Task { @MainActor [weak self] in
                self?.thumbnailDidLoad(image, id: id, digest: digest)
            }
        }
        return slot
    }

    private func thumbnailDidLoad(_ image: UIImage?, id: UUID, digest: String) {
        // A slot evicted meanwhile (or a newer recipe requested) ignores the result; the disk cache
        // still has it for next time.
        guard let slot = slots[id], slot.pendingDigest == digest else { return }
        slot.pendingDigest = nil
        if let image {
            slot.image = image
            slot.imageDigest = digest
            slot.failedDigest = nil
            if slot.hasFailed { slot.hasFailed = false }
        } else {
            slot.failedDigest = digest
            if slot.image == nil { slot.hasFailed = true }
        }
    }

    /// Stable digest of a recipe (cached while the recipe is unchanged).
    private func thumbnailDigest(for project: PhotoProject) -> String {
        if let cached = thumbnailDigests[project.id], cached.recipe == project.recipe {
            return cached.digest
        }
        let digest = LibraryFiles.recipeDigest(project.recipe)
        thumbnailDigests[project.id] = (project.recipe, digest)
        return digest
    }

    /// Drops the least recently requested slots. Cells on screen keep showing the image they already
    /// have; they only ask again when they are rebuilt.
    private func trimSlotsIfNeeded() {
        guard slots.count >= LibraryStore.slotLimit else { return }
        let target = LibraryStore.slotLimit * 3 / 4
        let evictable = slots
            .filter { $0.value.pendingDigest == nil }
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
        let excess = slots.count - target
        for entry in evictable.prefix(max(0, excess)) {
            slots[entry.key] = nil
        }
    }

    /// Re-renders a project's thumbnail once edits pause (see `refreshDelay`).
    private func scheduleThumbnailRefresh(for id: UUID) {
        deferredRefreshes[id]?.cancel()
        deferredRefreshes[id] = Task { [weak self] in
            try? await Task.sleep(for: LibraryStore.refreshDelay)
            guard !Task.isCancelled, let self else { return }
            self.deferredRefreshes[id] = nil
            if let project = self.project(id: id) {
                self.requestThumbnail(project)
            }
        }
    }

    private func refreshThumbnailNow(for project: PhotoProject) {
        deferredRefreshes[project.id]?.cancel()
        deferredRefreshes[project.id] = nil
        requestThumbnail(project)
    }

    private func handleMemoryWarning() {
        slots = slots.filter { $0.value.pendingDigest != nil }
        pipeline.purgeDocuments()
    }

    // MARK: Import

    /// Imports photos picked with `.photosPicker(..., preferredItemEncoding: .current, ...)`: each item's
    /// stored file is copied byte for byte (`ImportedOriginal`), inspected and added as a new project.
    /// Items are processed in selection order and keep that order at the top of the library.
    func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        beginImport(count: items.count)
        defer { endImport() }

        let batchStart = Date()
        for (index, item) in items.enumerated() {
            let createdAt = LibraryStore.importDate(batchStart: batchStart, index: index)
            do {
                guard let original = try await item.loadTransferable(type: ImportedOriginal.self) else {
                    throw LibraryImportError.noImageData
                }
                let project = try await createProject(from: original, createdAt: createdAt)
                insert(project)
            } catch {
                importErrors.append(String(localized: "A photo couldn't be imported. \(LibraryStore.message(for: error))"))
            }
            importCompleted += 1
        }
    }

    /// Imports files picked in Files (or opened from another app): security-scoped, coordinated
    /// byte-for-byte copies.
    func importFiles(_ urls: [URL]) async {
        await importFileURLs(urls)
    }

    /// `importFiles(_:)`, returning the projects that were added, in order (e.g. to open the photo a
    /// user sent to Noor from another app).
    @discardableResult
    func importFileURLs(_ urls: [URL]) async -> [PhotoProject] {
        guard !urls.isEmpty else { return [] }
        beginImport(count: urls.count)
        defer { endImport() }

        var added: [PhotoProject] = []
        let batchStart = Date()
        for (index, url) in urls.enumerated() {
            let createdAt = LibraryStore.importDate(batchStart: batchStart, index: index)
            let name = url.lastPathComponent
            do {
                let original = try await Task.detached(priority: .userInitiated) {
                    try ImportedOriginal.stageFile(at: url)
                }.value
                let project = try await createProject(from: original, createdAt: createdAt)
                insert(project)
                added.append(project)
            } catch {
                importErrors.append(String(localized: "“\(name)” couldn't be imported. \(LibraryStore.message(for: error))"))
            }
            importCompleted += 1
        }
        return added
    }

    /// Dismisses the import problems (after the alert was shown).
    func clearImportErrors() {
        importErrors = []
    }

    /// Adds a problem reported by the import UI itself (e.g. the file picker failed to open).
    func reportImportError(_ message: String) {
        importErrors.append(message)
    }

    /// Inspects the staged original off the main thread and assembles its project folder.
    private func createProject(from original: ImportedOriginal, createdAt: Date) async throws -> PhotoProject {
        try await Task.detached(priority: .userInitiated) { () throws -> PhotoProject in
            defer { original.discardStaging() }
            return try LibraryFiles.makeProject(stagedFile: original.url,
                                                fileName: original.fileName,
                                                declaredType: original.declaredType,
                                                createdAt: createdAt)
        }.value
    }

    private func beginImport(count: Int) {
        if activeImports == 0 {
            importErrors = []
            importTotal = 0
            importCompleted = 0
        }
        activeImports += 1
        importTotal += count
        isImporting = true
    }

    private func endImport() {
        activeImports = max(0, activeImports - 1)
        guard activeImports == 0 else { return }
        isImporting = false
        importTotal = 0
        importCompleted = 0
    }

    /// Items of one batch get import times 1 ms apart, so the first selected sorts first.
    private static func importDate(batchStart: Date, index: Int) -> Date {
        batchStart.addingTimeInterval(-Double(index) / 1000)
    }

    /// Inserts at the position given by the library order.
    private func insert(_ project: PhotoProject) {
        guard !projects.contains(where: { $0.id == project.id }) else { return }
        let index = projects.firstIndex { PhotoProject.libraryOrder(project, $0) } ?? projects.endIndex
        projects.insert(project, at: index)
    }

    // MARK: Editing

    /// Persists a changed project (recipe / modifiedAt) and re-renders its thumbnail in the background
    /// once edits pause. Unknown projects (e.g. removed meanwhile) are ignored.
    func update(_ project: PhotoProject) {
        store(project, refreshesThumbnailNow: false)
    }

    /// Back to the identity recipe (for RAW: the camera defaults). Geometry is reset too.
    func resetEdits(_ project: PhotoProject) {
        guard var current = self.project(id: project.id), current.recipe != EditRecipe() else { return }
        current.recipe = EditRecipe()
        current.modifiedAt = Date()
        store(current, refreshesThumbnailNow: true)
    }

    /// A second project with its own copy of the original (an APFS clone, so it costs almost no
    /// space until one of them is removed) and the same recipe. It sorts right after the source.
    func duplicate(_ project: PhotoProject) {
        guard let source = self.project(id: project.id) else { return }
        let createdAt = source.createdAt.addingTimeInterval(-0.001)
        let digest = thumbnailDigest(for: source)
        let sourceImage: UIImage? = slots[source.id].flatMap { $0.imageDigest == digest ? $0.image : nil }

        Task {
            do {
                let clone = try await Task.detached(priority: .userInitiated) {
                    try LibraryFiles.duplicate(source, createdAt: createdAt, thumbnailDigest: digest)
                }.value
                // Same original, same recipe: the source's thumbnail is already the right picture.
                if let sourceImage {
                    let slot = LibraryThumbnailSlot()
                    slot.image = sourceImage
                    slot.imageDigest = digest
                    self.slots[clone.id] = slot
                    self.thumbnailDigests[clone.id] = (clone.recipe, digest)
                }
                self.insert(clone)
            } catch {
                self.importErrors.append(String(localized: "“\(source.displayName)” couldn't be duplicated. \(LibraryStore.message(for: error))"))
            }
        }
    }

    /// Deletes the project folder (the app's own copy of the original and its recipe) and its
    /// thumbnails. Never touches the Photos library or the file it was imported from.
    func remove(_ project: PhotoProject) {
        let id = project.id
        let original = originalURL(for: self.project(id: id) ?? project)
        projects.removeAll { $0.id == id }
        slots[id] = nil
        thumbnailDigests[id] = nil
        deferredRefreshes[id]?.cancel()
        deferredRefreshes[id] = nil
        pipeline.forgetDocument(at: original)
        // Serial queue: runs after any pending project.json write for this project.
        ioQueue.async {
            LibraryFiles.deleteProject(id: id)
        }
    }

    private func store(_ project: PhotoProject, refreshesThumbnailNow: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        guard projects[index] != project else { return }
        let recipeChanged = projects[index].recipe != project.recipe
        projects[index] = project
        persist(project)
        guard recipeChanged else { return }
        if refreshesThumbnailNow {
            refreshThumbnailNow(for: project)
        } else {
            scheduleThumbnailRefresh(for: project.id)
        }
    }

    /// Encodes on the main actor (cheap) and writes atomically on the serial IO queue.
    private func persist(_ project: PhotoProject) {
        let data: Data
        do {
            data = try LibraryFiles.encode(project)
        } catch {
            libraryLog.error("Could not encode project \(project.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let url = LibraryFiles.projectFileURL(id: project.id)
        ioQueue.async {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                libraryLog.error("Could not save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Storage

    /// Space used by originals + recipes and by the thumbnail cache (computed off the main thread).
    func storageUsage() async -> LibraryStorageUsage {
        await Task.detached(priority: .utility) {
            LibraryStorageUsage(originals: LibraryFiles.allocatedSize(of: LibraryFiles.root),
                                thumbnails: LibraryFiles.allocatedSize(of: LibraryFiles.thumbnailRoot))
        }.value
    }

    /// Deletes every cached thumbnail. Cells regenerate theirs the next time they are shown.
    func clearThumbnailCache() async {
        slots = slots.filter { $0.value.pendingDigest != nil }
        pipeline.purgeDocuments()
        await Task.detached(priority: .utility) {
            LibraryFiles.clearThumbnails()
        }.value
    }

    // MARK: Messages

    /// A short, user-facing reason for an import / duplicate failure.
    private static func message(for error: Error) -> String {
        switch error {
        case PhotoDocumentError.unsupported:
            return String(localized: "Noor can't read this file format.")
        case PhotoDocumentError.unreadable:
            return String(localized: "The file couldn't be read. It may be damaged.")
        case LibraryImportError.noImageData:
            return String(localized: "The photo isn't available in a format Noor can open.")
        case let cocoa as CocoaError where cocoa.code == .fileWriteOutOfSpace:
            return String(localized: "There isn't enough storage space.")
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Import errors

/// Failures of the library's own import steps (decoding problems come from `PhotoDocumentError`).
private enum LibraryImportError: Error {
    case noImageData        // the picker item offered no image representation
}

// MARK: - Thumbnail slot

/// The observable thumbnail state of one project (an implementation detail of `LibraryStore`). Cells
/// observe only their own slot; the bookkeeping (`@ObservationIgnored`) changes without refreshing
/// anything.
@MainActor
@Observable
final class LibraryThumbnailSlot {
    var image: UIImage?
    var hasFailed = false

    /// Recipe digest `image` was rendered with.
    @ObservationIgnored var imageDigest: String?
    /// Digest being loaded / rendered right now.
    @ObservationIgnored var pendingDigest: String?
    /// Digest that could not be rendered (not retried until the recipe changes).
    @ObservationIgnored var failedDigest: String?
    @ObservationIgnored var lastAccess: UInt64 = 0
}

// MARK: - Thumbnail pipeline

/// Everything one background thumbnail job needs (plain values, safe to send to another thread).
private struct LibraryThumbnailRequest: Sendable {
    let id: UUID
    let digest: String
    let originalURL: URL
    let recipe: EditRecipe
}

/// Loads thumbnails from the disk cache or renders them through the recipe with `ThumbnailRenderer`
/// (the same pipeline as preview and export), then caches them as JPEG.
///
/// Thread safety: cache reads run on one private `OperationQueue` and renders on another (two at a
/// time each, utility QoS), so a slow RAW render never holds up thumbnails that are already on disk.
/// The only shared mutable state, a tiny most-recently-used list of open `PhotoDocument`s (so
/// re-rendering the photo being edited reuses its decoded thumbnail base), is guarded by `lock`.
/// `PhotoDocument` itself is thread-safe.
private final class LibraryThumbnailPipeline: @unchecked Sendable {
    /// Long edge of library thumbnails, in pixels.
    static let longEdge: CGFloat = 600
    private static let jpegQuality = 0.85
    private static let documentLimit = 2

    private let diskQueue = LibraryThumbnailPipeline.makeQueue(name: "com.hmdalajmi.noor.library.thumbnails.disk")
    private let renderQueue = LibraryThumbnailPipeline.makeQueue(name: "com.hmdalajmi.noor.library.thumbnails.render")
    private let lock = NSLock()
    /// Most recently used last. Guarded by `lock`.
    private var documents: [(url: URL, document: PhotoDocument)] = []

    private static func makeQueue(name: String) -> OperationQueue {
        let queue = OperationQueue()
        queue.name = name
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }

    /// Produces the thumbnail in the background (disk cache first, else a render); `completion` runs
    /// on the job's thread.
    func load(_ request: LibraryThumbnailRequest, completion: @escaping @Sendable (UIImage?) -> Void) {
        diskQueue.addOperation { [self] in
            let fileURL = LibraryFiles.thumbnailURL(id: request.id, digest: request.digest)
            if let cached = autoreleasepool(invoking: { LibraryThumbnailPipeline.loadFromDisk(fileURL) }) {
                completion(cached)
                return
            }
            self.renderQueue.addOperation { [self] in
                let image = autoreleasepool { self.render(request, to: fileURL) }
                completion(image)
            }
        }
    }

    /// Releases the open documents (and their decoded thumbnail bases).
    func purgeDocuments() {
        lock.lock()
        documents.removeAll()
        lock.unlock()
    }

    /// Closes the document of a removed project.
    func forgetDocument(at url: URL) {
        lock.lock()
        documents.removeAll { $0.url == url }
        lock.unlock()
    }

    // MARK: Jobs

    /// Renders through the recipe and caches the JPEG at `fileURL`.
    private func render(_ request: LibraryThumbnailRequest, to fileURL: URL) -> UIImage? {
        // The project may have been removed while this job waited.
        guard FileManager.default.fileExists(atPath: request.originalURL.path(percentEncoded: false)),
              let document = openDocument(at: request.originalURL),
              let rendered = ThumbnailRenderer.render(document, recipe: request.recipe,
                                                      longEdge: LibraryThumbnailPipeline.longEdge)
        else { return nil }

        if let data = LibraryThumbnailPipeline.jpegData(rendered) {
            do {
                // The system may purge Caches while the app runs.
                try FileManager.default.createDirectory(at: LibraryFiles.thumbnailRoot,
                                                        withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
                LibraryFiles.removeThumbnails(id: request.id, keeping: fileURL.lastPathComponent)
            } catch {
                libraryLog.error("Could not cache thumbnail: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Already a decoded bitmap: ready to draw without a main-thread decode.
        return UIImage(cgImage: rendered)
    }

    private func openDocument(at url: URL) -> PhotoDocument? {
        lock.lock()
        if let index = documents.firstIndex(where: { $0.url == url }) {
            let entry = documents.remove(at: index)
            documents.append(entry)
            lock.unlock()
            return entry.document
        }
        lock.unlock()

        // Opening inspects metadata only; done outside the lock so other jobs are not blocked.
        guard let document = try? PhotoDocument(url: url) else { return nil }
        lock.lock()
        documents.append((url: url, document: document))
        if documents.count > LibraryThumbnailPipeline.documentLimit {
            documents.removeFirst(documents.count - LibraryThumbnailPipeline.documentLimit)
        }
        lock.unlock()
        return document
    }

    /// Decodes a cached JPEG off the main thread (`preparingForDisplay`) so scrolling never decodes.
    private static func loadFromDisk(_ url: URL) -> UIImage? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path), let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        return image.preparingForDisplay() ?? image
    }

    /// JPEG (quality 0.85) with the bitmap's Display P3 profile. Display only, never exported.
    private static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData,
                                                                 UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - File system

/// All library file-system work. Stateless and thread-agnostic: every function may run on any thread
/// (the store calls the slow ones from background tasks).
private enum LibraryFiles {
    static let projectFileName = "project.json"
    /// Bump to invalidate every cached thumbnail (e.g. after a rendering change).
    static let thumbnailFormatVersion = 1

    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
    }
    /// Project folders under construction (renamed into `root` when complete).
    static var stagingRoot: URL { root.appending(path: ".Staging", directoryHint: .isDirectory) }
    /// Project folders being deleted (renamed here first, so a removal is atomic).
    static var trashRoot: URL { root.appending(path: ".Trash", directoryHint: .isDirectory) }
    static var thumbnailRoot: URL {
        URL.cachesDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)
    }

    static func folderURL(id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    static func originalURL(id: UUID, fileName: String) -> URL {
        folderURL(id: id).appending(component: fileName, directoryHint: .notDirectory)
    }

    static func projectFileURL(id: UUID) -> URL {
        folderURL(id: id).appending(component: projectFileName, directoryHint: .notDirectory)
    }

    static func thumbnailURL(id: UUID, digest: String) -> URL {
        thumbnailRoot.appending(component: "\(id.uuidString)-\(digest).jpg", directoryHint: .notDirectory)
    }

    // MARK: Launch

    /// Creates the folders and discards leftovers of interrupted imports.
    static func prepareForLaunch() {
        let fm = FileManager.default
        try? fm.removeItem(at: stagingRoot)
        ImportedOriginal.purgeStaging()
        for folder in [root, stagingRoot, trashRoot, thumbnailRoot] {
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                libraryLog.error("Could not create \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reads every `<uuid>/project.json`. Folders that cannot be read are skipped (and kept on disk).
    static func loadProjects() -> [PhotoProject] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
        else { return [] }

        let decoder = JSONDecoder()
        var projects: [PhotoProject] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let file = folder.appending(component: projectFileName, directoryHint: .notDirectory)
            do {
                let data = try Data(contentsOf: file)
                var project = try decoder.decode(PhotoProject.self, from: data)
                project.id = id   // the folder name is the identity
                projects.append(project)
            } catch {
                libraryLog.error("Skipping project \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return projects.sorted(by: PhotoProject.libraryOrder)
    }

    /// Empties the trash and deletes thumbnails of projects that no longer exist.
    static func cleanUp(keepingThumbnailsOf ids: Set<UUID>) {
        let fm = FileManager.default
        if let trashed = try? fm.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil) {
            for item in trashed { try? fm.removeItem(at: item) }
        }
        if let files = try? fm.contentsOfDirectory(at: thumbnailRoot, includingPropertiesForKeys: nil) {
            for file in files {
                if let id = UUID(uuidString: String(file.lastPathComponent.prefix(36))), ids.contains(id) {
                    continue
                }
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: Projects

    static func encode(_ project: PhotoProject) throws -> Data {
        let encoder = JSONEncoder()
        // Dates keep their default (sub-millisecond) encoding: batch order depends on it.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    /// Inspects a staged original with `PhotoDocument` (refusing anything Noor cannot decode, e.g. a RAW
    /// camera this iOS version cannot develop), then moves it into a new project folder.
    static func makeProject(stagedFile: URL, fileName: String, declaredType: UTType?,
                            createdAt: Date) throws -> PhotoProject {
        let info = try PhotoDocument(url: stagedFile).info
        let storedName = libraryFileName(proposed: fileName, info: info, declaredType: declaredType,
                                         date: info.captureDate ?? createdAt)
        var typeIdentifier = info.typeIdentifier
        if typeIdentifier.isEmpty {
            typeIdentifier = UTType(filenameExtension: (storedName as NSString).pathExtension)?.identifier
                ?? declaredType?.identifier
                ?? UTType.image.identifier
        }

        let project = PhotoProject(id: UUID(),
                                   originalFileName: storedName,
                                   typeIdentifier: typeIdentifier,
                                   createdAt: createdAt,
                                   modifiedAt: createdAt,
                                   recipe: EditRecipe(),
                                   pixelWidth: Int(info.uprightSize.width.rounded()),
                                   pixelHeight: Int(info.uprightSize.height.rounded()),
                                   isRAW: info.isRAW,
                                   isHDR: info.isHDR,
                                   bitsPerComponent: info.bitsPerComponent)
        try publish(project) { folder in
            // Same volume: a rename, the bytes are not rewritten.
            try FileManager.default.moveItem(at: stagedFile,
                                             to: folder.appending(component: storedName, directoryHint: .notDirectory))
        }
        return project
    }

    /// A new project with a copy of `source`'s original and the same recipe.
    static func duplicate(_ source: PhotoProject, createdAt: Date, thumbnailDigest: String) throws -> PhotoProject {
        var clone = source
        clone.id = UUID()
        clone.createdAt = createdAt
        clone.modifiedAt = Date()
        let duplicate = clone
        let sourceOriginal = originalURL(id: source.id, fileName: source.originalFileName)
        try publish(duplicate) { folder in
            try FileManager.default.copyItem(at: sourceOriginal,
                                             to: folder.appending(component: duplicate.originalFileName,
                                                                  directoryHint: .notDirectory))
        }
        // Same original and recipe: reuse the cached thumbnail file if there is one.
        try? FileManager.default.copyItem(at: thumbnailURL(id: source.id, digest: thumbnailDigest),
                                          to: thumbnailURL(id: duplicate.id, digest: thumbnailDigest))
        return duplicate
    }

    /// Builds the project folder under `.Staging` (original + project.json) and renames it into the
    /// library, so a project is either complete or absent.
    private static func publish(_ project: PhotoProject, placeOriginal: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let staging = stagingRoot.appending(path: project.id.uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try placeOriginal(staging)
            try encode(project).write(to: staging.appending(component: projectFileName, directoryHint: .notDirectory),
                                      options: .atomic)
            try fm.moveItem(at: staging, to: folderURL(id: project.id))
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Moves the folder to the trash (atomic disappearance), deletes it, then its thumbnails.
    static func deleteProject(id: UUID) {
        let fm = FileManager.default
        let folder = folderURL(id: id)
        let trashed = trashRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? fm.removeItem(at: trashed)
        do {
            try fm.moveItem(at: folder, to: trashed)
            try fm.removeItem(at: trashed)
        } catch {
            try? fm.removeItem(at: folder)
        }
        removeThumbnails(id: id, keeping: nil)
    }

    // MARK: Names

    /// The name the original keeps inside its project folder: the name it had, made safe, with its
    /// extension. System-generated picker names (UUIDs, query strings) become `Noor_yyyyMMdd_HHmmss`.
    static func libraryFileName(proposed: String, info: SourceInfo, declaredType: UTType?, date: Date) -> String {
        var name = proposed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }

        var base = (name as NSString).deletingPathExtension
        var ext = (name as NSString).pathExtension
        if ext.isEmpty {
            ext = UTType(info.typeIdentifier)?.preferredFilenameExtension
                ?? declaredType?.preferredFilenameExtension
                ?? info.fileExtension
        }
        if base.isEmpty || looksGenerated(base) {
            base = "Noor_\(timestamp(date))"
        }
        if base.count > 120 {
            base = String(base.prefix(120))
        }
        let result = ext.isEmpty ? base : "\(base).\(ext)"
        return result.lowercased() == projectFileName ? "Original-\(result)" : result
    }

    private static func looksGenerated(_ base: String) -> Bool {
        if base.contains("=") || base.contains("&") { return true }
        return base.count >= 36 && UUID(uuidString: String(base.prefix(36))) != nil
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    // MARK: Thumbnails

    /// Stable across launches (unlike `hashValue`): FNV-1a 64 over the recipe's sorted-key JSON,
    /// salted with the thumbnail format and size.
    static func recipeDigest(_ recipe: EditRecipe) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var bytes = Array("noor-thumbnail-v\(thumbnailFormatVersion)-\(Int(LibraryThumbnailPipeline.longEdge))|".utf8)
        bytes.append(contentsOf: (try? encoder.encode(recipe)) ?? Data())
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }

    /// Deletes a project's cached thumbnails, except `kept` (a file name).
    static func removeThumbnails(id: UUID, keeping kept: String?) {
        let fm = FileManager.default
        let prefix = "\(id.uuidString)-"
        guard let files = try? fm.contentsOfDirectory(at: thumbnailRoot, includingPropertiesForKeys: nil) else { return }
        for file in files {
            let name = file.lastPathComponent
            if name.hasPrefix(prefix), name != kept {
                try? fm.removeItem(at: file)
            }
        }
    }

    static func clearThumbnails() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: thumbnailRoot, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fm.removeItem(at: file) }
    }

    // MARK: Size

    /// Allocated bytes of every regular file below `folder`.
    static func allocatedSize(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                              options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
