//
//  Models.swift
//  Laqta — Shared
//
//  SwiftData models: folders and the items saved in them (photos, videos, PDFs and links).
//  Fields added after 1.0 are optional so existing libraries migrate without loss,
//  and every field has a default so the library can sync with iCloud.
//

import Foundation
import SwiftData
import Synchronization

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "folder"
    /// v1 color; 2.0 reads it only to pick a cover mood for old folders.
    var colorKey: String = "gold"
    var sortIndex: Int = 0
    /// Private folders open with Face ID.
    var isLocked: Bool = false
    var createdAt: Date = Date.now

    // 2.0
    var updatedAt: Date?
    var toneRaw: String?

    // 2.1
    /// Set while the folder is in Recently Deleted.
    var deletedAt: Date?
    /// Items deleted together with the folder carry the same batch.
    var deletionBatch: UUID?
    /// How items are ordered inside the folder (`FolderSort`).
    var sortRaw: String?

    // 2.2
    /// The folder this one sits inside. `nil` for a folder on Home.
    var parentID: UUID?

    init(name: String, symbol: String, tone: FolderTone, isLocked: Bool = false) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorKey = "gold"
        self.sortIndex = 0
        self.isLocked = isLocked
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.toneRaw = tone.rawValue
    }

    /// Folders are listed by this date, newest first.
    var lastUpdate: Date { updatedAt ?? createdAt }

    var tone: FolderTone {
        get { toneRaw.flatMap { FolderTone(rawValue: $0) } ?? FolderTone.fromLegacy(colorKey) }
        set { toneRaw = newValue.rawValue }
    }

    var badgeSymbol: String { FolderSymbols.outline(symbol) }

    var isInTrash: Bool { deletedAt != nil }

    /// A subfolder inherits the privacy of every folder above it.
    @MainActor var isPrivate: Bool {
        if isLocked { return true }
        guard parentID != nil, let context = modelContext else { return false }
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        return LaqtaStore.path(to: id, in: folders).contains(where: \.isLocked)
    }

    var sort: FolderSort {
        get { sortRaw.flatMap { FolderSort(rawValue: $0) } ?? .newest }
        set { sortRaw = newValue == .newest ? nil : newValue.rawValue }
    }

    func touch(_ date: Date = .now) {
        updatedAt = date
    }
}

/// Where the original photo or video stands in the user's Photos library.
nonisolated enum LibraryStatus: Int, Sendable, CaseIterable {
    /// Deleting the original was off when the item was saved.
    case untouched = 0
    /// Waiting to delete the original from Photos.
    case pendingDeletion = 1
    /// The original was deleted from Photos.
    case deleted = 2
    /// The original could not be found in Photos.
    case notFound = 3
    /// The user kept the original.
    case declined = 4
}

nonisolated enum ItemKind: Int, Sendable, CaseIterable {
    case photo = 0
    case link = 1
    case video = 2
    case document = 3

    /// Order when a folder is grouped by kind.
    var groupOrder: Int {
        switch self {
        case .photo: 0
        case .video: 1
        case .document: 2
        case .link: 3
        }
    }

    var groupTitle: String {
        switch self {
        case .photo: "Photos"
        case .video: "Videos"
        case .document: "PDFs"
        case .link: "Links"
        }
    }

    var mediaKind: MediaKind? {
        switch self {
        case .photo: .photo
        case .video: .video
        case .document: .document
        case .link: nil
        }
    }
}

nonisolated enum AnalysisState: Int, Sendable {
    /// Waiting for the app to analyze it.
    case pending = 0
    case done = 2
    case failed = 3
    /// Link saved with its title and preview only.
    case shallow = 5
}

/// Quick filters in a folder.
nonisolated enum ItemTag: String, Sendable, CaseIterable {
    case place
    case text
    case link
    case video
    /// Has a date (Insights → Coming up).
    case date
    case document
    case note
}

/// How items are ordered inside a folder.
nonisolated enum FolderSort: String, Sendable, CaseIterable, Identifiable {
    /// Date added, newest first.
    case newest
    /// Date added, oldest first.
    case oldest
    /// When the photo or video was taken (or the link published), newest first.
    case taken
    /// Photos, videos, PDFs, then links.
    case kind
    /// A to Z.
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .taken: "Date Taken"
        case .kind: "Type"
        case .title: "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .taken: "camera"
        case .kind: "square.grid.2x2"
        case .title: "textformat"
        }
    }

    /// What `order` compares for one item.
    nonisolated struct Key: Sendable {
        var addedAt: Date
        var takenAt: Date?
        var kind: ItemKind
        var title: String
    }

    /// Stable ordering: ties fall back to the date added (newest first).
    func areInIncreasingOrder(_ lhs: Key, _ rhs: Key) -> Bool {
        switch self {
        case .newest:
            return lhs.addedAt > rhs.addedAt
        case .oldest:
            return lhs.addedAt < rhs.addedAt
        case .taken:
            let left = lhs.takenAt ?? lhs.addedAt
            let right = rhs.takenAt ?? rhs.addedAt
            return left != right ? left > right : lhs.addedAt > rhs.addedAt
        case .kind:
            if lhs.kind.groupOrder != rhs.kind.groupOrder { return lhs.kind.groupOrder < rhs.kind.groupOrder }
            return lhs.addedAt > rhs.addedAt
        case .title:
            let order = lhs.title.localizedStandardCompare(rhs.title)
            return order != .orderedSame ? order == .orderedAscending : lhs.addedAt > rhs.addedAt
        }
    }
}

@Model
final class Shot {
    var id: UUID = UUID()
    var folderID: UUID?
    /// Media file, or the link's preview image ("" when there is none).
    var fileName: String = ""
    var thumbnailName: String = ""
    var originalName: String?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var byteCount: Int = 0
    var capturedAt: Date?
    var captureOffsetKnown: Bool = false
    var addedAt: Date = Date.now
    /// A screenshot (photo) or a screen recording (video).
    var isScreenshot: Bool = false
    var isFavorite: Bool = false
    var note: String = ""
    /// `PHAsset.localIdentifier` when known (imports from the in-app picker).
    var sourceAssetID: String?
    var libraryStatusRaw: Int = 0

    // 2.0
    var kindRaw: Int?
    var linkURL: String?
    var linkTitle: String?
    var linkSite: String?
    var linkAuthor: String?
    var linkDuration: Double?
    var linkFormRaw: String?
    var linkDetails: String?
    var linkPublishedAt: Date?
    var linkViews: Int?
    /// The app or site the item came from ("Safari", "YouTube", "Camera").
    var sourceName: String?
    var deepAnalysis: Bool?
    var analysisStateRaw: Int?
    var analysisData: Data?
    var searchText: String?
    var tagsRaw: String?
    var viewedAt: Date?

    // 2.1
    /// Set while the item is in Recently Deleted.
    var deletedAt: Date?
    var deletionBatch: UUID?
    /// SHA-256 of the media file (duplicates and backups).
    var contentHash: String?
    /// The same capture in another encoding (see `DuplicateKey.capture`).
    var captureKey: String?
    /// The same link with different tracking parameters (see `DuplicateKey.link`).
    var linkKey: String?
    /// UTType identifier of the stored file.
    var mediaTypeRaw: String?
    var mediaDuration: Double?
    var hasAudio: Bool?
    var latitude: Double?
    var longitude: Double?
    var cameraModel: String?
    var documentTitle: String?
    var documentPages: Int?
    /// When the link's details were last read from the source (`nil` while a YouTube link waits for them).
    var linkRefreshedAt: Date?
    /// The media file was uploaded to iCloud, so other devices can download it.
    var mediaInCloud: Bool?
    var noteUpdatedAt: Date?
    /// Preview image loaded from the web instead of a stored file (YouTube thumbnails aren't stored).
    var linkImageURL: String?
    /// The linked video was removed or made private.
    var linkUnavailable: Bool?

    init(staged: StagedMedia, files: StoredFiles, folderID: UUID?) {
        let info = staged.info
        self.id = staged.id
        self.folderID = folderID
        self.fileName = files.fileName
        self.thumbnailName = files.thumbnailName
        self.originalName = staged.originalName
        self.pixelWidth = info.pixelWidth
        self.pixelHeight = info.pixelHeight
        self.byteCount = staged.byteCount
        self.capturedAt = info.capturedAt
        self.captureOffsetKnown = info.captureOffsetKnown
        self.addedAt = Date.now
        self.isScreenshot = info.isScreenCapture
        self.isFavorite = false
        self.note = ""
        self.sourceAssetID = staged.sourceAssetID
        self.libraryStatusRaw = LibraryStatus.untouched.rawValue
        self.kindRaw = info.kind.itemKind.rawValue
        self.analysisStateRaw = AnalysisState.pending.rawValue
        self.contentHash = staged.contentHash
        self.captureKey = staged.captureKey
        self.mediaTypeRaw = info.typeIdentifier
        self.mediaDuration = info.duration
        self.hasAudio = info.hasAudio
        self.latitude = info.latitude
        self.longitude = info.longitude
        self.cameraModel = info.cameraModel
        self.documentTitle = info.kind == .document ? info.title : nil
        self.documentPages = info.pageCount
    }

    init(link: LinkDraft, files: StoredFiles?, folderID: UUID?) {
        self.id = UUID()
        self.folderID = folderID
        self.fileName = files?.fileName ?? ""
        self.thumbnailName = files?.thumbnailName ?? ""
        self.originalName = nil
        self.pixelWidth = 0
        self.pixelHeight = 0
        self.byteCount = 0
        self.capturedAt = nil
        self.captureOffsetKnown = false
        self.addedAt = Date.now
        self.isScreenshot = false
        self.isFavorite = false
        self.note = ""
        self.sourceAssetID = nil
        self.libraryStatusRaw = LibraryStatus.untouched.rawValue
        self.kindRaw = ItemKind.link.rawValue
        self.linkURL = link.url.absoluteString
        self.linkTitle = link.title
        self.linkSite = link.site
        self.linkAuthor = link.author
        self.linkDuration = link.duration
        self.linkFormRaw = link.form.rawValue
        self.linkDetails = link.details
        self.linkPublishedAt = link.publishedAt
        self.linkViews = link.views
        self.sourceName = link.sourceName
        self.linkKey = DuplicateKey.link(for: link.url)
        // A YouTube link saved offline gets its details later.
        self.linkRefreshedAt = link.isYouTube && !link.hasYouTubeDetails && !link.isUnavailable ? nil : Date.now
        self.linkImageURL = link.imageURL
        self.linkUnavailable = link.isUnavailable ? true : nil
    }

    // MARK: Kind

    var kind: ItemKind { ItemKind(rawValue: kindRaw ?? 0) ?? .photo }
    var isLink: Bool { kind == .link }
    var isPhoto: Bool { kind == .photo }
    var isVideoFile: Bool { kind == .video }
    var isDocument: Bool { kind == .document }
    /// Photos and videos page together in the viewer.
    var isViewerMedia: Bool { kind == .photo || kind == .video }

    var linkForm: LinkForm { linkFormRaw.flatMap { LinkForm(rawValue: $0) } ?? .page }
    /// A YouTube link: its title, channel and thumbnail come from YouTube's oEmbed.
    var isYouTube: Bool {
        guard isLink else { return false }
        if linkKey?.hasPrefix("yt:") == true { return true }
        return url.map(YouTubeLink.isYouTube) ?? false
    }
    /// The preview image to load from the web, when none is stored.
    var remoteImageURL: URL? {
        guard isLink, thumbnailName.isEmpty, let linkImageURL, let url = URL(string: linkImageURL),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
    var hasPreviewImage: Bool { hasThumbnail || remoteImageURL != nil }
    var isLinkVideo: Bool { isLink && linkForm == .video }
    /// A saved video file or a link to a video.
    var isVideo: Bool { isVideoFile || isLinkVideo }
    var url: URL? { linkURL.flatMap { URL(string: $0) } }

    var isInTrash: Bool { deletedAt != nil }

    /// Length shown on cells: the video file's, or the linked video's.
    var playbackDuration: Double? {
        isVideoFile ? mediaDuration : (isLinkVideo ? linkDuration : nil)
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    // MARK: Files

    var hasMediaFile: Bool { !fileName.isEmpty }
    var hasThumbnail: Bool { !thumbnailName.isEmpty }
    var fileURL: URL { MediaLocation.fileURL(named: fileName) }
    var thumbnailURL: URL { AppGroup.thumbnailsURL.appending(path: thumbnailName.isEmpty ? "\(id.uuidString).jpg" : thumbnailName) }

    /// A file name people recognize when sharing ("IMG_1234.HEIC", "Invoice.pdf").
    var shareFileName: String {
        let ext = (fileName as NSString).pathExtension
        let base = (originalName?.isEmpty == false ? originalName : nil) ?? (isDocument ? documentTitle : nil) ?? displayTitle
        let cleaned = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let trimmed = String(cleaned.prefix(80))
        if ext.isEmpty || (trimmed as NSString).pathExtension.lowercased() == ext.lowercased() { return trimmed }
        return "\(trimmed).\(ext)"
    }

    var libraryStatus: LibraryStatus {
        get { LibraryStatus(rawValue: libraryStatusRaw) ?? .untouched }
        set { libraryStatusRaw = newValue.rawValue }
    }

    // MARK: Intelligence

    var analysisState: AnalysisState {
        get { AnalysisState(rawValue: analysisStateRaw ?? 0) ?? .pending }
        set { analysisStateRaw = newValue.rawValue }
    }

    var analysis: ShotAnalysis? {
        AnalysisCache.shared.analysis(for: id, data: analysisData)
    }

    var tags: Set<ItemTag> {
        Set((tagsRaw ?? "").split(separator: ",").compactMap { ItemTag(rawValue: String($0)) })
    }

    func store(_ analysis: ShotAnalysis, state: AnalysisState) {
        analysisData = try? JSONEncoder().encode(analysis)
        analysisState = state
        refreshIndex(analysis)
    }

    /// Rebuilds the tags and search text (after an analysis or a note change).
    func refreshIndex(_ analysis: ShotAnalysis? = nil) {
        let analysis = analysis ?? self.analysis
        var tags: [ItemTag] = []
        if let analysis {
            if analysis.place != nil || !analysis.places.isEmpty || hasLocation { tags.append(.place) }
            if !isLink, (analysis.text?.count ?? 0) >= 12 { tags.append(.text) }
            if analysis.entities.contains(where: { $0.kind == .date }) { tags.append(.date) }
        } else if hasLocation {
            tags.append(.place)
        }
        if isLink { tags.append(.link) }
        if isVideo { tags.append(.video) }
        if isDocument { tags.append(.document) }
        if !note.isEmpty { tags.append(.note) }
        tagsRaw = tags.map(\.rawValue).joined(separator: ",")
        searchText = SearchIndex.text(for: self, analysis: analysis)
    }

    func setNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != note else { return }
        note = trimmed
        noteUpdatedAt = .now
        refreshIndex()
    }

    /// Title shown in lists, search and the Intelligence sheet.
    var displayTitle: String {
        switch kind {
        case .link:
            if let title = linkTitle, !title.isEmpty { return title }
            if isYouTube { return linkUnavailable == true ? "Unavailable YouTube video" : "YouTube video" }
            return linkSite ?? "Link"
        case .document:
            if let title = documentTitle, !title.isEmpty { return title }
            if let title = analysis?.title, !title.isEmpty { return title }
            if let name = originalName, !name.isEmpty { return name }
            return "PDF"
        case .photo, .video:
            if let title = analysis?.title, !title.isEmpty { return title }
            return kindLabel
        }
    }

    var kindLabel: String {
        switch kind {
        case .link: linkForm.label
        case .photo: isScreenshot ? "Screenshot" : "Photo"
        case .video: isScreenshot ? "Screen Recording" : "Video"
        case .document: "PDF"
        }
    }

    var kindSymbol: String {
        switch kind {
        case .link: linkForm.systemImage
        case .photo: isScreenshot ? "camera.viewfinder" : "photo"
        case .video: isScreenshot ? "record.circle" : "video"
        case .document: "doc.richtext"
        }
    }

    /// Items stay "New" until opened, for a day.
    var isNew: Bool {
        viewedAt == nil && Date.now.timeIntervalSince(addedAt) < 86_400
    }

    var sortKey: FolderSort.Key {
        FolderSort.Key(
            addedAt: addedAt,
            takenAt: capturedAt ?? linkPublishedAt,
            kind: kind,
            title: displayTitle
        )
    }

    var fingerprint: AssetFingerprint {
        AssetFingerprint(
            shotID: id,
            knownAssetID: sourceAssetID,
            originalName: originalName,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            capturedAt: capturedAt,
            captureOffsetKnown: captureOffsetKnown,
            isScreenshot: isScreenshot,
            addedAt: addedAt,
            isVideo: isVideoFile,
            duration: mediaDuration
        )
    }

    /// What a folder cover is blurred from. YouTube thumbnails are never altered, so they are skipped.
    var coverSource: CoverSource? {
        guard !isYouTube, hasThumbnail || hasMediaFile else { return nil }
        return CoverSource(id: id, thumbnailURL: thumbnailURL, originalURL: isPhoto && hasMediaFile ? fileURL : nil)
    }

    /// Photos and videos make the best covers, then link previews; PDF pages (mostly white) come last.
    var coverPriority: Int {
        switch kind {
        case .photo, .video: 0
        case .link: 1
        case .document: 2
        }
    }

    /// The cover for items listed newest first: the newest photo or video, else the newest
    /// link preview, else the newest PDF.
    static func bestCover(in newestFirst: some Sequence<Shot>) -> CoverSource? {
        var best: (priority: Int, source: CoverSource)?
        for item in newestFirst {
            let priority = item.coverPriority
            if let best, best.priority <= priority { continue }
            guard let source = item.coverSource else { continue }
            best = (priority, source)
            if priority == 0 { break }
        }
        return best?.source
    }
}

/// Everything needed to find the original photo or video again in the Photos library.
nonisolated struct AssetFingerprint: Sendable {
    let shotID: UUID
    let knownAssetID: String?
    let originalName: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let capturedAt: Date?
    let captureOffsetKnown: Bool
    let isScreenshot: Bool
    let addedAt: Date
    var isVideo: Bool = false
    var duration: Double? = nil
}

/// Decoded analyses, reused while the stored JSON is unchanged.
nonisolated final class AnalysisCache: Sendable {
    static let shared = AnalysisCache()

    private struct Entry: Sendable {
        let data: Data
        let value: ShotAnalysis
    }

    /// Past this, a quarter is dropped. A library bigger than the cache must not make
    /// the cache useless.
    private static let capacity = 4_000

    private let entries = Mutex<[UUID: Entry]>([:])

    func analysis(for id: UUID, data: Data?) -> ShotAnalysis? {
        guard let data else { return nil }
        if let cached = entries.withLock({ $0[id] }), cached.data == data {
            return cached.value
        }
        guard let value = try? JSONDecoder().decode(ShotAnalysis.self, from: data) else { return nil }
        entries.withLock { store in
            // Clearing the whole cache was the bug: one sequential walk over a library
            // past the limit emptied it mid-walk, and every pass after that was 100%
            // misses, for good. Dropping a quarter keeps most of the hits.
            if store.count >= Self.capacity {
                for key in Array(store.keys.prefix(Self.capacity / 4)) { store[key] = nil }
            }
            store[id] = Entry(data: data, value: value)
        }
        return value
    }
}

// MARK: - Container

enum LaqtaStore {
    static let schema = Schema([Folder.self, Shot.self])

    static func makeContainer(cloudSync: Bool = false, inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration("Laqta", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        try AppGroup.prepareDirectories()
        let database: ModelConfiguration.CloudKitDatabase = cloudSync ? .private(CloudConfig.containerIdentifier) : .none
        let configuration = ModelConfiguration(
            "Laqta",
            schema: schema,
            url: AppGroup.storeURL,
            allowsSave: true,
            cloudKitDatabase: database
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: A library that won't open

    /// Where a library that wouldn't open is kept.
    ///
    /// Nothing is deleted. A store SwiftData refuses today can still be readable by a
    /// later build, by a Mac, or by hand — and it is the only copy of everything the
    /// last backup doesn't have.
    static var damagedURL: URL {
        AppGroup.rootURL.appending(path: "Damaged", directoryHint: .isDirectory)
    }

    /// The library and the files SQLite keeps beside it.
    static var libraryFileURLs: [URL] {
        let store = AppGroup.storeURL
        let folder = store.deletingLastPathComponent()
        return ["", "-wal", "-shm"].map { folder.appending(path: store.lastPathComponent + $0) }
    }

    /// Moves the library aside so a new, empty one can open in its place.
    /// Returns the folder it was moved to.
    @discardableResult
    static func setDamagedLibraryAside(now: Date = .now) throws -> URL {
        let manager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = damagedURL.appending(path: "Laqta-\(formatter.string(from: now))", directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var moved = false
        for url in libraryFileURLs where manager.fileExists(atPath: url.path(percentEncoded: false)) {
            try manager.moveItem(at: url, to: folder.appending(path: url.lastPathComponent))
            moved = true
        }
        guard moved else {
            try? manager.removeItem(at: folder)
            // Nothing to move: the library is missing rather than damaged, and opening
            // it again makes a new one anyway.
            throw CocoaError(.fileNoSuchFile)
        }
        return folder
    }

    /// First launch folders.
    static func seedIfNeeded(_ context: ModelContext) {
        let defaults = AppGroup.defaults
        guard !defaults.bool(forKey: SettingsKey.didSeedFolders) else {
            upgradeIfNeeded(context)
            return
        }
        let existing = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? 0
        if existing == 0 {
            let now = Date.now
            for (index, seed) in SeedFolder.all.enumerated() {
                let folder = Folder(name: seed.name, symbol: seed.symbol, tone: seed.tone, isLocked: seed.locked)
                folder.id = seed.id
                folder.updatedAt = now.addingTimeInterval(Double(-index) * 60)
                context.insert(folder)
            }
            // Marking the library seeded after a save that didn't happen left it empty
            // for good: the flag only goes down once the folders are really stored.
            guard context.commit(.setUp) else { return }
        }
        defaults.set(true, forKey: SettingsKey.didSeedFolders)
        defaults.set(true, forKey: SettingsKey.didUpgradeTo2)
        defaults.set(true, forKey: SettingsKey.didUpgradeTo21)
        defaults.set(true, forKey: SettingsKey.didCheckModelPlaces)
    }

    /// Brings older libraries up to date.
    static func upgradeIfNeeded(_ context: ModelContext) {
        let defaults = AppGroup.defaults
        if !defaults.bool(forKey: SettingsKey.didUpgradeTo2) {
            let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
            for folder in folders {
                if folder.updatedAt == nil {
                    folder.updatedAt = newestItem(in: folder.id, context: context)?.addedAt ?? folder.createdAt
                }
                if folder.toneRaw == nil {
                    folder.toneRaw = FolderTone.fromLegacy(folder.colorKey).rawValue
                }
                folder.symbol = FolderSymbols.outline(folder.symbol)
            }
            guard context.commit(.setUp) else { return }
            defaults.set(true, forKey: SettingsKey.didUpgradeTo2)
        }
        if !defaults.bool(forKey: SettingsKey.didUpgradeTo21) {
            // Link keys power duplicate detection; hashes are filled in by the app later.
            let linkKind: Int? = ItemKind.link.rawValue
            let links = (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.kindRaw == linkKind && $0.linkKey == nil }))) ?? []
            for link in links {
                if let url = link.url { link.linkKey = DuplicateKey.link(for: url) }
            }
            guard context.commit(.setUp) else { return }
            defaults.set(true, forKey: SettingsKey.didUpgradeTo21)
        }
        if !defaults.bool(forKey: SettingsKey.didCheckModelPlaces) {
            // Earlier builds let the language model name a place or title for a photo with
            // nothing in it to back that up. Those photos are analyzed again.
            let photoKind: Int? = ItemKind.photo.rawValue
            let done: Int? = AnalysisState.done.rawValue
            let photos = (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate<Shot> {
                $0.kindRaw == photoKind && $0.analysisStateRaw == done
            }))) ?? []
            for photo in photos {
                if let analysis = photo.analysis, hasUngroundedInsight(analysis) {
                    photo.analysisState = .pending
                }
            }
            guard context.commit(.setUp) else { return }
            defaults.set(true, forKey: SettingsKey.didCheckModelPlaces)
        }
    }

    /// A photo analysis whose model-written place or title isn't backed by the image.
    static func hasUngroundedInsight(_ analysis: ShotAnalysis) -> Bool {
        guard analysis.usedLanguageModel else { return false }
        let text = analysis.text ?? ""
        if let place = analysis.place, place.origin == "From text", place.category != "Address",
           !PlaceGrounding.isMentioned(place.name, in: text) {
            return true
        }
        return text.isEmpty && analysis.labels.isEmpty && analysis.entities.isEmpty && analysis.place == nil
    }

    static func folder(with id: UUID, context: ModelContext) -> Folder? {
        let target = id
        var descriptor = FetchDescriptor<Folder>(predicate: #Predicate<Folder> { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func item(with id: UUID, context: ModelContext) -> Shot? {
        let target = id
        var descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func items(withIDs ids: [UUID], context: ModelContext) -> [Shot] {
        guard !ids.isEmpty else { return [] }
        let wanted = ids
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { wanted.contains($0.id) })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Items in a folder that are not in Recently Deleted, newest first.
    static func items(in folderID: UUID, context: ModelContext) -> [Shot] {
        let target: UUID? = folderID
        let descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.folderID == target && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The item a folder cover is made from (see `Shot.bestCover(in:)`).
    static func coverSource(in folderID: UUID, context: ModelContext) -> CoverSource? {
        let target: UUID? = folderID
        var descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.folderID == target && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return Shot.bestCover(in: (try? context.fetch(descriptor)) ?? [])
    }

    static func newestItem(in folderID: UUID, context: ModelContext) -> Shot? {
        let target: UUID? = folderID
        var descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.folderID == target && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func itemCount(in folderID: UUID, context: ModelContext) -> Int {
        let target: UUID? = folderID
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.folderID == target && $0.deletedAt == nil })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Folders that are not in Recently Deleted, most recently updated first.
    static func foldersByUpdate(_ context: ModelContext) -> [Folder] {
        let descriptor = FetchDescriptor<Folder>(predicate: #Predicate<Folder> { $0.deletedAt == nil })
        let folders = (try? context.fetch(descriptor)) ?? []
        return folders.sorted { $0.lastUpdate > $1.lastUpdate }
    }

    /// Folders sitting directly inside `parent` — pass `nil` for the ones on Home.
    static func folders(inside parent: UUID?, context: ModelContext) -> [Folder] {
        foldersByUpdate(context).filter { $0.parentID == parent }
    }

    /// How many folders sit directly inside each folder.
    static func subfolderCounts(_ folders: [Folder]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for folder in folders where folder.deletedAt == nil {
            guard let parent = folder.parentID else { continue }
            result[parent, default: 0] += 1
        }
        return result
    }

    /// Every folder under this one, at any depth (deepest last).
    static func descendants(of folderID: UUID, in folders: [Folder]) -> [Folder] {
        var byParent: [UUID: [Folder]] = [:]
        for folder in folders {
            guard let parent = folder.parentID else { continue }
            byParent[parent, default: []].append(folder)
        }
        var result: [Folder] = []
        var queue = byParent[folderID] ?? []
        // A cycle would only come from damaged data; the seen set makes it harmless.
        var seen: Set<UUID> = [folderID]
        while let next = queue.first {
            queue.removeFirst()
            guard seen.insert(next.id).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: byParent[next.id] ?? [])
        }
        return result
    }

    static func descendants(of folderID: UUID, context: ModelContext) -> [Folder] {
        descendants(of: folderID, in: (try? context.fetch(FetchDescriptor<Folder>())) ?? [])
    }

    /// The folders from Home down to this one, this one last.
    static func path(to folderID: UUID, in folders: [Folder]) -> [Folder] {
        var byID: [UUID: Folder] = [:]
        for folder in folders { byID[folder.id] = folder }
        var result: [Folder] = []
        var current = byID[folderID]
        var seen: Set<UUID> = []
        while let folder = current, seen.insert(folder.id).inserted {
            result.insert(folder, at: 0)
            current = folder.parentID.flatMap { byID[$0] }
        }
        return result
    }

    /// True when moving `folder` inside `target` would make a loop.
    static func wouldLoop(moving folderID: UUID, into target: UUID?, folders: [Folder]) -> Bool {
        guard let target else { return false }
        if target == folderID { return true }
        return descendants(of: folderID, in: folders).contains { $0.id == target }
    }

    /// Items that are not in Recently Deleted and whose folder isn't either.
    static var liveItemsPredicate: Predicate<Shot> {
        #Predicate<Shot> { $0.deletedAt == nil }
    }
}

/// The folders a new library starts with. Fixed IDs keep them from doubling up
/// when two devices set up the same library and sync.
nonisolated struct SeedFolder: Sendable {
    let id: UUID
    let name: String
    let symbol: String
    let tone: FolderTone
    let locked: Bool

    static let all: [SeedFolder] = [
        SeedFolder(id: UUID(uuidString: "7A0C3C1E-2B1A-4F7B-9E51-0A1C2D3E4F01")!, name: "Travel", symbol: "airplane", tone: .ember, locked: false),
        SeedFolder(id: UUID(uuidString: "7A0C3C1E-2B1A-4F7B-9E51-0A1C2D3E4F02")!, name: "Perfume", symbol: "drop", tone: .olive, locked: false),
        SeedFolder(id: UUID(uuidString: "7A0C3C1E-2B1A-4F7B-9E51-0A1C2D3E4F03")!, name: "Cities", symbol: "building.2", tone: .tide, locked: false),
        SeedFolder(id: UUID(uuidString: "7A0C3C1E-2B1A-4F7B-9E51-0A1C2D3E4F04")!, name: "Private", symbol: "lock", tone: .dusk, locked: true)
    ]
}
