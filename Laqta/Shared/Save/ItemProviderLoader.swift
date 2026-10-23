//
//  ItemProviderLoader.swift
//  Laqta — Shared
//
//  Loads shared items without decoding them in memory (the Share Extension has a low memory limit).
//

import Foundation
import UIKit
import UniformTypeIdentifiers

nonisolated struct ProviderBox: @unchecked Sendable {
    let provider: NSItemProvider
}

nonisolated enum SharedKind: Sendable, Equatable {
    case media(MediaKind)
    case url
    case text
}

nonisolated enum ItemProviderLoader {
    static func kind(of provider: NSItemProvider) -> SharedKind? {
        if let kind = mediaKind(of: provider) { return .media(kind) }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return .url
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            return .text
        }
        // Files shared as a bare file URL (Files, Mail attachments).
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return .media(.document)
        }
        return nil
    }

    private static func registeredTypes(_ provider: NSItemProvider) -> [UTType] {
        provider.registeredTypeIdentifiers.compactMap { UTType($0) }
    }

    static func mediaKind(of provider: NSItemProvider) -> MediaKind? {
        let types = registeredTypes(provider)
        // PDFs and movies first: a PDF often also offers a rendered image.
        if types.contains(where: { $0.conforms(to: .pdf) }) { return .document }
        if types.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) { return .video }
        if types.contains(where: { $0.conforms(to: .image) }) || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return .photo
        }
        return nil
    }

    /// Picks the most faithful representation the sender offers.
    static func typeIdentifier(for provider: NSItemProvider, kind: MediaKind) -> String? {
        let types = registeredTypes(provider)
        switch kind {
        case .document:
            return types.first { $0.conforms(to: .pdf) }?.identifier
                ?? (provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL.identifier : nil)
        case .video:
            let movies = types.filter { $0.conforms(to: .movie) || $0.conforms(to: .video) }
            return (movies.first { $0 != .movie && $0 != .video } ?? movies.first)?.identifier
        case .photo:
            let images = types.filter { $0.conforms(to: .image) }
            if let specific = images.first(where: { $0 != .image }) { return specific.identifier }
            if !images.isEmpty || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                return UTType.image.identifier
            }
            return nil
        }
    }

    // MARK: Links

    @concurrent
    static func loadURL(_ box: ProviderBox) async -> URL? {
        let provider = box.provider
        if provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url, !url.isFileURL, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url
            }
        }
        if let text = await loadText(box) {
            return LinkClassifier.firstURL(in: text)
        }
        return nil
    }

    @concurrent
    static func loadText(_ box: ProviderBox) async -> String? {
        let provider = box.provider
        guard provider.canLoadObject(ofClass: String.self) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    // MARK: Media

    @concurrent
    static func stage(_ box: ProviderBox, kind: MediaKind) async throws -> StagedMedia {
        let provider = box.provider
        guard let typeIdentifier = typeIdentifier(for: provider, kind: kind) else {
            throw MediaError.unsupportedItem
        }
        let suggestedName = provider.suggestedName
        DebugLog.write("provider types=\(provider.registeredTypeIdentifiers) kind=\(kind.rawValue) chosen=\(typeIdentifier) suggestedName=\(suggestedName ?? "-")")

        if typeIdentifier == UTType.fileURL.identifier {
            return try await stageFileURLObject(provider, name: suggestedName)
        }
        // A file representation is the only way a video or a large PDF can be taken at
        // all: the sender writes it to disk and Laqta copies it, so the file never has
        // to fit in the extension's memory. Every type the sender offers for this kind
        // is tried that way before anything that loads bytes — one sender refusing the
        // best type used to drop a whole image to the in-memory path.
        for candidate in fileRepresentationTypes(provider, kind: kind, first: typeIdentifier) {
            guard let copy = try await staged(from: candidate, provider: provider, kind: kind) else { continue }
            // Past the copy the file is Laqta's: one it can't read is an error to
            // report, not a reason to ask the sender for another type.
            return try await describeCopy(copy, kind: kind, name: suggestedName)
        }
        // Only photos are ever taken as bytes, and only up to a limit that leaves the
        // extension alive. Videos and PDFs never are.
        if kind == .photo {
            if let copy = try await bytes(from: typeIdentifier, provider: provider) {
                return try await describeCopy(copy, kind: kind, name: suggestedName)
            }
            if let copy = try await loadedImage(provider) {
                return try await describeCopy(copy, kind: kind, name: suggestedName)
            }
        }
        return try await stageFileURLObject(provider, name: suggestedName)
    }

    /// A file the sender wrote to disk, or nil when it won't offer this type.
    ///
    /// "Too large for the share sheet" is an answer rather than a reason to try the
    /// same item another way, so it is the one failure that stops the search.
    private static func staged(
        from typeIdentifier: String,
        provider: NSItemProvider,
        kind: MediaKind
    ) async throws -> (id: UUID, url: URL)? {
        do {
            return try await copyFileRepresentation(provider, typeIdentifier: typeIdentifier, kind: kind)
        } catch {
            if MediaError.isTooLargeToShare(error) { throw error }
            return nil
        }
    }

    private static func bytes(from typeIdentifier: String, provider: NSItemProvider) async throws -> (id: UUID, url: URL)? {
        do {
            return try await copyDataRepresentation(provider, typeIdentifier: typeIdentifier)
        } catch {
            if MediaError.isTooLargeToShare(error) { throw error }
            return nil
        }
    }

    private static func loadedImage(_ provider: NSItemProvider) async throws -> (id: UUID, url: URL)? {
        do {
            return try await copyLoadedImage(provider)
        } catch {
            if MediaError.isTooLargeToShare(error) { throw error }
            return nil
        }
    }

    /// The best type first, then every other type the sender registered for this kind.
    private static func fileRepresentationTypes(_ provider: NSItemProvider, kind: MediaKind, first: String) -> [String] {
        var types = [first]
        for type in registeredTypes(provider) where conforms(type, to: kind) {
            let identifier = type.identifier
            if !types.contains(identifier) { types.append(identifier) }
        }
        return types
    }

    private static func conforms(_ type: UTType, to kind: MediaKind) -> Bool {
        switch kind {
        case .document: type.conforms(to: .pdf)
        case .video: type.conforms(to: .movie) || type.conforms(to: .video)
        case .photo: type.conforms(to: .image)
        }
    }

    private static func describeCopy(_ copy: (id: UUID, url: URL), kind: MediaKind, name: String?) async throws -> StagedMedia {
        // A PDF shared as an image-only item, or the reverse, is checked by its real type.
        let actualKind = MediaInspector.kind(forFileAt: copy.url) ?? kind
        return try await MediaStore.describe(id: copy.id, fileURL: copy.url, kind: actualKind, originalName: name, sourceAssetID: nil)
    }

    private static func copyFileRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        kind: MediaKind
    ) async throws -> (id: UUID, url: URL) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(id: UUID, url: URL), any Error>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? MediaError.noData)
                    return
                }
                // The temporary file only exists inside this callback.
                do {
                    continuation.resume(returning: try MediaStore.copyToStaging(url, kind: kind))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func copyDataRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> (id: UUID, url: URL) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(id: UUID, url: URL), any Error>) in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                guard let data else {
                    continuation.resume(throwing: error ?? MediaError.noData)
                    return
                }
                do {
                    continuation.resume(returning: try MediaStore.writeToStaging(data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Last resort for senders that only offer an in-memory image.
    ///
    /// JPEG, not PNG: a decoded 48-megapixel screenshot is already around 200 MB in
    /// the extension's hands, and `pngData()` asked for about as much again, which is
    /// how a big image took the whole extension down with it instead of saving. JPEG
    /// at 0.92 is a few megabytes, and the pixels are whatever the sender decoded.
    private static func copyLoadedImage(_ provider: NSItemProvider) async throws -> (id: UUID, url: URL) {
        guard provider.canLoadObject(ofClass: UIImage.self) else { throw MediaError.noData }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(id: UUID, url: URL), any Error>) in
            _ = provider.loadObject(ofClass: UIImage.self) { object, error in
                guard let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.92) else {
                    continuation.resume(throwing: error ?? MediaError.noData)
                    return
                }
                do {
                    continuation.resume(returning: try MediaStore.writeToStaging(data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Senders that only offer a file URL object (Files, some mail apps).
    private static func stageFileURLObject(_ provider: NSItemProvider, name: String?) async throws -> StagedMedia {
        guard provider.canLoadObject(ofClass: URL.self) else { throw MediaError.noData }
        let copy: (id: UUID, url: URL, kind: MediaKind, name: String) = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url, url.isFileURL else {
                    continuation.resume(throwing: error ?? MediaError.noData)
                    return
                }
                guard let kind = MediaInspector.kind(forFileAt: url) else {
                    continuation.resume(throwing: MediaError.unsupportedItem)
                    return
                }
                do {
                    let copy = try MediaStore.copyToStaging(url, kind: kind)
                    continuation.resume(returning: (copy.id, copy.url, kind, url.deletingPathExtension().lastPathComponent))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return try await MediaStore.describe(id: copy.id, fileURL: copy.url, kind: copy.kind, originalName: name ?? copy.name, sourceAssetID: nil)
    }
}
