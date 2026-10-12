import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// A photo on its way into the library: an exact, byte-for-byte copy of the original file in a
/// private staging folder (`tmp/NoorImports/<uuid>/`). `LibraryStore` then inspects it and moves
/// it into its project folder.
///
/// From Photos it is loaded with `PhotosPickerItem.loadTransferable(type: ImportedOriginal.self)` and a
/// picker using `preferredItemEncoding: .current`, so the system hands over the stored encoding
/// (HEIC stays HEIC, ProRAW stays DNG, HDR gain maps survive) instead of a compatibility JPEG.
/// `FileRepresentation` delivers a file (no `Data` blob in memory, which matters for 75 MB DNGs) that
/// only exists inside the importing closure, so it is copied there.
///
/// From Files, `stageFile(at:)` copies under security-scoped access and a coordinated read, which also
/// downloads iCloud Drive placeholders first.
struct ImportedOriginal: Transferable {
    /// The staged copy (exact bytes of the original).
    let url: URL
    /// Name the original had where it came from (may be a system-generated name for Photos items).
    let fileName: String
    /// The content type the sender declared for the file, if known.
    let declaredType: UTType?

    // MARK: Transfer

    /// Most preferred first: RAW / DNG beats the JPEG or HEIC of a RAW+JPEG pair, HEIC beats a
    /// transcoded JPEG, and any other image format is taken as stored.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: ImportedOriginal.dngType) { received in
            try ImportedOriginal.stage(received, declared: ImportedOriginal.dngType)
        }
        FileRepresentation(importedContentType: .rawImage) { received in
            try ImportedOriginal.stage(received, declared: .rawImage)
        }
        FileRepresentation(importedContentType: .heic) { received in
            try ImportedOriginal.stage(received, declared: .heic)
        }
        FileRepresentation(importedContentType: .image) { received in
            try ImportedOriginal.stage(received, declared: .image)
        }
    }

    /// DNG / Apple ProRAW. `UTType.dng` is iOS 18+, so the identifier is spelled out.
    static let dngType: UTType = UTType("com.adobe.raw-image") ?? .rawImage

    // MARK: Staging

    /// Root of all staged imports. Emptied at launch (`purgeStaging()`), so a crash mid-import leaks nothing.
    static var stagingRoot: URL {
        URL.temporaryDirectory.appending(path: stagingFolderName, directoryHint: .isDirectory)
    }
    private static let stagingFolderName = "NoorImports"

    /// Copies a file received from the Photos picker. Runs inside the importing closure, where the
    /// received file is guaranteed to exist.
    static func stage(_ received: ReceivedTransferredFile, declared: UTType) throws -> ImportedOriginal {
        let fileName = received.file.lastPathComponent
        let folder = try makeStagingFolder()
        let destination = folder.appending(component: stagedName(for: fileName, declared: declared))
        do {
            try FileManager.default.copyItem(at: received.file, to: destination)   // byte-for-byte
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return ImportedOriginal(url: destination, fileName: fileName, declaredType: declared)
    }

    /// Copies a file picked in Files (or opened from another app). Synchronous and possibly slow
    /// (iCloud download): call it off the main thread.
    static func stageFile(at url: URL) throws -> ImportedOriginal {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
            throw ImportedOriginalError.notAFile
        }

        let fileName = url.lastPathComponent
        let declared = UTType(filenameExtension: url.pathExtension)
        let folder = try makeStagingFolder()
        let destination = folder.appending(component: stagedName(for: fileName, declared: declared))

        // A coordinated read waits for other writers and downloads an iCloud placeholder first.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges],
                                                         error: &coordinationError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: destination)   // byte-for-byte
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        if let error = copyError {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return ImportedOriginal(url: destination, fileName: fileName, declaredType: declared)
    }

    /// Removes this staged copy's private folder (after it was moved into the library, or on failure).
    func discardStaging() {
        // Only ever deletes a `NoorImports/<uuid>/` folder created by `makeStagingFolder()`.
        let folder = url.deletingLastPathComponent()
        guard UUID(uuidString: folder.lastPathComponent) != nil,
              folder.deletingLastPathComponent().lastPathComponent == ImportedOriginal.stagingFolderName
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes every staged import left over from a previous run. Call before any import starts.
    static func purgeStaging() {
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    // MARK: Helpers

    private static func makeStagingFolder() throws -> URL {
        let folder = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A safe single path component that keeps the extension (`PhotoDocument` falls back to it when
    /// ImageIO cannot type the data, e.g. some RAW formats). The final library name is chosen later.
    private static func stagedName(for fileName: String, declared: UTType?) -> String {
        var ext = (fileName as NSString).pathExtension
        if ext.isEmpty { ext = declared?.preferredFilenameExtension ?? "" }
        return ext.isEmpty ? "original" : "original.\(ext)"
    }
}

/// Why a picked item could not be staged.
enum ImportedOriginalError: LocalizedError {
    case notAFile

    var errorDescription: String? {
        switch self {
        case .notAFile:
            return String(localized: "Folders can't be imported. Choose photos instead.")
        }
    }
}
