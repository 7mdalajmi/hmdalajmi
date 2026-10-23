//
//  CloudMediaStore.swift
//  Laqta — Shared
//
//  Media files kept in Laqta's iCloud container when iCloud sync is on.
//

import Foundation

nonisolated enum CloudMediaStore {
    /// Removes an item's files from iCloud (all devices). Only while sync is on: with sync off,
    /// the library on this device no longer matches iCloud, and other devices may still use the files.
    static func deleteFiles(fileName: String, thumbnailName: String) {
        guard CloudConfig.isSyncEnabled else { return }
        var urls: [URL] = []
        if !fileName.isEmpty, let url = CloudMedia.mediaURL(for: fileName) { urls.append(url) }
        if !thumbnailName.isEmpty, let url = CloudMedia.thumbnailURL(for: thumbnailName) { urls.append(url) }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                coordinatedDelete(url)
            }
        }
    }

    static func coordinatedDelete(_ url: URL) {
        CloudFiles.coordinatedDelete(url)
    }
}

extension CloudMediaStore {
    /// Copies a thumbnail made on another device into the local cache, when it's already downloaded.
    nonisolated static func copyThumbnailIfAvailable(named name: String, to destination: URL) -> Bool {
        guard !name.isEmpty, let source = CloudMedia.thumbnailURL(for: name) else { return false }
        let manager = FileManager.default
        let values = try? source.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard values?.ubiquitousItemDownloadingStatus == .current else {
            // Ask iCloud for it; a later load will find it.
            try? manager.startDownloadingUbiquitousItem(at: source)
            return false
        }
        var copied = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            try? manager.removeItem(at: destination)
            copied = (try? manager.copyItem(at: url, to: destination)) != nil
        }
        return copied
    }
}

extension CloudMediaStore {
    /// Asks iCloud to download an item's media file.
    nonisolated static func requestDownload(of fileName: String) {
        guard !fileName.isEmpty, let url = CloudMedia.mediaURL(for: fileName) else { return }
        CloudFiles.requestDownload(url)
    }
}
