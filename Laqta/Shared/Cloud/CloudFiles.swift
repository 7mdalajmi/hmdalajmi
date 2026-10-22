//
//  CloudFiles.swift
//  Laqta — Shared
//
//  Reading, writing and waiting for files in Laqta's iCloud container, with file
//  coordination, and files that iCloud hasn't downloaded to this device yet.
//

import Foundation

nonisolated enum CloudFiles {
    /// iOS keeps not-yet-downloaded iCloud files as ".Name.icloud" placeholders.
    static func placeholderName(for name: String) -> String {
        ".\(name).icloud"
    }

    static func realName(fromPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > 8 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// The file is on this device and can be read now.
    static func isAvailable(_ url: URL) -> Bool {
        var url = url
        url.removeAllCachedResourceValues()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return true }
        return values.ubiquitousItemDownloadingStatus == .current
    }

    /// The file exists in iCloud, downloaded or not.
    static func exists(_ url: URL) -> Bool {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path(percentEncoded: false)) { return true }
        let placeholder = url.deletingLastPathComponent().appending(path: placeholderName(for: url.lastPathComponent))
        return manager.fileExists(atPath: placeholder.path(percentEncoded: false))
    }

    static func requestDownload(_ url: URL) {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            // Not an iCloud file, or already downloaded.
        }
    }

    /// Waits for iCloud to download a file (asking again now and then).
    @concurrent
    static func waitUntilAvailable(_ url: URL, timeout: Duration = .seconds(600)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var attempt = 0
        while clock.now < deadline {
            if isAvailable(url) { return true }
            if attempt % 15 == 0 { requestDownload(url) }
            attempt += 1
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return false
            }
        }
        return isAvailable(url)
    }

    // MARK: Coordinated access

    static func createDirectory(_ url: URL) throws {
        var coordinationError: NSError?
        var thrown: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } catch {
                thrown = error
            }
        }
        if let error = coordinationError ?? thrown { throw error }
    }

    /// Copies a file into (or out of) iCloud. iCloud downloads the source first when needed.
    static func copy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var thrown: (any Error)?
        NSFileCoordinator().coordinate(
            readingItemAt: source,
            options: [],
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError
        ) { readURL, writeURL in
            let manager = FileManager.default
            do {
                let temporary = writeURL.deletingLastPathComponent()
                    .appending(path: ".\(UUID().uuidString)-\(writeURL.lastPathComponent)")
                try manager.copyItem(at: readURL, to: temporary)
                if manager.fileExists(atPath: writeURL.path(percentEncoded: false)) {
                    _ = try manager.replaceItemAt(writeURL, withItemAt: temporary)
                } else {
                    try manager.moveItem(at: temporary, to: writeURL)
                }
            } catch {
                thrown = error
            }
        }
        if let error = coordinationError ?? thrown { throw error }
    }

    static func write(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var thrown: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                thrown = error
            }
        }
        if let error = coordinationError ?? thrown { throw error }
    }

    /// Reads a small file, downloading it first when needed.
    static func read(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            result = Result { try Data(contentsOf: target) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func coordinatedDelete(_ url: URL) {
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            try? FileManager.default.removeItem(at: target)
        }
        if let coordinationError {
            DebugLog.write("cloud: delete failed \(coordinationError)")
        }
    }

    /// File names in an iCloud folder, including files that aren't downloaded yet.
    static func names(in folder: URL) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else {
            return []
        }
        var names = Set<String>()
        for entry in entries {
            if let real = realName(fromPlaceholder: entry) {
                names.insert(real)
            } else if !entry.hasPrefix(".") {
                names.insert(entry)
            }
        }
        return names
    }

    /// Total size of an iCloud folder (downloaded or not).
    static func size(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
