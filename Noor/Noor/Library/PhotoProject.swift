import Foundation
import CoreGraphics

/// One photo in the Noor library: a byte-exact copy of the original file plus the recipe that edits it.
///
/// On disk a project is a folder, `Application Support/Library/<id>/`, holding the original file
/// (exact bytes, original file name and extension) and `project.json` (this value). The original is
/// never modified: preview, thumbnails and export all re-render it through `recipe`.
///
/// The source facts (`typeIdentifier`, pixel size, RAW / HDR flags, bit depth) are read once at import
/// with `PhotoDocument(url:)`, so the library grid can show its badges without opening any file.
struct PhotoProject: Codable, Identifiable, Hashable, Sendable {
    /// Also the name of the project folder.
    var id: UUID
    /// Stored name inside the project folder; keeps the original extension (`IMG_1234.HEIC`).
    var originalFileName: String
    /// UTType identifier of the original (`public.heic`, `com.adobe.raw-image`, ...).
    var typeIdentifier: String
    /// When the photo was added to Noor. The library is sorted by this, newest first.
    var createdAt: Date
    /// Last time the recipe changed.
    var modifiedAt: Date
    /// The whole edit. A new project starts with `EditRecipe()` (RAW: the camera defaults).
    var recipe: EditRecipe
    /// Upright (orientation applied) full-resolution size; for RAW, the developed size.
    var pixelWidth: Int
    var pixelHeight: Int
    var isRAW: Bool
    /// Gain-map or PQ / HLG original.
    var isHDR: Bool
    /// Bits per channel of the original (8, 10, 12, 14, 16, 32).
    var bitsPerComponent: Int

    /// The original file name without its extension ("IMG_1234").
    var displayName: String {
        let base = (originalFileName as NSString).deletingPathExtension
        return base.isEmpty ? originalFileName : base
    }

    // MARK: Derived

    /// Full-resolution upright size in pixels.
    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }

    /// True when the recipe changes anything at all (tone, colour, effects or geometry).
    var isEdited: Bool { !recipe.isIdentity }

    /// Lowercased extension of the stored original ("heic", "dng", ...).
    var fileExtension: String { (originalFileName as NSString).pathExtension.lowercased() }

    // MARK: Coding

    enum CodingKeys: String, CodingKey {
        case id, originalFileName, typeIdentifier, createdAt, modifiedAt, recipe
        case pixelWidth, pixelHeight, isRAW, isHDR, bitsPerComponent
    }
}

// MARK: - Tolerant decoding

extension PhotoProject {
    /// Decodes `project.json`. Only `id` and `originalFileName` are required: every other missing or
    /// malformed value falls back to a safe default, so a project written by an older (or newer) Noor
    /// still opens instead of disappearing from the library.
    ///
    /// Declared in an extension so the memberwise initializer stays available.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let id = try c.decode(UUID.self, forKey: .id)
        let originalFileName = try c.decode(String.self, forKey: .originalFileName)
        let created = value(.createdAt, Date.distantPast)
        self.init(id: id,
                  originalFileName: originalFileName,
                  typeIdentifier: value(.typeIdentifier, ""),
                  createdAt: created,
                  modifiedAt: value(.modifiedAt, created),
                  recipe: value(.recipe, EditRecipe()),
                  pixelWidth: max(0, value(.pixelWidth, 0)),
                  pixelHeight: max(0, value(.pixelHeight, 0)),
                  isRAW: value(.isRAW, false),
                  isHDR: value(.isHDR, false),
                  bitsPerComponent: max(1, value(.bitsPerComponent, 8)))
    }
}

// MARK: - Ordering

extension PhotoProject {
    /// Library order: newest first; ties (same import instant) broken by id so the order is stable
    /// across launches.
    static func libraryOrder(_ a: PhotoProject, _ b: PhotoProject) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}
