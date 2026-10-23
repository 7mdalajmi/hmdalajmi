//
//  PhotosImport.swift
//  Laqta
//
//  Files picked in the app. Photos keep their identifier, so deleting the original is exact.
//

import CoreTransferable
import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Copies a picked photo or video out of the picker's temporary location.
nonisolated struct PickedMediaFile: Transferable, Sendable {
    let url: URL
    let originalName: String

    static var directory: URL {
        URL.temporaryDirectory.appending(path: "PickerImport", directoryHint: .isDirectory)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try copy(received.file, defaultExtension: "mov")
        }
        FileRepresentation(importedContentType: .image) { received in
            try copy(received.file, defaultExtension: "jpg")
        }
    }

    static func copy(_ source: URL, defaultExtension: String) throws -> PickedMediaFile {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? defaultExtension : source.pathExtension
        let destination = directory.appending(path: "\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return PickedMediaFile(url: destination, originalName: source.deletingPathExtension().lastPathComponent)
    }

    /// Copies a file chosen in the Files app (security-scoped) so it can be read later.
    static func copyFromFiles(_ source: URL) throws -> PickedMediaFile {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
        var result: PickedMediaFile?
        var copyError: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            do {
                result = try copy(url, defaultExtension: "pdf")
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        guard let result else { throw MediaError.noData }
        return result
    }

    /// Turns scanned pages into one PDF.
    static func pdf(from pages: [UIImage], title: String) throws -> PickedMediaFile {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = PDFDocument()
        for (index, image) in pages.enumerated() {
            if let page = PDFPage(image: image) {
                document.insert(page, at: index)
            }
        }
        guard document.pageCount > 0 else { throw MediaError.noData }
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title]
        let destination = directory.appending(path: "\(UUID().uuidString).pdf")
        guard document.write(to: destination) else { throw MediaError.unreadable(.document) }
        return PickedMediaFile(url: destination, originalName: title)
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
