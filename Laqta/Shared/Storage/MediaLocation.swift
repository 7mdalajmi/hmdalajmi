//
//  MediaLocation.swift
//  Laqta — Shared
//
//  Where a stored media file lives: on this device (App Group), or in Laqta's
//  iCloud container when iCloud sync is on.
//

import Foundation

nonisolated enum MediaLocation {
    /// The file URL to read a stored media file from.
    static func fileURL(named fileName: String) -> URL {
        let local = AppGroup.mediaURL.appending(path: fileName)
        guard !fileName.isEmpty, let cloud = CloudMedia.mediaURL(for: fileName) else { return local }
        if FileManager.default.fileExists(atPath: local.path(percentEncoded: false)) {
            return local
        }
        return cloud
    }
}
