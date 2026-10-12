import Foundation
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Export settings
//
// Everything the export sheet lets the user choose, plus the values the exporter hands back.
// The defaults are Noor's "zero quality loss" promise: same format family as the original,
// full resolution, the source colour profile, all metadata, HDR kept.

/// Output file format. `.original` means "same family as the original, at its best quality"
/// and is resolved by `Exporter.plan` (JPEG → JPEG, PNG → PNG 16, TIFF/RAW → TIFF 16, HEIF → HEIF 10).
enum ExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case original   // same family as the source; an unedited photo is copied byte for byte
    case heif10     // HEVC 10-bit: the best lossy format
    case tiff16     // 16-bit per channel, uncompressed: the lossless master
    case png16      // 16-bit per channel, lossless
    case jpeg       // 8-bit, lossy, most compatible
    case heif8      // HEVC 8-bit (the classic iPhone HEIC)

    var id: String { rawValue }
}

/// Output pixel size. Exports never upscale: a long edge larger than the photo keeps full size.
enum ExportSize: Codable, Hashable, Sendable {
    case original
    case longEdge(Int)
}

/// Output colour space. `.matchSource` embeds the original's ICC profile when it is an RGB,
/// non-HDR profile, otherwise Display P3. ProPhoto is only used for 16-bit files (P3 otherwise).
enum ExportColorSpace: String, Codable, CaseIterable, Identifiable, Sendable {
    case matchSource, displayP3, sRGB, adobeRGB, proPhoto

    var id: String { rawValue }
}

/// The user's export choices. Persisted inside `AppSettings`, so decoding is tolerant:
/// a missing or unknown value falls back to its default instead of failing.
struct ExportOptions: Codable, Hashable, Sendable {
    var format: ExportFormat = .original
    var size: ExportSize = .original
    var colorSpace: ExportColorSpace = .matchSource
    var quality: Double = 1.0          // JPEG/HEIF only, 0.5…1.0
    var keepMetadata = true
    var keepLocation = true
    var keepHDR = true
    var fileName: String? = nil       // base name without extension; nil = "<original>-noor"

    enum CodingKeys: String, CodingKey {
        case format, size, colorSpace, quality, keepMetadata, keepLocation, keepHDR, fileName
    }
}

extension ExportOptions {
    // Declared in an extension so the memberwise and `init()` initializers stay available.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportOptions()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.init()
        format = v(.format, d.format)
        size = v(.size, d.size)
        colorSpace = v(.colorSpace, d.colorSpace)
        let q = v(.quality, d.quality)
        quality = q.isFinite ? min(max(q, 0.5), 1.0) : d.quality
        keepMetadata = v(.keepMetadata, d.keepMetadata)
        keepLocation = v(.keepLocation, d.keepLocation)
        keepHDR = v(.keepHDR, d.keepHDR)
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? d.fileName
    }
}

// MARK: - Plan and result

/// What an export with the current options will produce. Cheap to compute (no pixel work),
/// so the export sheet can show "6048 × 4024 · HEIF 10-bit · Display P3 · ≈ 14 MB" live.
struct ExportPlan: Equatable, Sendable {
    var format: ExportFormat           // resolved (never .original)
    var pixelSize: CGSize
    var bitsPerComponent: Int
    var colorSpaceName: String         // e.g. "Display P3"
    var isPassthrough: Bool            // byte-identical copy of the original (or original pixels, location removed)
    var writesHDR: Bool
    var estimatedBytes: Int64
    var fileExtension: String
    var contentType: UTType
}

/// The finished file. It lives in its own folder under `tmp/Exports/<uuid>/` so the file name
/// shown by Files / the share sheet is clean; `Exporter.discard(_:)` removes it when done.
struct ExportResult: Sendable {
    var url: URL
    var contentType: UTType
    var pixelSize: CGSize
    var bitsPerComponent: Int
    var colorSpaceName: String
    var fileSize: Int64
    var wasPassthrough: Bool           // original pixels untouched (byte copy or lossless metadata edit)
    var containsHDR: Bool              // gain map (Adaptive HDR) or the original HDR file
}

/// Coarse progress reported by `Exporter.export`. Core Image renders lazily, so most of the
/// GPU time is spent during `.encoding`.
enum ExportStage: Sendable {
    case preparing      // reading metadata, deciding passthrough
    case rendering      // decoding the original and building the edit graph
    case encoding       // rendering + writing the file
    case finishing      // metadata merge and read-back verification
}

// MARK: - Errors

/// Every failure the export and save paths can report, with a short message for an alert.
enum ExportError: LocalizedError {
    case sourceUnreadable
    case renderFailed
    case tooLarge(width: Int, height: Int)
    case encodeFailed(reason: String)
    case verificationFailed
    case fileSystem(reason: String)
    case cancelled
    case fileMissing
    case photosAccessDenied
    case photosRejectedFile
    case notEnoughSpace
    case photosSaveFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .sourceUnreadable:
            return String(localized: "The original photo couldn’t be read.")
        case .renderFailed:
            return String(localized: "The edited photo couldn’t be rendered.")
        case .tooLarge(let width, let height):
            return String(localized: "The photo is too large to export at \(width) × \(height). Choose a smaller size.")
        case .encodeFailed(let reason):
            return String(localized: "The file couldn’t be written. \(reason)")
        case .verificationFailed:
            return String(localized: "The exported file didn’t pass verification, so it wasn’t kept.")
        case .fileSystem(let reason):
            return String(localized: "The export file couldn’t be created. \(reason)")
        case .cancelled:
            return String(localized: "The export was cancelled.")
        case .fileMissing:
            return String(localized: "The exported file is no longer available. Export it again.")
        case .photosAccessDenied:
            return String(localized: "Noor isn’t allowed to add photos. Allow access in Settings › Privacy & Security › Photos.")
        case .photosRejectedFile:
            return String(localized: "Photos doesn’t accept this file type. Save it to Files instead.")
        case .notEnoughSpace:
            return String(localized: "There isn’t enough storage space to save the photo.")
        case .photosSaveFailed(let reason):
            return String(localized: "The photo couldn’t be saved to Photos. \(reason)")
        }
    }
}
