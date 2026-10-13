import Foundation
import Photos
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Save to Photos

/// Adds an exported file to the photo library as a new asset with its exact bytes
/// (no re-encode by Photos). Needs only add-only access (`NSPhotoLibraryAddUsageDescription`).
enum PhotoLibrarySaver {
    /// Saves `result.url` as a new photo. Throws a localized `ExportError` on failure.
    static func save(_ result: ExportResult) async throws {
        let url = result.url
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw ExportError.fileMissing }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized, .limited:
            break
        case .denied, .restricted, .notDetermined:
            throw ExportError.photosAccessDenied
        @unknown default:
            throw ExportError.photosAccessDenied
        }

        let fileName = url.lastPathComponent
        let typeIdentifier = result.contentType.identifier
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileName
                options.uniformTypeIdentifier = typeIdentifier
                options.shouldMoveFile = false        // the file stays available for Files / Share
                request.addResource(with: .photo, fileURL: url, options: options)
            }
        } catch let error as PHPhotosError {
            switch error.code {
            case .accessUserDenied, .accessRestricted:
                throw ExportError.photosAccessDenied
            case .invalidResource:
                throw ExportError.photosRejectedFile
            case .notEnoughSpace:
                throw ExportError.notEnoughSpace
            default:
                throw ExportError.photosSaveFailed(reason: error.localizedDescription)
            }
        } catch {
            throw ExportError.photosSaveFailed(reason: error.localizedDescription)
        }
    }
}

// MARK: - Save to Files / Share

/// An exported file for `fileExporter(isPresented:item:contentTypes:…)` and `ShareLink`.
/// Exactly one representation matches the file's real type, so a HEIF is never offered as JPEG.
struct ExportedFile: Transferable {
    let url: URL
    let contentType: UTType

    /// The types with a dedicated representation; anything else is offered as a generic image.
    fileprivate static let specificTypes: [UTType] = [.heic, .heif, .jpeg, .png, .tiff]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .heic) { SentTransferredFile($0.url) }
            .exportingCondition { $0.contentType == .heic }
        FileRepresentation(exportedContentType: .heif) { SentTransferredFile($0.url) }
            .exportingCondition { $0.contentType == .heif }
        FileRepresentation(exportedContentType: .jpeg) { SentTransferredFile($0.url) }
            .exportingCondition { $0.contentType == .jpeg }
        FileRepresentation(exportedContentType: .png) { SentTransferredFile($0.url) }
            .exportingCondition { $0.contentType == .png }
        FileRepresentation(exportedContentType: .tiff) { SentTransferredFile($0.url) }
            .exportingCondition { $0.contentType == .tiff }
        FileRepresentation(exportedContentType: .image) { SentTransferredFile($0.url) }
            .exportingCondition { !ExportedFile.specificTypes.contains($0.contentType) }
    }
}

extension ExportedFile {
    /// The file of a finished export.
    init(_ result: ExportResult) {
        self.init(url: result.url, contentType: result.contentType)
    }
}
