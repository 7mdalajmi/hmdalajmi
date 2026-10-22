//
//  ItemProviderLoader.swift
//  لقطة — Share Extension
//
//  تحميل الصور من قائمة المشاركة بدون فك ترميزها في الذاكرة (حد ذاكرة الإضافة منخفض).
//

import Foundation
import UIKit
import UniformTypeIdentifiers

nonisolated struct ProviderBox: @unchecked Sendable {
    let provider: NSItemProvider
}

nonisolated enum ItemProviderLoader {
    /// Picks the most faithful image representation the sender offers.
    static func imageTypeIdentifier(for provider: NSItemProvider) -> String? {
        let imageTypes = provider.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .filter { $0.conforms(to: .image) }
        if let specific = imageTypes.first(where: { $0 != .image }) {
            return specific.identifier
        }
        if !imageTypes.isEmpty || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return UTType.image.identifier
        }
        return nil
    }

    @concurrent
    static func stage(_ box: ProviderBox) async throws -> StagedImage {
        let provider = box.provider
        guard let typeIdentifier = imageTypeIdentifier(for: provider) else {
            throw MediaError.unsupportedItem
        }
        let suggestedName = provider.suggestedName
        DebugLog.write("provider types=\(provider.registeredTypeIdentifiers) chosen=\(typeIdentifier) suggestedName=\(suggestedName ?? "-")")

        if let staged = try? await stageFileRepresentation(provider, typeIdentifier: typeIdentifier, name: suggestedName) {
            return staged
        }
        if let staged = try? await stageDataRepresentation(provider, typeIdentifier: typeIdentifier, name: suggestedName) {
            return staged
        }
        return try await stageLoadedObject(provider, name: suggestedName)
    }

    private static func stageFileRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        name: String?
    ) async throws -> StagedImage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StagedImage, any Error>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? MediaError.noData)
                    return
                }
                // The temporary file only exists inside this callback.
                DebugLog.write("file representation: \(url.lastPathComponent)")
                do {
                    let staged = try MediaStore.stageFile(at: url, originalName: name)
                    continuation.resume(returning: staged)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func stageDataRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        name: String?
    ) async throws -> StagedImage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StagedImage, any Error>) in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                guard let data else {
                    continuation.resume(throwing: error ?? MediaError.noData)
                    return
                }
                do {
                    let staged = try MediaStore.stageData(data, originalName: name)
                    continuation.resume(returning: staged)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Last resort for senders that only offer an in-memory image or a file URL object.
    private static func stageLoadedObject(_ provider: NSItemProvider, name: String?) async throws -> StagedImage {
        if provider.canLoadObject(ofClass: UIImage.self) {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StagedImage, any Error>) in
                _ = provider.loadObject(ofClass: UIImage.self) { object, error in
                    guard let image = object as? UIImage, let data = image.pngData() else {
                        continuation.resume(throwing: error ?? MediaError.noData)
                        return
                    }
                    do {
                        continuation.resume(returning: try MediaStore.stageData(data, originalName: name))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        if provider.canLoadObject(ofClass: URL.self) {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StagedImage, any Error>) in
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url, url.isFileURL else {
                        continuation.resume(throwing: error ?? MediaError.noData)
                        return
                    }
                    do {
                        continuation.resume(returning: try MediaStore.stageFile(at: url, originalName: name))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        throw MediaError.noData
    }
}
