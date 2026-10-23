//
//  LibraryModel.swift
//  Laqta
//
//  Library actions: move, favorite, notes, Recently Deleted, and removing originals from Photos.
//

import Foundation
import Observation
import Photos
import SwiftData

@Observable
final class LibraryModel {
    /// Items stay in Recently Deleted for this long.
    static let trashRetention: TimeInterval = 30 * 86_400

    /// Changes when the Share Extension (or iCloud) edited the library while the app was in the background.
    private(set) var refreshToken = UUID()
    private(set) var isCleaningPhotos = false
    var lastCleanupMessage: String?
    /// Originals Laqta believes it found but isn't sure about. The sheet shows each
    /// one next to Laqta's own copy, and the user decides.
    private(set) var originalsToConfirm: [OriginalToConfirm] = []
    /// True once the user has asked for the cleanup themselves — a sheet full of
    /// photos is an answer to a question they asked, not something to meet on launch.
    private(set) var wantsOriginalsConfirmation = false
    /// Folder that just moved to the top (gold sweep on Home).
    private(set) var highlightedFolderID: UUID?
    /// Bumps when Recently Deleted changes, so counts refresh.
    private(set) var trashVersion = 0

    @ObservationIgnored private var lastSeenExternalChange: Double = AppGroup.lastExternalChange

    var autoDeleteEnabled: Bool {
        AppGroup.bool(SettingsKey.autoDeleteFromPhotos)
    }

    func checkForExternalChanges(context: ModelContext) {
        let stamp = AppGroup.lastExternalChange
        guard stamp != lastSeenExternalChange else { return }
        lastSeenExternalChange = stamp
        if let id = AppGroup.defaults.string(forKey: SettingsKey.lastUsedFolderID).flatMap(UUID.init(uuidString:)) {
            highlight(id)
        }
        refreshToken = UUID()
    }

    /// Redraws lists after changes that arrived from iCloud.
    func refresh() {
        refreshToken = UUID()
    }

    func highlight(_ folderID: UUID) {
        highlightedFolderID = folderID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.highlightedFolderID == folderID {
                self?.highlightedFolderID = nil
            }
        }
    }

    func noteLocalSave(to folderID: UUID) {
        lastSeenExternalChange = AppGroup.lastExternalChange
        highlight(folderID)
    }

    // MARK: Editing

    func move(_ items: [Shot], to folder: Folder, context: ModelContext) {
        let ids = items.map(\.id)
        let folderID = folder.id
        LibraryWriter.move(items, to: folder)
        guard context.commit(.move, retry: { [weak self] in
            guard let self, let folder = LaqtaStore.folder(with: folderID, context: context) else { return }
            self.move(LaqtaStore.items(withIDs: ids, context: context), to: folder, context: context)
        }) else { return }
        highlight(folder.id)
    }

    func toggleFavorite(_ item: Shot, context: ModelContext) {
        item.isFavorite.toggle()
        // The rollback puts the old value back, so doing it again means the same thing.
        guard context.commit(.favorite, retry: { [weak self] in
            self?.toggleFavorite(item, context: context)
        }) else { return }
        LibraryWriter.noteChange()
    }

    func markViewed(_ item: Shot, context: ModelContext) {
        guard item.viewedAt == nil else { return }
        item.viewedAt = .now
        // Deliberately no save(). The main context autosaves, and saving here fires on
        // every swipe through an unseen folder — each one refetching every live @Query
        // in the stack and queueing a CloudKit export. A first-view stamp is not worth
        // that, and losing one is harmless.
    }

    func setNote(_ text: String, for item: Shot, context: ModelContext) {
        item.setNote(text)
        guard context.commit(.note, retry: { [weak self] in
            self?.setNote(text, for: item, context: context)
        }) else { return }
        LibraryWriter.noteChange()
    }

    func setSort(_ sort: FolderSort, for folder: Folder, context: ModelContext) {
        guard folder.sort != sort else { return }
        folder.sort = sort
        context.commit(.sort, retry: { [weak self] in
            self?.setSort(sort, for: folder, context: context)
        })
    }

    // MARK: Recently Deleted

    /// Moves items to Recently Deleted. Photos is not touched.
    func trash(_ items: [Shot], context: ModelContext) {
        let live = items.filter { $0.deletedAt == nil }
        guard !live.isEmpty else { return }
        let batch = UUID()
        let now = Date.now
        for item in live {
            item.deletedAt = now
            item.deletionBatch = batch
        }
        let ids = live.map(\.id)
        guard context.commit(.trash, retry: { [weak self] in
            self?.trash(LaqtaStore.items(withIDs: ids, context: context), context: context)
        }) else { return }
        LibraryWriter.noteChange()
        trashVersion += 1
    }

    /// Moves a folder and everything in it to Recently Deleted.
    /// A folder goes to Recently Deleted with its items and everything nested inside it.
    func trash(folder: Folder, context: ModelContext) {
        guard folder.deletedAt == nil else { return }
        let batch = UUID()
        let now = Date.now
        for target in [folder] + LaqtaStore.descendants(of: folder.id, context: context) {
            guard target.deletedAt == nil else { continue }
            target.deletedAt = now
            target.deletionBatch = batch
            for item in LaqtaStore.items(in: target.id, context: context) {
                item.deletedAt = now
                item.deletionBatch = batch
            }
        }
        let folderID = folder.id
        guard context.commit(.trash, retry: { [weak self] in
            guard let self, let folder = LaqtaStore.folder(with: folderID, context: context) else { return }
            self.trash(folder: folder, context: context)
        }) else { return }
        LibraryWriter.noteChange()
        trashVersion += 1
    }

    /// Puts items back. A deleted folder comes back with them (without its other items).
    func restore(_ items: [Shot], context: ModelContext) {
        guard !items.isEmpty else { return }
        var folders: Set<UUID> = []
        for item in items {
            item.deletedAt = nil
            item.deletionBatch = nil
            if let folderID = item.folderID { folders.insert(folderID) }
        }
        for folderID in folders {
            guard let folder = LaqtaStore.folder(with: folderID, context: context) else { continue }
            if folder.deletedAt != nil {
                folder.deletedAt = nil
                folder.deletionBatch = nil
            }
            folder.touch()
        }
        let ids = items.map(\.id)
        guard context.commit(.restore, retry: { [weak self] in
            self?.restore(LaqtaStore.items(withIDs: ids, context: context), context: context)
        }) else { return }
        LibraryWriter.noteChange()
        trashVersion += 1
        if let first = folders.first { highlight(first) }
    }

    /// Puts a folder back with the items and folders that were deleted together with it.
    func restore(folder: Folder, context: ModelContext) {
        let batch = folder.deletionBatch
        let everyFolder = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        var coming = [folder]
        if batch != nil {
            coming += LaqtaStore.descendants(of: folder.id, in: everyFolder).filter { $0.deletionBatch == batch }
        }
        for restored in coming {
            let target: UUID? = restored.id
            let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.folderID == target && $0.deletedAt != nil })
            for item in (try? context.fetch(descriptor)) ?? [] where batch != nil && item.deletionBatch == batch {
                item.deletedAt = nil
                item.deletionBatch = nil
            }
            restored.deletedAt = nil
            restored.deletionBatch = nil
        }
        // A folder whose parent was deleted for good comes back to Home rather than nowhere.
        if let parent = folder.parentID,
           everyFolder.first(where: { $0.id == parent && $0.deletedAt == nil }) == nil {
            folder.parentID = nil
        }
        folder.touch()
        let folderID = folder.id
        guard context.commit(.restore, retry: { [weak self] in
            guard let self, let folder = LaqtaStore.folder(with: folderID, context: context) else { return }
            self.restore(folder: folder, context: context)
        }) else { return }
        LibraryWriter.noteChange()
        trashVersion += 1
        highlight(folder.id)
    }

    /// Removes items and their files for good.
    func deletePermanently(_ items: [Shot], context: ModelContext) {
        let files = items.map { StoredFiles(fileName: $0.fileName, thumbnailName: $0.thumbnailName) }
        let ids = items.map(\.id)
        for item in items {
            context.delete(item)
        }
        guard commitDeletion(files: files, operation: .delete, context: context, retry: { [weak self] in
            self?.deletePermanently(LaqtaStore.items(withIDs: ids, context: context), context: context)
        }) else { return }
        LibraryWriter.noteChange()
        trashVersion += 1
    }

    /// Removes a deleted folder, and everything still inside it, for good.
    ///
    /// Only what is actually in the trash goes. A live item can be sitting in a folder
    /// that another device trashed before that item's save arrived, and deleting the
    /// folder must not take it along — so a folder that still holds something live is
    /// not empty, and is left where it is. That is the guard `emptyTrash` and the
    /// 30-day purge already use.
    func deletePermanently(folder: Folder, context: ModelContext) {
        var files: [StoredFiles] = []
        for gone in [folder] + LaqtaStore.descendants(of: folder.id, context: context) {
            let target: UUID? = gone.id
            let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.folderID == target })
            var holdsSomethingLive = false
            for item in (try? context.fetch(descriptor)) ?? [] {
                guard item.deletedAt != nil else { holdsSomethingLive = true; continue }
                files.append(StoredFiles(fileName: item.fileName, thumbnailName: item.thumbnailName))
                context.delete(item)
            }
            if !holdsSomethingLive { context.delete(gone) }
        }
        let folderID = folder.id
        guard commitDeletion(files: files, operation: .delete, context: context, retry: { [weak self] in
            guard let self, let folder = LaqtaStore.folder(with: folderID, context: context) else { return }
            self.deletePermanently(folder: folder, context: context)
        }) else { return }
        LibraryWriter.noteChange()
        trashVersion += 1
    }

    func emptyTrash(context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.deletedAt != nil }))) ?? []
        let files = items.map { StoredFiles(fileName: $0.fileName, thumbnailName: $0.thumbnailName) }
        for item in items {
            context.delete(item)
        }
        let folders = (try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate<Folder> { $0.deletedAt != nil }))) ?? []
        for folder in folders {
            let target: UUID? = folder.id
            let remaining = (try? context.fetchCount(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.folderID == target }))) ?? 0
            if remaining == 0 { context.delete(folder) }
        }
        guard commitDeletion(files: files, operation: .emptyTrash, context: context, retry: { [weak self] in
            self?.emptyTrash(context: context)
        }) else { return }
        LibraryWriter.noteChange()
        trashVersion += 1
    }

    /// Deletes what has been in Recently Deleted for more than 30 days.
    @discardableResult
    func purgeExpiredTrash(context: ModelContext, now: Date = .now) -> Int {
        let cutoff = now.addingTimeInterval(-Self.trashRetention)
        let expired = (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { item in
            item.deletedAt.flatMap { $0 < cutoff } ?? false
        }))) ?? []
        let files = expired.map { StoredFiles(fileName: $0.fileName, thumbnailName: $0.thumbnailName) }
        for item in expired {
            context.delete(item)
        }
        let folders = (try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate<Folder> { folder in
            folder.deletedAt.flatMap { $0 < cutoff } ?? false
        }))) ?? []
        var removedFolders = 0
        for folder in folders {
            let target: UUID? = folder.id
            let remaining = (try? context.fetchCount(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.folderID == target }))) ?? 0
            if remaining == 0 {
                context.delete(folder)
                removedFolders += 1
            }
        }
        if !expired.isEmpty || removedFolders > 0 {
            // No retry: the next launch, or the next six hours, comes back to it anyway.
            guard commitDeletion(files: files, operation: .purge, context: context, retry: nil) else { return 0 }
            trashVersion += 1
        }
        AppGroup.defaults.set(now.timeIntervalSince1970, forKey: SettingsKey.lastPurgeAt)
        return expired.count
    }

    func trashCount(context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.deletedAt != nil }))) ?? 0
    }

    /// The user says this is the original: the item takes the asset's identifier, so
    /// from now on it is known rather than guessed, and the deletion goes ahead.
    func confirmOriginal(_ candidate: OriginalToConfirm, context: ModelContext) async {
        originalsToConfirm.removeAll { $0.id == candidate.id }
        if originalsToConfirm.isEmpty { wantsOriginalsConfirmation = false }
        guard let item = LaqtaStore.item(with: candidate.id, context: context) else { return }
        item.sourceAssetID = candidate.assetID
        item.libraryStatus = .pendingDeletion
        guard context.commit(.photoCleanup) else { return }
        await runPhotoCleanup(context: context, userInitiated: true)
    }

    /// The user says it isn't: the original stays, and Laqta stops asking.
    func keepOriginal(_ candidate: OriginalToConfirm, context: ModelContext) {
        originalsToConfirm.removeAll { $0.id == candidate.id }
        if originalsToConfirm.isEmpty { wantsOriginalsConfirmation = false }
        guard let item = LaqtaStore.item(with: candidate.id, context: context) else { return }
        item.libraryStatus = .declined
        context.commit(.photoCleanup)
    }

    func dismissOriginalsToConfirm() {
        wantsOriginalsConfirmation = false
    }

    private func commitDeletion(
        files: [StoredFiles],
        operation: SaveOperation,
        context: ModelContext,
        retry: (@MainActor () -> Void)?
    ) -> Bool {
        guard context.commit(operation, retry: retry) else { return false }
        // Bytes are deleted only after the record deletion is durable. A duplicate
        // CloudKit record may still reference the same file, so retain that copy.
        guard let remaining = try? context.fetch(FetchDescriptor<Shot>()) else { return true }
        let mediaInUse = Set(remaining.map(\.fileName))
        let thumbnailsInUse = Set(remaining.map(\.thumbnailName))
        for files in files {
            let fileName = mediaInUse.contains(files.fileName) ? "" : files.fileName
            let thumbnailName = thumbnailsInUse.contains(files.thumbnailName) ? "" : files.thumbnailName
            MediaStore.deleteStoredFiles(fileName: fileName, thumbnailName: thumbnailName)
            CloudMediaStore.deleteFiles(fileName: fileName, thumbnailName: thumbnailName)
        }
        return true
    }

    // MARK: Photos library

    /// A guessed original, waiting to be looked at.
    nonisolated struct OriginalToConfirm: Identifiable, Sendable, Equatable {
        /// The item in Laqta.
        let id: UUID
        /// The asset in Photos the guess points at.
        let assetID: String
    }

    func pendingDeletionCount(context: ModelContext) -> Int {
        let pending = LibraryStatus.pendingDeletion.rawValue
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.libraryStatusRaw == pending && $0.deletedAt == nil })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Photos and videos kept in Photos although Laqta has a copy.
    func originalsStillInPhotos(context: ModelContext) async -> [UUID] {
        guard PhotoLibraryService.canModifyLibrary else { return [] }
        let untouched = LibraryStatus.untouched.rawValue
        let declined = LibraryStatus.declined.rawValue
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { item in
            (item.libraryStatusRaw == untouched || item.libraryStatusRaw == declined) && item.deletedAt == nil
        })
        let candidates = ((try? context.fetch(descriptor)) ?? []).filter(\.isViewerMedia).prefix(200)
        let matches = await PhotoLibraryService.resolve(candidates.map(\.fingerprint))
        return Array(matches.keys)
    }

    func queueForDeletion(_ ids: [UUID], context: ModelContext) async {
        for item in LaqtaStore.items(withIDs: ids, context: context) {
            item.libraryStatus = .pendingDeletion
        }
        guard context.commit(.photoCleanup, retry: { [weak self] in
            Task { await self?.queueForDeletion(ids, context: context) }
        }) else { return }
        await runPhotoCleanup(context: context, userInitiated: true)
    }

    /// Deletes originals that are still waiting, with a single system confirmation.
    func runPhotoCleanup(context: ModelContext, userInitiated: Bool = false) async {
        guard !isCleaningPhotos else { return }
        let pendingRaw = LibraryStatus.pendingDeletion.rawValue
        // Items in Recently Deleted keep their originals, so nothing is lost in both places.
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.libraryStatusRaw == pendingRaw && $0.deletedAt == nil })
        guard let fetched = try? context.fetch(descriptor), !fetched.isEmpty else {
            if userInitiated { lastCleanupMessage = "Nothing is waiting to be deleted." }
            return
        }
        let pending = fetched.filter { $0.isViewerMedia && $0.hasMediaFile && CloudFiles.exists($0.fileURL) }
        guard !pending.isEmpty else {
            if userInitiated { lastCleanupMessage = "The saved copies aren't available. Restore or download them before deleting the originals from Photos." }
            return
        }
        guard PhotoLibraryService.canModifyLibrary else {
            if userInitiated {
                let status = await PhotoLibraryService.requestAccess()
                if status == .authorized || status == .limited {
                    await runPhotoCleanup(context: context, userInitiated: true)
                } else {
                    lastCleanupMessage = "Allow Laqta to access Photos first."
                }
            }
            return
        }

        isCleaningPhotos = true
        defer { isCleaningPhotos = false }

        let matches = await PhotoLibraryService.resolve(pending.map(\.fingerprint))
        let now = Date.now
        for shot in pending where matches[shot.id] == nil {
            // Screenshots shared from the markup editor may never reach the library.
            if now.timeIntervalSince(shot.addedAt) > 3 * 86_400 || userInitiated {
                shot.libraryStatus = .notFound
            }
        }

        // Only an original Laqta can name — one whose asset identifier the item itself
        // carries — is deleted here. The rest were worked out from a file name, a pixel
        // size and a capture time, and a photo is not something to delete on a guess.
        let sure = pending.filter { matches[$0.id]?.isExact == true }
        let guesses = pending.filter { matches[$0.id]?.isExact == false }
        originalsToConfirm = guesses.compactMap { shot in
            matches[shot.id].map { OriginalToConfirm(id: shot.id, assetID: $0.identifier) }
        }
        if userInitiated, !originalsToConfirm.isEmpty { wantsOriginalsConfirmation = true }
        let identifiers = Array(Set(sure.compactMap { matches[$0.id]?.identifier }))
        guard !identifiers.isEmpty else {
            // Nothing was deleted from Photos, so a failed save here loses only a
            // "not in Photos any more" note that the next pass writes again.
            context.commit(.photoCleanup)
            if userInitiated {
                lastCleanupMessage = originalsToConfirm.isEmpty
                    ? String(localized: "The originals are no longer in Photos.")
                    : String(localized: "Laqta found photos that look like the originals. Check them before anything is deleted.")
            }
            return
        }

        do {
            try await PhotoLibraryService.deleteAssets(withIdentifiers: identifiers)
            for shot in sure {
                shot.libraryStatus = .deleted
            }
            if userInitiated {
                lastCleanupMessage = identifiers.count == 1
                    ? String(localized: "1 original moved to Recently Deleted in Photos.")
                    : String(localized: "\(identifiers.count) originals moved to Recently Deleted in Photos.")
            }
        } catch {
            DebugLog.write("app: delete failed \(error)")
            if PhotoLibraryService.isUserCancellation(error) {
                for shot in sure {
                    shot.libraryStatus = .declined
                }
                if userInitiated { lastCleanupMessage = String(localized: "Kept. The originals stay in Photos.") }
            } else if userInitiated {
                lastCleanupMessage = String(localized: "Photos couldn't delete the originals: \(error.localizedDescription)")
            }
        }
        // The originals are already gone from Photos: this save is the only record of
        // it, so its failure has to be said out loud rather than swallowed.
        context.commit(.photoCleanup)
    }
}
