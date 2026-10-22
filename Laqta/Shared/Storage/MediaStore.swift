//
//  MediaStore.swift
//  Laqta — Shared
//
//  Copies photos, videos and PDFs into Laqta's private storage, so they stay
//  even after the original is deleted from Photos.
//

import CoreGraphics
import Foundation
import UniformTypeIdentifiers

nonisolated enum MediaStore {
    static let thumbnailPixelSize = 640
    /// Above this size the Share Extension avoids a full photo decode (memory ceiling).
    static let fullDecodePixelLimit = 16_000_000
    /// Space kept free on the device when copying large files.
    static let reservedSpace: Int64 = 250 * 1024 * 1024
    /// Files above this size are not hashed in the Share Extension (time limit).
    static let extensionHashLimit: Int64 = 4 * 1024 * 1024 * 1024
    /// The largest file the Share Extension copies. Above this the copy takes long
    /// enough that the system is as likely to end the extension as to let it finish,
    /// and the app's own importer has no limit — so it says so instead of dying.
    static let extensionFileLimit: Int64 = 2 * 1024 * 1024 * 1024
    /// The largest item the Share Extension will take as bytes in memory rather than
    /// as a file. Its whole budget is a fraction of the app's.
    static let extensionDataLimit: Int64 = 64 * 1024 * 1024

    // MARK: Staging

    /// Copies a file into staging. Safe to call inside `NSItemProvider` callbacks,
    /// where the temporary file only exists until the callback returns.
    static func copyToStaging(_ source: URL, kind: MediaKind?) throws -> (id: UUID, url: URL) {
        try AppGroup.prepareDirectories()
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if AppGroup.isRunningInExtension, size > extensionFileLimit {
            throw MediaError.tooLargeToShare(limit: extensionFileLimit)
        }
        try ensureSpace(for: size)
        let id = UUID()
        let destination = AppGroup.stagingURL.appending(path: "\(id.uuidString).\(fileExtension(for: source, kind: kind))")
        try FileManager.default.copyItem(at: source, to: destination)
        return (id, destination)
    }

    static func writeToStaging(_ data: Data) throws -> (id: UUID, url: URL) {
        try AppGroup.prepareDirectories()
        if AppGroup.isRunningInExtension, Int64(data.count) > extensionDataLimit {
            throw MediaError.tooLargeToShare(limit: extensionDataLimit)
        }
        try ensureSpace(for: Int64(data.count))
        let id = UUID()
        let destination = AppGroup.stagingURL.appending(path: "\(id.uuidString).\(ImageTools.fileExtension(for: data))")
        try data.write(to: destination, options: .atomic)
        return (id, destination)
    }

    /// Copies and describes a file picked in the app.
    @concurrent
    static func stageFile(at source: URL, originalName: String?, sourceAssetID: String?, kind: MediaKind? = nil) async throws -> StagedMedia {
        let resolvedKind = kind ?? MediaInspector.kind(forFileAt: source)
        guard let resolvedKind else { throw MediaError.unsupportedItem }
        let copy = try copyToStaging(source, kind: resolvedKind)
        let name = originalName ?? source.deletingPathExtension().lastPathComponent
        return try await describe(id: copy.id, fileURL: copy.url, kind: resolvedKind, originalName: name, sourceAssetID: sourceAssetID)
    }

    /// Stages downloaded image data (link previews).
    @concurrent
    static func stageImageData(_ data: Data, originalName: String? = nil) async throws -> StagedMedia {
        let copy = try writeToStaging(data)
        return try await describe(id: copy.id, fileURL: copy.url, kind: .photo, originalName: originalName, sourceAssetID: nil)
    }

    /// Reads a staged file, makes its thumbnail and hashes it.
    @concurrent
    static func describe(id: UUID, fileURL: URL, kind: MediaKind, originalName: String?, sourceAssetID: String?) async throws -> StagedMedia {
        guard var info = await MediaInspector.info(forFileAt: fileURL, kind: kind) else {
            try? FileManager.default.removeItem(at: fileURL)
            throw MediaError.unreadable(kind)
        }
        if info.typeIdentifier == nil {
            info.typeIdentifier = MediaInspector.typeIdentifier(forFileAt: fileURL)
        }
        if kind == .document, info.title == nil, let originalName, !originalName.isEmpty {
            info.title = originalName
        }

        let inExtension = AppGroup.isRunningInExtension
        let allowFullDecode = kind != .photo || !inExtension || info.pixelCount <= fullDecodePixelLimit
        let thumbnailURL = AppGroup.stagingURL.appending(path: "\(id.uuidString)-thumb.jpg")
        var hasThumbnail = false
        if let thumbnail = await MediaInspector.thumbnail(
            forFileAt: fileURL,
            kind: kind,
            maxPixelSize: thumbnailPixelSize,
            allowFullDecode: allowFullDecode,
            duration: info.duration
        ) {
            hasThumbnail = (try? ImageTools.writeJPEG(thumbnail, to: thumbnailURL)) != nil
        }

        let byteCount = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let hash: String? = inExtension && Int64(byteCount) > extensionHashLimit ? nil : ContentHasher.sha256(of: fileURL)
        return StagedMedia(
            id: id,
            fileURL: fileURL,
            thumbnailURL: hasThumbnail ? thumbnailURL : nil,
            hasLowResThumbnail: !allowFullDecode,
            info: info,
            originalName: originalName,
            byteCount: byteCount,
            sourceAssetID: sourceAssetID,
            contentHash: hash
        )
    }

    static func ensureSpace(for byteCount: Int64) throws {
        guard byteCount > 0 else { return }
        let values = try? AppGroup.rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        if available - byteCount < reservedSpace {
            throw MediaError.notEnoughSpace(needed: byteCount)
        }
    }

    static func fileExtension(for url: URL, kind: MediaKind?) -> String {
        let ext = ImageTools.fileExtension(for: url)
        if ext != "jpg" || url.pathExtension.lowercased() == "jpg" { return ext }
        switch kind {
        case .video:
            return UTType(MediaInspector.typeIdentifier(forFileAt: url) ?? "")?.preferredFilenameExtension ?? "mov"
        case .document:
            return "pdf"
        default:
            return ext
        }
    }

    // MARK: Commit / discard

    /// Moves a staged file into permanent storage.
    static func commit(_ staged: StagedMedia) throws -> StoredFiles {
        try AppGroup.prepareDirectories()
        let manager = FileManager.default
        let fileName = "\(staged.id.uuidString).\(staged.fileURL.pathExtension)"
        let thumbnailName = "\(staged.id.uuidString).jpg"
        try manager.moveItem(at: staged.fileURL, to: AppGroup.mediaURL.appending(path: fileName))

        if let thumbnailURL = staged.thumbnailURL {
            if staged.hasLowResThumbnail {
                // The app renders a sharp thumbnail later, outside the extension's memory limit.
                try? manager.removeItem(at: thumbnailURL)
            } else {
                try? manager.moveItem(at: thumbnailURL, to: AppGroup.thumbnailsURL.appending(path: thumbnailName))
            }
        }
        return StoredFiles(fileName: fileName, thumbnailName: thumbnailName)
    }

    static func discard(_ staged: StagedMedia) {
        let manager = FileManager.default
        try? manager.removeItem(at: staged.fileURL)
        if let thumbnailURL = staged.thumbnailURL {
            try? manager.removeItem(at: thumbnailURL)
        }
    }

    /// One path component and nothing else: no separator, no `.` or `..`, no null byte.
    ///
    /// Every name the app writes itself is `<uuid>.<ext>`, so this only ever rejects a
    /// name that came from somewhere else — a restored backup's manifest.
    nonisolated static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    static func deleteStoredFiles(fileName: String, thumbnailName: String) {
        let manager = FileManager.default
        // Deleting is the dangerous direction: a name that is not a plain file name
        // could resolve onto the store itself.
        if isPlainFileName(fileName) {
            try? manager.removeItem(at: AppGroup.mediaURL.appending(path: fileName))
        }
        if isPlainFileName(thumbnailName) {
            try? manager.removeItem(at: AppGroup.thumbnailsURL.appending(path: thumbnailName))
        }
    }

    /// Removes leftovers from share sessions that never finished.
    @concurrent
    static func purgeStaging(olderThan age: TimeInterval = 6 * 3600) async {
        purgeStagingSync(olderThan: age)
    }

    private static func purgeStagingSync(olderThan age: TimeInterval) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: AppGroup.stagingURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date.now.addingTimeInterval(-age)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff {
                try? manager.removeItem(at: file)
            }
        }
    }

    // MARK: Storage usage

    @concurrent
    static func storageUsage() async -> Int64 {
        directorySize(AppGroup.rootURL)
    }

    static func directorySize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys)
        ) else { return 0 }
        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
