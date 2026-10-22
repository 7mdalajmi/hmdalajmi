//
//  BackupFormat.swift
//  Laqta
//
//  What a Laqta backup contains: a library manifest (folders, items, notes, analysis)
//  and the media files. YouTube thumbnails are shown from YouTube, so they aren't copied.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    /// A single-file Laqta backup ("Laqta Backup 2026-09-17.laqtabackup").
    nonisolated static let laqtaBackup = UTType(exportedAs: "Hmdalajmi.Laqta.backup", conformingTo: .data)
}

nonisolated struct BackupInfo: Codable, Sendable, Hashable, Identifiable {
    static let currentFormat = 1

    var id: String
    var format: Int
    var createdAt: Date
    var appVersion: String
    var deviceName: String
    /// Each device keeps its own number of backups.
    var deviceID: String
    var folderCount: Int
    var itemCount: Int
    var mediaBytes: Int64

    static func makeID(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "\(formatter.string(from: date))-\(UUID().uuidString.prefix(6))"
    }
}

nonisolated struct FolderRecord: Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    var colorKey: String
    var sortIndex: Int
    var isLocked: Bool
    var createdAt: Date
    var updatedAt: Date?
    var toneRaw: String?
    var sortRaw: String?
    /// 2.2 — the folder this one sits inside. Older backups have none.
    var parentID: UUID?
}

nonisolated struct ItemRecord: Codable, Sendable, Hashable {
    var id: UUID
    var folderID: UUID?
    var fileName: String
    var thumbnailName: String
    var originalName: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int
    var capturedAt: Date?
    var captureOffsetKnown: Bool
    var addedAt: Date
    var isScreenshot: Bool
    var isFavorite: Bool
    var note: String
    var sourceAssetID: String?
    var libraryStatusRaw: Int
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
    var sourceName: String?
    var deepAnalysis: Bool?
    var analysisStateRaw: Int?
    var analysisData: Data?
    var viewedAt: Date?
    var contentHash: String?
    var captureKey: String?
    var linkKey: String?
    var mediaTypeRaw: String?
    var mediaDuration: Double?
    var hasAudio: Bool?
    var latitude: Double?
    var longitude: Double?
    var cameraModel: String?
    var documentTitle: String?
    var documentPages: Int?
    var linkRefreshedAt: Date?
    var noteUpdatedAt: Date?
    var linkImageURL: String?
    /// The media file is in the backup.
    var hasMedia: Bool
    /// The thumbnail is in the backup.
    var hasThumbnail: Bool
}

nonisolated struct BackupManifest: Codable, Sendable {
    var info: BackupInfo
    var folders: [FolderRecord]
    var items: [ItemRecord]

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    static func decode(_ data: Data) throws -> BackupManifest {
        let manifest = try decoder().decode(BackupManifest.self, from: data)
        guard manifest.info.format <= BackupInfo.currentFormat else {
            throw BackupError.newerFormat
        }
        guard manifest.info.format > 0,
              Set(manifest.folders.map(\.id)).count == manifest.folders.count,
              Set(manifest.items.map(\.id)).count == manifest.items.count,
              manifest.items.allSatisfy({ item in
                  item.byteCount >= 0 && item.pixelWidth >= 0 && item.pixelHeight >= 0
                      && !item.pixelWidth.multipliedReportingOverflow(by: item.pixelHeight).overflow
                      && (item.fileName.isEmpty || MediaStore.isPlainFileName(item.fileName))
                      && (item.thumbnailName.isEmpty || MediaStore.isPlainFileName(item.thumbnailName))
                      && (!item.hasMedia || !item.fileName.isEmpty)
                      && (!item.hasThumbnail || !item.thumbnailName.isEmpty)
              }) else { throw BackupError.damaged }
        var totalBytes: Int64 = 0
        for item in manifest.items {
            let sum = totalBytes.addingReportingOverflow(Int64(item.byteCount))
            guard !sum.overflow else { throw BackupError.damaged }
            totalBytes = sum.partialValue
        }
        return manifest
    }

    /// Media and thumbnail file names the backup needs.
    var fileNames: (media: Set<String>, thumbnails: Set<String>) {
        var media = Set<String>()
        var thumbnails = Set<String>()
        for item in items {
            if item.hasMedia, !item.fileName.isEmpty { media.insert(item.fileName) }
            if item.hasThumbnail, !item.thumbnailName.isEmpty { thumbnails.insert(item.thumbnailName) }
        }
        return (media, thumbnails)
    }
}

nonisolated enum BackupError: LocalizedError, Equatable {
    case iCloudUnavailable
    case notABackup
    case newerFormat
    case damaged
    case notEnoughSpace
    case cancelled
    case nothingToBackUp
    case mediaUnavailable

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: "iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive for Laqta."
        case .notABackup: "This file isn't a Laqta backup."
        case .newerFormat: "This backup was made by a newer version of Laqta. Update Laqta, then try again."
        case .damaged: "This backup is incomplete or damaged."
        case .notEnoughSpace: "There isn't enough free space on this device."
        case .cancelled: "Stopped."
        case .nothingToBackUp: "There's nothing to back up yet."
        case .mediaUnavailable: "Some original files aren't available on this device yet. Download them from iCloud, then try backing up again. Your earlier backups are kept."
        }
    }
}

// MARK: - Snapshot of the library

/// A copy of the library taken on the main actor, then written elsewhere.
nonisolated struct LibrarySnapshot: Sendable {
    var folders: [FolderRecord]
    var items: [ItemRecord]

    /// Where each item's files are now.
    var mediaSources: [String: URL]
    var thumbnailSources: [String: URL]
}

enum LibrarySnapshotter {
    /// Everything that isn't in Recently Deleted.
    static func snapshot(context: ModelContext) -> LibrarySnapshot {
        let folders = LaqtaStore.foldersByUpdate(context)
        let liveFolderIDs = Set(folders.map(\.id))
        let descriptor = FetchDescriptor<Shot>(
            predicate: #Predicate<Shot> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt)]
        )
        let items = ((try? context.fetch(descriptor)) ?? []).filter { item in
            item.folderID.map(liveFolderIDs.contains) ?? true
        }
        var mediaSources: [String: URL] = [:]
        var thumbnailSources: [String: URL] = [:]
        var records: [ItemRecord] = []
        records.reserveCapacity(items.count)
        for item in items {
            let keepsFiles = !item.isYouTube
            if keepsFiles, item.hasMediaFile {
                mediaSources[item.fileName] = item.fileURL
            }
            if keepsFiles, item.hasThumbnail {
                thumbnailSources[item.thumbnailName] = item.thumbnailURL
            }
            records.append(record(for: item, keepsFiles: keepsFiles))
        }
        return LibrarySnapshot(
            folders: folders.map(record(for:)),
            items: records,
            mediaSources: mediaSources,
            thumbnailSources: thumbnailSources
        )
    }

    static func record(for folder: Folder) -> FolderRecord {
        FolderRecord(
            id: folder.id,
            name: folder.name,
            symbol: folder.symbol,
            colorKey: folder.colorKey,
            sortIndex: folder.sortIndex,
            isLocked: folder.isLocked,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt,
            toneRaw: folder.toneRaw,
            sortRaw: folder.sortRaw,
            parentID: folder.parentID
        )
    }

    static func record(for item: Shot, keepsFiles: Bool) -> ItemRecord {
        ItemRecord(
            id: item.id,
            folderID: item.folderID,
            fileName: keepsFiles ? item.fileName : "",
            thumbnailName: keepsFiles ? item.thumbnailName : "",
            originalName: item.originalName,
            pixelWidth: item.pixelWidth,
            pixelHeight: item.pixelHeight,
            byteCount: keepsFiles ? item.byteCount : 0,
            capturedAt: item.capturedAt,
            captureOffsetKnown: item.captureOffsetKnown,
            addedAt: item.addedAt,
            isScreenshot: item.isScreenshot,
            isFavorite: item.isFavorite,
            note: item.note,
            sourceAssetID: item.sourceAssetID,
            libraryStatusRaw: item.libraryStatusRaw,
            kindRaw: item.kindRaw,
            linkURL: item.linkURL,
            linkTitle: item.linkTitle,
            linkSite: item.linkSite,
            linkAuthor: item.linkAuthor,
            linkDuration: item.linkDuration,
            linkFormRaw: item.linkFormRaw,
            linkDetails: item.linkDetails,
            linkPublishedAt: item.linkPublishedAt,
            linkViews: item.linkViews,
            sourceName: item.sourceName,
            deepAnalysis: item.deepAnalysis,
            analysisStateRaw: item.analysisStateRaw,
            analysisData: item.analysisData,
            viewedAt: item.viewedAt,
            contentHash: item.contentHash,
            captureKey: item.captureKey,
            linkKey: item.linkKey,
            mediaTypeRaw: item.mediaTypeRaw,
            mediaDuration: item.mediaDuration,
            hasAudio: item.hasAudio,
            latitude: item.latitude,
            longitude: item.longitude,
            cameraModel: item.cameraModel,
            documentTitle: item.documentTitle,
            documentPages: item.documentPages,
            linkRefreshedAt: item.linkRefreshedAt,
            noteUpdatedAt: item.noteUpdatedAt,
            linkImageURL: item.linkImageURL,
            hasMedia: keepsFiles && item.hasMediaFile,
            hasThumbnail: keepsFiles && item.hasThumbnail
        )
    }

    // MARK: Restoring records

    static func makeFolder(from record: FolderRecord) -> Folder {
        let folder = Folder(name: record.name, symbol: record.symbol, tone: .ember, isLocked: record.isLocked)
        folder.id = record.id
        folder.colorKey = record.colorKey
        folder.sortIndex = record.sortIndex
        folder.createdAt = record.createdAt
        folder.updatedAt = record.updatedAt
        folder.toneRaw = record.toneRaw
        folder.sortRaw = record.sortRaw
        folder.parentID = record.parentID
        return folder
    }

    static func makeItem(from record: ItemRecord, fileName: String, thumbnailName: String) -> Shot {
        var info = MediaInfo(kind: .photo)
        info.pixelWidth = record.pixelWidth
        info.pixelHeight = record.pixelHeight
        let staged = StagedMedia(
            id: record.id,
            fileURL: URL(filePath: "/dev/null"),
            thumbnailURL: nil,
            hasLowResThumbnail: false,
            info: info,
            originalName: record.originalName,
            byteCount: record.byteCount,
            sourceAssetID: record.sourceAssetID,
            contentHash: record.contentHash
        )
        let item = Shot(staged: staged, files: StoredFiles(fileName: fileName, thumbnailName: thumbnailName), folderID: record.folderID)
        item.id = record.id
        item.capturedAt = record.capturedAt
        item.captureOffsetKnown = record.captureOffsetKnown
        item.addedAt = record.addedAt
        item.isScreenshot = record.isScreenshot
        item.isFavorite = record.isFavorite
        item.note = record.note
        item.libraryStatusRaw = record.libraryStatusRaw == LibraryStatus.pendingDeletion.rawValue
            ? LibraryStatus.untouched.rawValue
            : record.libraryStatusRaw
        item.kindRaw = record.kindRaw
        item.linkURL = record.linkURL
        item.linkTitle = record.linkTitle
        item.linkSite = record.linkSite
        item.linkAuthor = record.linkAuthor
        item.linkDuration = record.linkDuration
        item.linkFormRaw = record.linkFormRaw
        item.linkDetails = record.linkDetails
        item.linkPublishedAt = record.linkPublishedAt
        item.linkViews = record.linkViews
        item.sourceName = record.sourceName
        item.deepAnalysis = record.deepAnalysis
        item.analysisStateRaw = record.analysisStateRaw
        item.analysisData = record.analysisData
        item.viewedAt = record.viewedAt
        item.contentHash = record.contentHash
        item.captureKey = record.captureKey
        item.linkKey = record.linkKey
        item.mediaTypeRaw = record.mediaTypeRaw
        item.mediaDuration = record.mediaDuration
        item.hasAudio = record.hasAudio
        item.latitude = record.latitude
        item.longitude = record.longitude
        item.cameraModel = record.cameraModel
        item.documentTitle = record.documentTitle
        item.documentPages = record.documentPages
        item.linkRefreshedAt = record.linkRefreshedAt
        item.noteUpdatedAt = record.noteUpdatedAt
        item.linkImageURL = record.linkImageURL
        item.mediaInCloud = nil
        item.refreshIndex()
        return item
    }
}

// MARK: - Single-file archive

/// A simple streaming archive: "LQBK", a version, then entries of
/// [kind: UInt8][path length: UInt16][path][size: UInt64][bytes], ending with kind 0.
nonisolated enum BackupArchive {
    static let magic = Array("LQBK".utf8)
    static let version: UInt16 = 1
    static let chunkSize = 1 << 20
    static let manifestPath = "Library.json"

    nonisolated struct Entry: Sendable {
        let path: String
        let source: URL
    }

    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 512, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains("\u{0}") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return false }
        if path == manifestPath { return true }
        return parts.count == 2 && (parts[0] == "Media" || parts[0] == "Thumbnails")
    }

    /// Writes the entries into one file. `progress` gets the bytes written so far.
    static func write(
        entries: [Entry],
        to destination: URL,
        isCancelled: () -> Bool = { false },
        progress: (Int64) -> Void = { _ in }
    ) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: destination)
        guard manager.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var header = Data(magic)
        header.append(contentsOf: bytes(of: version))
        try output.write(contentsOf: header)
        var written: Int64 = 0
        var seen = Set<String>()
        for entry in entries {
            if isCancelled() { throw BackupError.cancelled }
            guard isSafe(entry.path), seen.insert(entry.path.lowercased()).inserted else { throw BackupError.damaged }
            let attributes = try entry.source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard attributes.isRegularFile == true, let fileSize = attributes.fileSize, fileSize >= 0 else {
                throw BackupError.damaged
            }
            let size = UInt64(fileSize)
            let input = try FileHandle(forReadingFrom: entry.source)
            defer { try? input.close() }
            let pathBytes = Array(entry.path.utf8)
            var entryHeader = Data([1])
            entryHeader.append(contentsOf: bytes(of: UInt16(pathBytes.count)))
            entryHeader.append(contentsOf: pathBytes)
            entryHeader.append(contentsOf: bytes(of: size))
            try output.write(contentsOf: entryHeader)
            var remaining = size
            while remaining > 0 {
                let count = Int(min(UInt64(chunkSize), remaining))
                guard let chunk = try input.read(upToCount: count), !chunk.isEmpty else {
                    throw BackupError.damaged
                }
                try output.write(contentsOf: chunk)
                remaining -= UInt64(chunk.count)
                written += Int64(chunk.count)
                progress(written)
                if isCancelled() { throw BackupError.cancelled }
            }
        }
        try output.write(contentsOf: Data([0]))
        try output.synchronize()
    }

    /// Reads an archive into a folder and returns the paths it wrote.
    static func extract(
        _ archive: URL,
        to folder: URL,
        isCancelled: () -> Bool = { false },
        progress: (Int64) -> Void = { _ in }
    ) throws -> [String] {
        let manager = FileManager.default
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        let archiveSize = try input.seekToEnd()
        try input.seek(toOffset: 0)
        guard let head = try input.read(upToCount: 6), head.count == 6,
              Array(head.prefix(4)) == magic else {
            throw BackupError.notABackup
        }
        let fileVersion = UInt16(head[4]) | (UInt16(head[5]) << 8)
        guard fileVersion <= version else { throw BackupError.newerFormat }
        guard fileVersion > 0 else { throw BackupError.damaged }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var paths: [String] = []
        var total: Int64 = 0
        var seen = Set<String>()
        while true {
            if isCancelled() { throw BackupError.cancelled }
            guard let kindData = try input.read(upToCount: 1), let kind = kindData.first else {
                throw BackupError.damaged
            }
            if kind == 0 {
                guard try input.offset() == archiveSize else { throw BackupError.damaged }
                break
            }
            guard kind == 1,
                  let lengthData = try input.read(upToCount: 2), lengthData.count == 2 else {
                throw BackupError.damaged
            }
            let length = Int(UInt16(lengthData[lengthData.startIndex]) | (UInt16(lengthData[lengthData.startIndex + 1]) << 8))
            guard length > 0, length <= 512, let pathData = try input.read(upToCount: length), pathData.count == length,
                  let path = String(data: pathData, encoding: .utf8),
                  let sizeData = try input.read(upToCount: 8), sizeData.count == 8 else {
                throw BackupError.damaged
            }
            var size: UInt64 = 0
            for (index, byte) in sizeData.enumerated() {
                size |= UInt64(byte) << (8 * UInt64(index))
            }
            let offset = try input.offset()
            guard isSafe(path), seen.insert(path.lowercased()).inserted,
                  offset < archiveSize, size < archiveSize - offset else { throw BackupError.damaged }
            let destination = folder.appending(path: path)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard manager.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: destination)
            var remaining = size
            do {
                while remaining > 0 {
                    if isCancelled() { throw BackupError.cancelled }
                    let count = Int(min(UInt64(chunkSize), remaining))
                    guard let chunk = try input.read(upToCount: count), !chunk.isEmpty else {
                        throw BackupError.damaged
                    }
                    try output.write(contentsOf: chunk)
                    remaining -= UInt64(chunk.count)
                    total += Int64(chunk.count)
                    progress(total)
                }
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
            paths.append(path)
        }
        return paths
    }

    private static func bytes<T: FixedWidthInteger>(of value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}
