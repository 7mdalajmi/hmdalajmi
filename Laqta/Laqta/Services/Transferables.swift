//
//  Transferables.swift
//  Laqta
//
//  Sharing and dragging saved items: files keep a readable name, and items
//  dragged inside Laqta carry their ID.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// An item dragged between Laqta folders.
    nonisolated static let laqtaItem = UTType(exportedAs: "Hmdalajmi.Laqta.item", conformingTo: .data)
}

/// A stored media file, shared with a name people recognize ("IMG_1234.HEIC").
nonisolated struct ShareableFile: Transferable, Sendable {
    let sourceURL: URL
    let fileName: String
    let kind: MediaKind

    @MainActor
    init(item: Shot) {
        sourceURL = item.fileURL
        fileName = item.shareFileName
        kind = item.kind.mediaKind ?? .photo
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .image) { file in
            SentTransferredFile(try file.namedCopy())
        }
        .exportingCondition { $0.kind == .photo }
        .suggestedFileName { $0.suggestedName }
        FileRepresentation(exportedContentType: .movie) { file in
            SentTransferredFile(try file.namedCopy())
        }
        .exportingCondition { $0.kind == .video }
        .suggestedFileName { $0.suggestedName }
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(try file.namedCopy())
        }
        .exportingCondition { $0.kind == .document }
        .suggestedFileName { $0.suggestedName }
    }

    /// Never empty (an empty name makes the system share sheet fail).
    var suggestedName: String {
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? sourceURL.lastPathComponent : name
    }

    /// A hard link (or copy) with the readable name, in a temporary folder.
    func namedCopy() throws -> URL {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory
            .appending(path: "Share", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: suggestedName)
        do {
            try manager.linkItem(at: sourceURL, to: destination)
        } catch {
            try manager.copyItem(at: sourceURL, to: destination)
        }
        return destination
    }
}

/// A saved item being dragged: inside Laqta it moves between folders,
/// outside it becomes the file or the link.
nonisolated struct ItemTransfer: Transferable, Codable, Sendable {
    let id: UUID
    let kind: Int
    let fileName: String
    let sourcePath: String?
    let link: String?

    @MainActor
    init(item: Shot) {
        id = item.id
        kind = item.kind.rawValue
        fileName = item.shareFileName
        sourcePath = item.hasMediaFile && !item.isLink ? item.fileURL.path(percentEncoded: false) : nil
        link = item.linkURL
    }

    private var mediaKind: MediaKind? { ItemKind(rawValue: kind)?.mediaKind }

    var suggestedName: String {
        fileName.isEmpty ? "Laqta Item" : fileName
    }

    private var shareable: ShareableFile? {
        guard let sourcePath, let mediaKind else { return nil }
        return ShareableFile(sourceURL: URL(fileURLWithPath: sourcePath), fileName: fileName, kind: mediaKind)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .laqtaItem)
        FileRepresentation(exportedContentType: .image) { item in
            guard let file = item.shareable else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(try file.namedCopy())
        }
        .exportingCondition { $0.mediaKind == .photo }
        .suggestedFileName { $0.suggestedName }
        FileRepresentation(exportedContentType: .movie) { item in
            guard let file = item.shareable else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(try file.namedCopy())
        }
        .exportingCondition { $0.mediaKind == .video }
        .suggestedFileName { $0.suggestedName }
        FileRepresentation(exportedContentType: .pdf) { item in
            guard let file = item.shareable else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(try file.namedCopy())
        }
        .exportingCondition { $0.mediaKind == .document }
        .suggestedFileName { $0.suggestedName }
        ProxyRepresentation { item in
            URL(string: item.link ?? "") ?? URL(string: "https://")!
        }
        .exportingCondition { $0.link != nil }
    }
}

extension ShareableFile {
    nonisolated init(sourceURL: URL, fileName: String, kind: MediaKind) {
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.kind = kind
    }
}
