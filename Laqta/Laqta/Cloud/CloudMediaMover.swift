//
//  CloudMediaMover.swift
//  Laqta
//
//  With iCloud sync on, media files move into Laqta's iCloud container, so every
//  device can download them. Thumbnails are copied (this device keeps its own).
//

import Foundation

nonisolated enum CloudMediaMover {
    enum Outcome: Sendable, Equatable {
        case moved
        case alreadyInCloud
        case missing
        case failed
    }

    /// Moves one item's media file into iCloud.
    @concurrent
    static func upload(fileName: String, thumbnailName: String) async -> Outcome {
        guard let mediaFolder = CloudContainer.mediaURL, let thumbnailFolder = CloudContainer.thumbnailsURL else {
            return .failed
        }
        do {
            try CloudFiles.createDirectory(mediaFolder)
            try CloudFiles.createDirectory(thumbnailFolder)
        } catch {
            DebugLog.write("cloud: folders failed \(error)")
            return .failed
        }
        let manager = FileManager.default
        if !thumbnailName.isEmpty {
            let local = AppGroup.thumbnailsURL.appending(path: thumbnailName)
            let cloud = thumbnailFolder.appending(path: thumbnailName)
            if manager.fileExists(atPath: local.path(percentEncoded: false)), !CloudFiles.exists(cloud) {
                do {
                    try CloudFiles.copy(from: local, to: cloud)
                } catch {
                    DebugLog.write("cloud: thumbnail upload failed \(error)")
                }
            }
        }
        guard !fileName.isEmpty else { return .alreadyInCloud }
        let local = AppGroup.mediaURL.appending(path: fileName)
        let cloud = mediaFolder.appending(path: fileName)
        guard manager.fileExists(atPath: local.path(percentEncoded: false)) else {
            return CloudFiles.exists(cloud) ? .alreadyInCloud : .missing
        }
        if CloudFiles.exists(cloud) {
            // The same file is already in iCloud (file names are unique per item).
            if CloudFiles.isAvailable(cloud), sameSize(local, cloud) {
                try? manager.removeItem(at: local)
            }
            return .alreadyInCloud
        }
        do {
            try manager.setUbiquitous(true, itemAt: local, destinationURL: cloud)
            return .moved
        } catch {
            DebugLog.write("cloud: upload failed \(fileName) \(error)")
            return .failed
        }
    }

    /// Brings a media file from iCloud back into this device's storage.
    @concurrent
    static func download(fileName: String, timeout: Duration = .seconds(300)) async -> Bool {
        guard !fileName.isEmpty else { return true }
        let local = AppGroup.mediaURL.appending(path: fileName)
        if FileManager.default.fileExists(atPath: local.path(percentEncoded: false)) { return true }
        guard let cloud = CloudMedia.mediaURL(for: fileName), CloudFiles.exists(cloud) else { return false }
        guard await CloudFiles.waitUntilAvailable(cloud, timeout: timeout) else { return false }
        do {
            try AppGroup.prepareDirectories()
            try CloudFiles.copy(from: cloud, to: local)
            return true
        } catch {
            DebugLog.write("cloud: download failed \(fileName) \(error)")
            return false
        }
    }

    /// The media file is only in iCloud (not in this device's own storage).
    static func isOnlyInCloud(fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        let local = AppGroup.mediaURL.appending(path: fileName)
        return !FileManager.default.fileExists(atPath: local.path(percentEncoded: false))
    }

    private static func sameSize(_ first: URL, _ second: URL) -> Bool {
        let a = (try? first.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let b = (try? second.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
        return a == b
    }
}
