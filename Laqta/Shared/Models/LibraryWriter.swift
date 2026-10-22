//
//  LibraryWriter.swift
//  Laqta — Shared
//
//  The few ways the library changes. Every save moves its folder to the top.
//

import Foundation
import SwiftData

enum LibraryWriter {
    @discardableResult
    static func addMedia(
        _ staged: StagedMedia,
        to folder: Folder,
        deleteOriginal: Bool,
        preliminary: ShotAnalysis?,
        sourceName: String?,
        context: ModelContext
    ) throws -> Shot {
        let files = try MediaStore.commit(staged)
        let shot = Shot(staged: staged, files: files, folderID: folder.id)
        let canDeleteOriginal = staged.kind != .document
        shot.libraryStatus = deleteOriginal && canDeleteOriginal ? .pendingDeletion : .untouched
        shot.sourceName = sourceName
        if let preliminary {
            shot.store(preliminary, state: .pending)
        } else {
            shot.refreshIndex(nil)
        }
        context.insert(shot)
        folder.touch()
        noteChange()
        return shot
    }

    @discardableResult
    static func addLink(_ draft: LinkDraft, to folder: Folder, deep: Bool, context: ModelContext) -> Shot {
        var files: StoredFiles?
        if let image = draft.image {
            files = try? MediaStore.commit(image)
        }
        let shot = Shot(link: draft, files: files, folderID: folder.id)
        if draft.isYouTube {
            // YouTube details are shown as YouTube returns them; there is nothing more to extract.
            shot.store(YouTubeDetails.analysis(for: draft), state: .done)
            shot.deepAnalysis = true
            context.insert(shot)
            folder.touch()
            noteChange()
            return shot
        }
        shot.deepAnalysis = deep
        var analysis = ShotAnalysis()
        analysis.category = draft.form.label
        analysis.sections = draft.chapters
        analysis.sectionsTitle = draft.form.sectionsTitle
        analysis.places = draft.placeNames.map { PlaceRef(name: $0, origin: "Mentioned") }
        analysis.prices = draft.prices
        analysis.source = SourceRef(
            app: draft.sourceName ?? "Safari",
            headline: "Shared from \(draft.sourceName ?? "Safari")",
            detail: draft.site,
            url: draft.url.absoluteString,
            reason: nil
        )
        analysis.basis = basis(for: draft, deep: false)
        analysis.analyzedAt = .now
        shot.store(analysis, state: deep ? .pending : .shallow)
        context.insert(shot)
        folder.touch()
        noteChange()
        return shot
    }

    static func basis(for draft: LinkDraft, deep: Bool) -> String {
        switch draft.form {
        case .video:
            return draft.chapters.isEmpty ? "From the video's title and description" : "From the video's chapters and description"
        case .article:
            return deep ? "From the article text" : "From the article's title and summary"
        case .post:
            return "From the post's caption"
        case .product:
            return deep ? "From the product page" : "From the product's title and price"
        case .place, .page:
            return deep ? "From the page text" : "From the page title and description"
        }
    }

    static func move(_ items: [Shot], to folder: Folder) {
        for item in items {
            item.folderID = folder.id
        }
        folder.touch()
        noteChange()
    }

    /// `tone: nil` lets Laqta choose — a mood no other folder is wearing,
    /// leaning toward whatever the name means.
    static func createFolder(name: String, tone: FolderTone? = nil, symbol: String? = nil, locked: Bool, parentID: UUID? = nil, context: ModelContext) -> Folder {
        let chosen = tone ?? FolderPalette.pick(name: name, taken: tonesInUse(context))
        let folder = Folder(
            name: name,
            symbol: symbol ?? FolderSuggester.symbol(forName: name),
            tone: chosen,
            isLocked: locked
        )
        folder.parentID = parentID
        context.insert(folder)
        noteChange()
        return folder
    }

    /// Every mood currently on a folder, including ones in the Trash — a folder
    /// you recover should not come back wearing someone else's colour.
    static func tonesInUse(_ context: ModelContext) -> Set<FolderTone> {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        return Set(folders.map(\.tone))
    }

    static func snapshots(_ context: ModelContext) -> [FolderSnapshot] {
        LaqtaStore.foldersByUpdate(context).map {
            FolderSnapshot(id: $0.id, name: $0.name, isLocked: $0.isPrivate, lastUpdate: $0.lastUpdate)
        }
    }

    /// Automatic backups only run when something changed since the last one.
    static func noteChange() {
        AppGroup.defaults.set(Date.now.timeIntervalSince1970, forKey: SettingsKey.lastLibraryChange)
    }
}

/// Counts and cover for one folder, without loading every item.
nonisolated struct FolderStats: Sendable, Equatable {
    var photos: Int = 0
    var videos: Int = 0
    var documents: Int = 0
    var links: Int = 0
    var cover: CoverSource?
    var newestAdded: Date?

    var total: Int { photos + videos + documents + links }

    mutating func count(_ kind: ItemKind) {
        switch kind {
        case .photo: photos += 1
        case .video: videos += 1
        case .document: documents += 1
        case .link: links += 1
        }
    }

    /// "4 shots · 1 video · 2 links"
    var summary: String {
        LaqtaFormat.contents(self)
    }
}

enum FolderStatsLoader {
    static func stats(for folderID: UUID, context: ModelContext) -> FolderStats {
        var stats = FolderStats()
        let target: UUID? = folderID
        for kind in ItemKind.allCases {
            let raw: Int? = kind.rawValue
            let descriptor: FetchDescriptor<Shot>
            if kind == .photo {
                descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> {
                    $0.folderID == target && $0.deletedAt == nil && ($0.kindRaw == nil || $0.kindRaw == raw)
                })
            } else {
                descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> {
                    $0.folderID == target && $0.deletedAt == nil && $0.kindRaw == raw
                })
            }
            let count = (try? context.fetchCount(descriptor)) ?? 0
            switch kind {
            case .photo: stats.photos = count
            case .video: stats.videos = count
            case .document: stats.documents = count
            case .link: stats.links = count
            }
        }
        stats.cover = LaqtaStore.coverSource(in: folderID, context: context)
        stats.newestAdded = LaqtaStore.newestItem(in: folderID, context: context)?.addedAt
        return stats
    }

    /// Enough of a folder's newest items to find a good cover among them.
    static let coverDepth = 12

    /// Every folder's counts, cover and newest item, in ONE pass over the library.
    ///
    /// This used to ask six questions per folder — four counts, a cover and a newest —
    /// and the cover question alone materialised sixty shots. On a real library that is
    /// dozens of queries and hundreds of objects on the main thread before the Share
    /// Extension can draw anything, which is exactly how long it took to open. One
    /// sorted fetch answers all of it.
    static func stats(for folders: [Folder], context: ModelContext) -> [UUID: FolderStats] {
        guard !folders.isEmpty else { return [:] }
        var result: [UUID: FolderStats] = [:]
        var coverPool: [UUID: [Shot]] = [:]
        for folder in folders {
            result[folder.id] = FolderStats()
            coverPool[folder.id] = []
        }
        // Only the clause SwiftData is known to translate well; the folder is
        // checked in the loop, which costs nothing because we walk it anyway.
        var descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        // Only the columns the counts and the cover actually read. Without this the
        // share extension pulls every row whole — analysis blobs, OCR text, notes —
        // into a process with a hard memory limit, while the folder list is drawing.
        // Home has used exactly this list since it was written.
        descriptor.propertiesToFetch = [\.id, \.folderID, \.kindRaw, \.addedAt,
                                        \.thumbnailName, \.fileName, \.linkKey, \.linkURL]
        for shot in (try? context.fetch(descriptor)) ?? [] {
            guard let id = shot.folderID, result[id] != nil else { continue }
            result[id]?.count(shot.kind)
            // The fetch is newest first, so the first one seen is the newest.
            if result[id]?.newestAdded == nil { result[id]?.newestAdded = shot.addedAt }
            if (coverPool[id]?.count ?? 0) < coverDepth { coverPool[id]?.append(shot) }
        }
        for folder in folders {
            result[folder.id]?.cover = Shot.bestCover(in: coverPool[folder.id] ?? [])
        }
        return result
    }
}

/// The analysis stored with a YouTube link: the creator's chapters and where the details came from.
nonisolated enum YouTubeDetails {
    static func analysis(for draft: LinkDraft, previous: ShotAnalysis? = nil) -> ShotAnalysis {
        var analysis = ShotAnalysis()
        analysis.category = draft.form.label
        analysis.sections = draft.chapters
        analysis.sectionsTitle = draft.chapters.isEmpty ? nil : "Chapters"
        analysis.source = SourceRef(
            app: "YouTube",
            headline: previous?.source?.headline ?? "Saved from YouTube",
            detail: "youtube.com",
            url: draft.url.absoluteString,
            reason: nil
        )
        analysis.basis = draft.isUnavailable ? "This video is no longer available on YouTube" : "Details from YouTube"
        analysis.analyzedAt = .now
        return analysis
    }
}
