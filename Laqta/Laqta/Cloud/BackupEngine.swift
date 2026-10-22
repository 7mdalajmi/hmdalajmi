//
//  BackupEngine.swift
//  Laqta
//
//  iCloud backups: each backup is a small manifest; media files are kept once in a
//  shared pool, so a new backup only uploads what changed. Also exports a single-file
//  backup and restores from either kind, adding what's missing without replacing anything.
//

import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum BackupPlace {
    static var root: URL? { CloudContainer.backupsURL }
    static var snapshots: URL? { root?.appending(path: "Snapshots", directoryHint: .isDirectory) }
    static var media: URL? { root?.appending(path: "Media", directoryHint: .isDirectory) }
    static var thumbnails: URL? { root?.appending(path: "Thumbnails", directoryHint: .isDirectory) }

    static func manifestURL(id: String) -> URL? { snapshots?.appending(path: "\(id).json") }
    static func infoURL(id: String) -> URL? { snapshots?.appending(path: "\(id).info.json") }
}

nonisolated struct BackupDevice: Sendable {
    let id: String
    let name: String

    @MainActor
    static var current: BackupDevice {
        #if os(macOS)
        let key = "backupMacDeviceID"
        let stored = AppGroup.defaults.string(forKey: key)
        let id = stored ?? UUID().uuidString
        if stored == nil { AppGroup.defaults.set(id, forKey: key) }
        return BackupDevice(id: id, name: Host.current().localizedName ?? "Mac")
        #else
        let device = UIDevice.current
        let id = device.identifierForVendor?.uuidString ?? "unknown"
        return BackupDevice(id: id, name: device.model)
        #endif
    }
}

/// Where a restore reads from.
nonisolated struct PreparedRestore: Sendable {
    let manifest: BackupManifest
    let mediaFolder: URL
    let thumbnailsFolder: URL
    /// Files can be moved instead of copied (an extracted file backup).
    let canMoveFiles: Bool
    /// Removed when the restore ends.
    let temporaryFolder: URL?
}

nonisolated struct RestoreSummary: Sendable, Equatable {
    var addedItems = 0
    var addedFolders = 0
    var recoveredItems = 0
    var recoveredFolders = 0
    var alreadyThere = 0
    var missingFiles = 0

    var message: String {
        var parts: [String] = []
        let added = addedItems + recoveredItems
        if added > 0 { parts.append("Added \(LaqtaFormat.count(added, "item", "items"))") }
        let folders = addedFolders + recoveredFolders
        if folders > 0 { parts.append(LaqtaFormat.count(folders, "folder", "folders")) }
        if parts.isEmpty { parts.append("Everything in this backup is already in Laqta") }
        var text = parts.joined(separator: " and ") + "."
        if alreadyThere > 0, added > 0 {
            text += " \(LaqtaFormat.count(alreadyThere, "item was", "items were")) already in Laqta."
        }
        if missingFiles > 0 {
            text += " \(LaqtaFormat.count(missingFiles, "item", "items")) couldn't be restored because the file is missing."
        }
        return text
    }
}

nonisolated enum BackupEngine {
    typealias Progress = @Sendable (Double, String) -> Void

    // MARK: iCloud backups

    /// Writes a new iCloud backup. Only files the pool doesn't have yet are uploaded.
    @concurrent
    static func backUp(_ snapshot: LibrarySnapshot, info: BackupInfo, keep: Int, progress: Progress) async throws -> BackupInfo {
        guard CloudContainer.rootURL != nil,
              let root = BackupPlace.root, let snapshots = BackupPlace.snapshots,
              let mediaPool = BackupPlace.media, let thumbnailPool = BackupPlace.thumbnails else {
            throw BackupError.iCloudUnavailable
        }
        guard !snapshot.items.isEmpty || !snapshot.folders.isEmpty else { throw BackupError.nothingToBackUp }
        guard snapshot.items.allSatisfy({ $0.kindRaw == ItemKind.link.rawValue || $0.hasMedia }) else {
            throw BackupError.mediaUnavailable
        }
        for folder in [root, snapshots, mediaPool, thumbnailPool] {
            try CloudFiles.createDirectory(folder)
        }
        let existingMedia = CloudFiles.names(in: mediaPool)
        let existingThumbnails = CloudFiles.names(in: thumbnailPool)

        var items = snapshot.items
        var bytes: Int64 = 0
        let total = max(items.count, 1)
        for index in items.indices {
            try Task.checkCancellation()
            let record = items[index]
            if record.hasMedia {
                if !existingMedia.contains(record.fileName) {
                    if let source = snapshot.mediaSources[record.fileName], CloudFiles.isAvailable(source) {
                        do {
                            try CloudFiles.copy(from: source, to: mediaPool.appending(path: record.fileName))
                        } catch {
                            DebugLog.write("backup: copy failed \(record.fileName) \(error)")
                            items[index].hasMedia = false
                        }
                    } else {
                        // Still downloading from iCloud on this device.
                        items[index].hasMedia = false
                    }
                }
                if !items[index].hasMedia, record.kindRaw != ItemKind.link.rawValue {
                    throw BackupError.mediaUnavailable
                }
                if items[index].hasMedia { bytes += Int64(record.byteCount) }
            }
            if record.hasThumbnail, !existingThumbnails.contains(record.thumbnailName) {
                if let source = snapshot.thumbnailSources[record.thumbnailName], CloudFiles.isAvailable(source) {
                    do {
                        try CloudFiles.copy(from: source, to: thumbnailPool.appending(path: record.thumbnailName))
                    } catch {
                        items[index].hasThumbnail = false
                    }
                } else {
                    items[index].hasThumbnail = false
                }
            }
            if index % 5 == 0 || index == items.count - 1 {
                progress(Double(index + 1) / Double(total) * 0.95, "Backing up \(LaqtaFormat.number(index + 1)) of \(LaqtaFormat.number(items.count))")
            }
        }

        var finished = info
        finished.folderCount = snapshot.folders.count
        finished.itemCount = items.count
        finished.mediaBytes = bytes
        let manifest = BackupManifest(info: finished, folders: snapshot.folders, items: items)
        guard let manifestURL = BackupPlace.manifestURL(id: finished.id), let infoURL = BackupPlace.infoURL(id: finished.id) else {
            throw BackupError.iCloudUnavailable
        }
        progress(0.97, "Saving the backup")
        try CloudFiles.write(try manifest.encoded(), to: manifestURL)
        // The small info file is written last: a backup is listed only once it's complete.
        try CloudFiles.write(try BackupManifest.encoder().encode(finished), to: infoURL)
        prune(keep: keep, deviceID: finished.deviceID)
        progress(1, "Backed up")
        return finished
    }

    /// Backups in iCloud from every device, newest first.
    @concurrent
    static func list() async -> (backups: [BackupInfo], waiting: Int) {
        guard let snapshots = BackupPlace.snapshots else { return ([], 0) }
        let names = CloudFiles.names(in: snapshots).filter { $0.hasSuffix(".info.json") }
        var backups: [BackupInfo] = []
        var waiting = 0
        for name in names {
            let url = snapshots.appending(path: name)
            if !CloudFiles.isAvailable(url) {
                guard await CloudFiles.waitUntilAvailable(url, timeout: .seconds(8)) else {
                    waiting += 1
                    continue
                }
            }
            if let data = try? CloudFiles.read(url), let info = try? BackupManifest.decoder().decode(BackupInfo.self, from: data) {
                backups.append(info)
            }
        }
        return (backups.sorted { $0.createdAt > $1.createdAt }, waiting)
    }

    @concurrent
    static func delete(id: String) async {
        if let info = BackupPlace.infoURL(id: id) { CloudFiles.coordinatedDelete(info) }
        if let manifest = BackupPlace.manifestURL(id: id) { CloudFiles.coordinatedDelete(manifest) }
        prune(keep: .max, deviceID: nil)
    }

    /// Keeps the newest `keep` backups of this device, then removes pool files no backup uses.
    static func prune(keep: Int, deviceID: String?) {
        guard let snapshots = BackupPlace.snapshots, let mediaPool = BackupPlace.media,
              let thumbnailPool = BackupPlace.thumbnails else { return }
        let decoder = BackupManifest.decoder()
        var infos: [BackupInfo] = []
        for name in CloudFiles.names(in: snapshots) where name.hasSuffix(".info.json") {
            let url = snapshots.appending(path: name)
            guard CloudFiles.isAvailable(url), let data = try? Data(contentsOf: url),
                  let info = try? decoder.decode(BackupInfo.self, from: data) else {
                // A backup that isn't downloaded may be using pool files: don't clean up this time.
                return
            }
            infos.append(info)
        }
        if let deviceID {
            let mine = infos.filter { $0.deviceID == deviceID }.sorted { $0.createdAt > $1.createdAt }
            for old in mine.dropFirst(max(1, keep)) {
                if let url = BackupPlace.infoURL(id: old.id) { CloudFiles.coordinatedDelete(url) }
                if let url = BackupPlace.manifestURL(id: old.id) { CloudFiles.coordinatedDelete(url) }
                infos.removeAll { $0.id == old.id }
            }
        }
        var usedMedia = Set<String>()
        var usedThumbnails = Set<String>()
        for info in infos {
            guard let url = BackupPlace.manifestURL(id: info.id), CloudFiles.isAvailable(url),
                  let data = try? Data(contentsOf: url), let manifest = try? BackupManifest.decode(data) else {
                return
            }
            let names = manifest.fileNames
            usedMedia.formUnion(names.media)
            usedThumbnails.formUnion(names.thumbnails)
        }
        // Files younger than a day may belong to a backup still being written on another device.
        let cutoff = Date.now.addingTimeInterval(-86_400)
        removeUnused(in: mediaPool, keeping: usedMedia, olderThan: cutoff)
        removeUnused(in: thumbnailPool, keeping: usedThumbnails, olderThan: cutoff)
    }

    private static func removeUnused(in folder: URL, keeping used: Set<String>, olderThan cutoff: Date) {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        for entry in entries {
            let fileName = entry.lastPathComponent
            let name = CloudFiles.realName(fromPlaceholder: fileName) ?? fileName
            guard !name.hasPrefix("."), !used.contains(name) else { continue }
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            guard modified < cutoff else { continue }
            CloudFiles.coordinatedDelete(folder.appending(path: name))
        }
    }

    @concurrent
    static func iCloudUsage() async -> Int64 {
        guard let root = BackupPlace.root else { return 0 }
        return CloudFiles.size(of: root)
    }

    @concurrent
    static func prepareRestore(fromICloud info: BackupInfo) async throws -> PreparedRestore {
        guard let manifestURL = BackupPlace.manifestURL(id: info.id),
              let media = BackupPlace.media, let thumbnails = BackupPlace.thumbnails else {
            throw BackupError.iCloudUnavailable
        }
        guard await CloudFiles.waitUntilAvailable(manifestURL, timeout: .seconds(120)) else {
            throw BackupError.iCloudUnavailable
        }
        let manifest = try BackupManifest.decode(try CloudFiles.read(manifestURL))
        return PreparedRestore(manifest: manifest, mediaFolder: media, thumbnailsFolder: thumbnails, canMoveFiles: false, temporaryFolder: nil)
    }

    // MARK: Single-file backups

    static var exportFolder: URL {
        URL.temporaryDirectory.appending(path: "LaqtaBackupExports", directoryHint: .isDirectory)
    }

    /// Writes a single-file backup and returns its URL (in a temporary folder).
    @concurrent
    static func export(_ snapshot: LibrarySnapshot, info: BackupInfo, progress: Progress) async throws -> URL {
        let manager = FileManager.default
        try? manager.removeItem(at: exportFolder)
        let folder = exportFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? manager.removeItem(at: folder) } }
        guard snapshot.items.allSatisfy({ $0.kindRaw == ItemKind.link.rawValue || $0.hasMedia }) else {
            throw BackupError.mediaUnavailable
        }

        var items = snapshot.items
        var entries: [BackupArchive.Entry] = []
        var bytes: Int64 = 0
        var seenMedia = Set<String>()
        var seenThumbnails = Set<String>()
        for index in items.indices {
            try Task.checkCancellation()
            let record = items[index]
            if record.hasMedia {
                if let source = snapshot.mediaSources[record.fileName], CloudFiles.isAvailable(source) {
                    if seenMedia.insert(record.fileName).inserted {
                        entries.append(.init(path: "Media/\(record.fileName)", source: source))
                        bytes += Int64(record.byteCount)
                    }
                } else {
                    guard record.kindRaw == ItemKind.link.rawValue else { throw BackupError.mediaUnavailable }
                    items[index].hasMedia = false
                }
            }
            if record.hasThumbnail {
                if let source = snapshot.thumbnailSources[record.thumbnailName], CloudFiles.isAvailable(source) {
                    if seenThumbnails.insert(record.thumbnailName).inserted {
                        entries.append(.init(path: "Thumbnails/\(record.thumbnailName)", source: source))
                    }
                } else {
                    items[index].hasThumbnail = false
                }
            }
        }
        try MediaStore.ensureSpace(for: bytes + 20 * 1024 * 1024)

        var finished = info
        finished.folderCount = snapshot.folders.count
        finished.itemCount = items.count
        finished.mediaBytes = bytes
        let manifest = BackupManifest(info: finished, folders: snapshot.folders, items: items)
        let manifestURL = folder.appending(path: BackupArchive.manifestPath)
        try manifest.encoded().write(to: manifestURL, options: .atomic)
        entries.insert(.init(path: BackupArchive.manifestPath, source: manifestURL), at: 0)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let archive = folder.appending(path: "Laqta Backup \(formatter.string(from: info.createdAt)).laqtabackup")
        let totalBytes = max(bytes, 1)
        try BackupArchive.write(entries: entries, to: archive, isCancelled: { Task.isCancelled }) { written in
            progress(min(0.99, Double(written) / Double(totalBytes)), "Preparing \(LaqtaFormat.bytes(written)) of \(LaqtaFormat.bytes(totalBytes))")
        }
        try? manager.removeItem(at: manifestURL)
        progress(1, "Ready")
        completed = true
        return archive
    }

    static func cleanUpExports() {
        try? FileManager.default.removeItem(at: exportFolder)
    }

    /// Reads a single-file backup the user picked.
    @concurrent
    static func prepareRestore(fromFile url: URL, progress: Progress) async throws -> PreparedRestore {
        let manager = FileManager.default
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        try AppGroup.prepareDirectories()
        let folder = AppGroup.stagingURL.appending(path: "Restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            // A file in iCloud Drive or another provider may need downloading first.
            var coordinationError: NSError?
            var result: Result<Void, any Error> = .success(())
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            try MediaStore.ensureSpace(for: size)
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
                result = Result {
                    _ = try BackupArchive.extract(readURL, to: folder, isCancelled: { Task.isCancelled }) { done in
                        progress(min(0.5, Double(done) / Double(max(size, 1)) * 0.5), "Reading the backup")
                    }
                }
            }
            if let coordinationError { throw coordinationError }
            try result.get()
            let manifestURL = folder.appending(path: BackupArchive.manifestPath)
            guard manager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else { throw BackupError.notABackup }
            let manifest = try BackupManifest.decode(try Data(contentsOf: manifestURL))
            return PreparedRestore(
                manifest: manifest,
                mediaFolder: folder.appending(path: "Media", directoryHint: .isDirectory),
                thumbnailsFolder: folder.appending(path: "Thumbnails", directoryHint: .isDirectory),
                canMoveFiles: true,
                temporaryFolder: folder
            )
        } catch {
            try? manager.removeItem(at: folder)
            if error is DecodingError { throw BackupError.damaged }
            throw error
        }
    }

    /// Copies (or moves) one file from a backup into the library.
    @concurrent
    static func bring(_ name: String, from folder: URL, to destinationFolder: URL, move: Bool) async -> Bool {
        // The name comes out of the backup's own manifest, and a `.laqtabackup` is a
        // file anyone can write and send — the app is its declared Owner, one Restore
        // tap away. Anything but a plain file name could resolve outside Media/:
        // "../Laqta.store" would make a later delete remove the live database.
        guard MediaStore.isPlainFileName(name) else { return false }
        let manager = FileManager.default
        let destination = destinationFolder.appending(path: name)
        if manager.fileExists(atPath: destination.path(percentEncoded: false)) { return true }
        let source = folder.appending(path: name)
        if move {
            guard manager.fileExists(atPath: source.path(percentEncoded: false)) else { return false }
            return (try? manager.moveItem(at: source, to: destination)) != nil
        }
        guard CloudFiles.exists(source) else { return false }
        if !CloudFiles.isAvailable(source) {
            guard await CloudFiles.waitUntilAvailable(source, timeout: .seconds(300)) else { return false }
        }
        return (try? CloudFiles.copy(from: source, to: destination)) != nil
    }

    static func finish(_ prepared: PreparedRestore) {
        if let folder = prepared.temporaryFolder {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

// MARK: - Restoring into the library

enum BackupRestorer {
    /// Adds what the backup has and the library doesn't. Nothing is replaced or deleted;
    /// items and folders waiting in Recently Deleted are recovered.
    static func restore(
        _ prepared: PreparedRestore,
        context: ModelContext,
        progress: (Double, String) -> Void
    ) async throws -> RestoreSummary {
        var summary = RestoreSummary()
        let manifest = prepared.manifest
        try AppGroup.prepareDirectories()
        let neededBytes = prepared.canMoveFiles ? 0 : manifest.items.reduce(Int64(0)) { $0 + ($1.hasMedia ? Int64($1.byteCount) : 0) }
        try MediaStore.ensureSpace(for: neededBytes)

        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        var foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in manifest.folders {
            if let existing = foldersByID[record.id] {
                if existing.deletedAt != nil {
                    existing.deletedAt = nil
                    existing.deletionBatch = nil
                    existing.touch()
                    summary.recoveredFolders += 1
                }
            } else {
                let folder = LibrarySnapshotter.makeFolder(from: record)
                context.insert(folder)
                foldersByID[record.id] = folder
                summary.addedFolders += 1
            }
        }

        let items = (try? context.fetch(FetchDescriptor<Shot>())) ?? []
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var fallbackFolder: Folder?
        let total = max(manifest.items.count, 1)
        for (index, record) in manifest.items.enumerated() {
            if Task.isCancelled {
                // What is already restored is kept; a failure here puts it back.
                try? context.commit()
                throw BackupError.cancelled
            }
            defer {
                if index % 10 == 0 || index == manifest.items.count - 1 {
                    progress(0.5 + Double(index + 1) / Double(total) * 0.5, "Restoring \(LaqtaFormat.number(index + 1)) of \(LaqtaFormat.number(manifest.items.count))")
                }
            }
            if let existing = itemsByID[record.id] {
                if existing.deletedAt != nil {
                    existing.deletedAt = nil
                    existing.deletionBatch = nil
                    summary.recoveredItems += 1
                } else {
                    summary.alreadyThere += 1
                }
                continue
            }
            let isLink = record.kindRaw == ItemKind.link.rawValue
            var fileName = ""
            if record.hasMedia {
                if await BackupEngine.bring(record.fileName, from: prepared.mediaFolder, to: AppGroup.mediaURL, move: prepared.canMoveFiles) {
                    fileName = record.fileName
                } else if !isLink {
                    summary.missingFiles += 1
                    continue
                }
            } else if !isLink {
                // A photo, video or PDF without its file can't be shown.
                summary.missingFiles += 1
                continue
            }
            var thumbnailName = ""
            if record.hasThumbnail,
               await BackupEngine.bring(record.thumbnailName, from: prepared.thumbnailsFolder, to: AppGroup.thumbnailsURL, move: prepared.canMoveFiles) {
                thumbnailName = record.thumbnailName
            }
            var itemRecord = record
            if itemRecord.folderID.flatMap({ foldersByID[$0] }) == nil {
                if fallbackFolder == nil {
                    let folder = LibraryWriter.createFolder(name: "Restored", tone: .tide, symbol: "arrow.counterclockwise", locked: false, context: context)
                    fallbackFolder = folder
                    foldersByID[folder.id] = folder
                    summary.addedFolders += 1
                }
                itemRecord.folderID = fallbackFolder?.id
            }
            let item = LibrarySnapshotter.makeItem(from: itemRecord, fileName: fileName, thumbnailName: thumbnailName)
            context.insert(item)
            summary.addedItems += 1
            if summary.addedItems % 50 == 0 {
                // A batch that can't be stored stops the restore with the real reason,
                // instead of counting items that were never written.
                try context.commit()
            }
        }
        try context.commit()
        LibraryWriter.noteChange()
        BackupEngine.finish(prepared)
        return summary
    }
}
