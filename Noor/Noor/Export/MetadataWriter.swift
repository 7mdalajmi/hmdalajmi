import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Source metadata
//
// Export metadata pipeline (research export-photos.md §2):
//   1. `MetadataWriter.properties(...)` builds a sanitized EXIF/TIFF/IPTC/GPS dictionary
//      (orientation 1, output pixel size, Software = Noor, location removed on request).
//      The exporter attaches it with `CIImage.settingProperties(_:)` and encodes once.
//   2. `mergeXMP(...)` losslessly merges the original's remaining XMP (keywords, rating, title,
//      creator, …) into the encoded file with `CGImageDestinationCopyImageSource`.
//   3. `inspect(_:)` reads the file back so the exporter can verify size, orientation, EXIF,
//      location and gain map before handing the file to the user.
// Nothing here decodes or re-encodes pixels.

/// Metadata of an original file, read once without decoding pixels and cached per URL
/// (originals are never modified, so the cache can't go stale).
/// Immutable after `init`, so it is safe to share between threads.
final class ExportSourceMetadata: @unchecked Sendable {
    /// `CGImageSourceCopyPropertiesAtIndex` of the primary image.
    let properties: [String: Any]
    /// The XMP packet (and EXIF/IPTC mirrored into XMP), if any.
    let xmp: CGImageMetadata?
    /// The embedded colour space (nil for RAW, where the decoder defines colour).
    let colorSpace: CGColorSpace?
    /// UTType identifier sniffed by ImageIO.
    let typeIdentifier: String?
    /// Size of the original file in bytes.
    let fileSize: Int64
    /// False when ImageIO couldn't open the file at all.
    let isReadable: Bool

    init(url: URL, isRAW: Bool) {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        var properties: [String: Any] = [:]
        var xmp: CGImageMetadata?
        var colorSpace: CGColorSpace?
        var typeIdentifier: String?
        var readable = false
        if let source = CGImageSourceCreateWithURL(url as CFURL, noCache) {
            let index = CGImageSourceGetPrimaryImageIndex(source)
            properties = (CGImageSourceCopyPropertiesAtIndex(source, index, noCache) as? [String: Any]) ?? [:]
            xmp = CGImageSourceCopyMetadataAtIndex(source, index, nil)
            typeIdentifier = CGImageSourceGetType(source) as String?
            if !isRAW {
                // Creating the CGImage only parses the header; pixels are decoded on first access,
                // which never happens here. We only want its colour space.
                colorSpace = CGImageSourceCreateImageAtIndex(source, index, noCache)?.colorSpace
            }
            readable = true
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        self.properties = properties
        self.xmp = xmp
        self.colorSpace = colorSpace
        self.typeIdentifier = typeIdentifier
        self.fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        self.isReadable = readable
    }

    // MARK: Derived facts

    /// The original has an EXIF dictionary worth carrying over.
    var hasExif: Bool {
        guard let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return false }
        return !exif.isEmpty
    }

    /// GPS coordinates, IPTC location names or XMP location tags are present.
    var hasLocation: Bool {
        MetadataWriter.containsLocation(properties: properties, xmp: xmp)
    }

    // MARK: Cache

    private static let cache: NSCache<NSURL, ExportSourceMetadata> = {
        let cache = NSCache<NSURL, ExportSourceMetadata>()
        cache.countLimit = 8
        return cache
    }()

    /// Cached metadata for an original (NSCache is thread-safe).
    static func cached(for url: URL, isRAW: Bool) -> ExportSourceMetadata {
        let key = url as NSURL
        if let hit = cache.object(forKey: key) { return hit }
        let fresh = ExportSourceMetadata(url: url, isRAW: isRAW)
        if fresh.isReadable { cache.setObject(fresh, forKey: key) }
        return fresh
    }
}

// MARK: - Read-back

/// What an exported file actually contains, read back with ImageIO.
struct ExportFileInspection {
    var pixelSize: CGSize
    var orientation: Int
    var exif: [String: Any]
    var hasGPS: Bool                 // a non-empty {GPS} dictionary (definitive)
    var hasLocationTags: Bool        // GPS, IPTC or XMP location data (broad, privacy-first heuristic)
    var hasGainMap: Bool
}

// MARK: - Metadata writer

/// Builds, merges and verifies export metadata. Stateless and thread-safe.
enum MetadataWriter {
    /// Written to TIFF Software in every export that keeps metadata.
    static let softwareName = "Noor"

    private static func key(_ name: CFString) -> String { name as String }

    // MARK: Sanitized properties (§2.3)

    /// The properties dictionary to attach with `CIImage.settingProperties(_:)`.
    /// - Parameters:
    ///   - outputSize: final pixel size (written to EXIF PixelX/YDimension).
    ///   - isSRGB: output profile is sRGB (EXIF ColorSpace 1, otherwise 0xFFFF "uncalibrated").
    ///   - pixelGridChanged: crop/rotate/flip/straighten or resize happened, so pixel-coordinate
    ///     tags (SubjectArea, SubjectLocation) no longer apply.
    static func properties(from source: ExportSourceMetadata, outputSize: CGSize, isSRGB: Bool,
                           keepMetadata: Bool, keepLocation: Bool, pixelGridChanged: Bool) -> [String: Any] {
        let src = source.properties
        // Orientation is baked into the pixels, so the file must always say "up".
        var out: [String: Any] = [key(kCGImagePropertyOrientation): 1]
        guard keepMetadata else { return out }

        for k in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let value = src[key(k)] { out[key(k)] = value }
        }

        if var exif = src[key(kCGImagePropertyExifDictionary)] as? [String: Any] {
            exif[key(kCGImagePropertyExifPixelXDimension)] = Int(outputSize.width)
            exif[key(kCGImagePropertyExifPixelYDimension)] = Int(outputSize.height)
            exif[key(kCGImagePropertyExifColorSpace)] = isSRGB ? 1 : 0xFFFF
            if pixelGridChanged {
                exif.removeValue(forKey: key(kCGImagePropertyExifSubjectArea))
                exif.removeValue(forKey: key(kCGImagePropertyExifSubjectLocation))
            }
            out[key(kCGImagePropertyExifDictionary)] = exif
        }
        if let aux = src[key(kCGImagePropertyExifAuxDictionary)] as? [String: Any], !aux.isEmpty {
            out[key(kCGImagePropertyExifAuxDictionary)] = aux
        }

        // TIFF: keep descriptive tags only; never the original's layout/compression tags.
        let tiffSource = (src[key(kCGImagePropertyTIFFDictionary)] as? [String: Any]) ?? [:]
        var tiff = tiffSource.filter { allowedTIFFKeys.contains($0.key) }
        tiff[key(kCGImagePropertyTIFFOrientation)] = 1
        tiff[key(kCGImagePropertyTIFFSoftware)] = softwareName
        out[key(kCGImagePropertyTIFFDictionary)] = tiff

        if var iptc = src[key(kCGImagePropertyIPTCDictionary)] as? [String: Any] {
            iptc.removeValue(forKey: key(kCGImagePropertyIPTCImageOrientation))
            if !keepLocation {
                iptc = iptc.filter { !MetadataWriter.isIPTCLocationKey($0.key) }
            }
            if !iptc.isEmpty { out[key(kCGImagePropertyIPTCDictionary)] = iptc }
        }

        if keepLocation, let gps = src[key(kCGImagePropertyGPSDictionary)] as? [String: Any], !gps.isEmpty {
            out[key(kCGImagePropertyGPSDictionary)] = gps
        }

        // MakerApple: Apple documents keys 33 and 48 as inputs to the ORIGINAL gain map's headroom.
        // Noor writes its own (ISO) gain map, so they would be wrong. ExcludeGPS can't filter
        // maker notes, so the whole dictionary goes when location must be removed.
        if keepLocation, var apple = src[key(kCGImagePropertyMakerAppleDictionary)] as? [String: Any] {
            apple.removeValue(forKey: "33")
            apple.removeValue(forKey: "48")
            if !apple.isEmpty { out[key(kCGImagePropertyMakerAppleDictionary)] = apple }
        }
        // Deliberately never copied: PixelWidth/Height, Depth, ColorModel, ProfileName, HasAlpha,
        // {DNG}, {Raw}, {CIFF}, {JFIF}, {PNG}, {HEICS} and other maker dictionaries.
        return out
    }

    private static let allowedTIFFKeys: Set<String> = [
        kCGImagePropertyTIFFMake as String, kCGImagePropertyTIFFModel as String,
        kCGImagePropertyTIFFDateTime as String, kCGImagePropertyTIFFArtist as String,
        kCGImagePropertyTIFFCopyright as String, kCGImagePropertyTIFFImageDescription as String,
        kCGImagePropertyTIFFHostComputer as String, kCGImagePropertyTIFFXResolution as String,
        kCGImagePropertyTIFFYResolution as String, kCGImagePropertyTIFFResolutionUnit as String,
    ]

    /// A key in the EXIF dictionary whose presence proves the encoder wrote the original's EXIF.
    static func signatureExifKey(of source: ExportSourceMetadata) -> String? {
        guard let exif = source.properties[key(kCGImagePropertyExifDictionary)] as? [String: Any] else { return nil }
        let candidates = [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifExposureTime,
                          kCGImagePropertyExifFNumber, kCGImagePropertyExifFocalLength,
                          kCGImagePropertyExifLensModel]
        return candidates.map { $0 as String }.first { exif[$0] != nil }
    }

    // MARK: Location detection

    private static func isIPTCLocationKey(_ key: String) -> Bool {
        let named: Set<String> = [
            kCGImagePropertyIPTCCity as String, kCGImagePropertyIPTCSubLocation as String,
            kCGImagePropertyIPTCProvinceState as String,
            kCGImagePropertyIPTCCountryPrimaryLocationName as String,
            kCGImagePropertyIPTCCountryPrimaryLocationCode as String,
        ]
        return named.contains(key) || key.localizedCaseInsensitiveContains("location")
    }

    /// XMP paths ("prefix:Name") that describe where the photo was taken.
    static func isLocationTag(_ path: String) -> Bool {
        let lower = path.lowercased()
        let explicit: Set<String> = ["photoshop:city", "photoshop:state", "photoshop:country",
                                     "iptc4xmpcore:countrycode"]
        if explicit.contains(lower) { return true }
        let name = lower.split(separator: ":").last.map(String.init) ?? lower
        if name == "subjectlocation" { return false }     // EXIF focus point, not a place
        return name.contains("gps") || name.contains("latitude") || name.contains("longitude")
            || name.contains("location")
    }

    /// Top-level XMP paths that carry location data.
    static func locationTagPaths(in xmp: CGImageMetadata) -> [String] {
        var paths: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(xmp, nil, nil) { path, _ in
            let p = path as String
            if MetadataWriter.isLocationTag(p) { paths.append(p) }
            return true
        }
        return paths
    }

    static func containsLocation(properties: [String: Any], xmp: CGImageMetadata?) -> Bool {
        if let gps = properties[key(kCGImagePropertyGPSDictionary)] as? [String: Any], !gps.isEmpty { return true }
        if let iptc = properties[key(kCGImagePropertyIPTCDictionary)] as? [String: Any],
           iptc.keys.contains(where: { MetadataWriter.isIPTCLocationKey($0) }) {
            return true
        }
        if let xmp, !locationTagPaths(in: xmp).isEmpty { return true }
        return false
    }

    // MARK: Lossless XMP merge (§2.2 step 2)

    /// XMP namespaces never carried into a rendered export.
    private static let droppedXMPPrefixes: Set<String> = [
        "exif", "exifEX", "tiff", "aux",                 // already written from the properties dictionary
        "crs",                                           // Camera Raw develop settings would re-apply edits
        "HDRGainMap", "hdrgm",                           // describe the ORIGINAL gain map
        "GCamera", "GContainer", "Container", "Item",    // Android motion/depth containers that are gone
        "GImage", "GDepth", "apdi",
        "xmpMM", "xmpNote",                              // document identity / extended-XMP pointers of the original
    ]
    /// Region tags in pixel coordinates; dropped when the pixel grid changed.
    private static let regionXMPPrefixes: Set<String> = ["mwg-rs", "MP", "MPRI", "MPReg", "apple-fi"]
    /// Single tags that describe the original file rather than the photo.
    private static let droppedXMPPaths: Set<String> = ["xmp:CreatorTool", "photoshop:ICCProfile", "photoshop:ColorMode"]

    /// Merges the original's descriptive XMP into `url` without touching the encoded pixels.
    /// Returns false (and leaves the file unchanged) when there is nothing to merge, when the
    /// container doesn't support a lossless rewrite, or when the rewritten file fails the check.
    @discardableResult
    static func mergeXMP(from source: ExportSourceMetadata, into url: URL, type: UTType,
                         keepLocation: Bool, pixelGridChanged: Bool) -> Bool {
        guard let xmp = source.xmp, let filtered = CGImageMetadataCreateMutableCopy(xmp) else { return false }
        var total = 0
        var drop: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(xmp, nil, nil) { path, tag in
            total += 1
            let p = path as String
            let prefix = (CGImageMetadataTagCopyPrefix(tag) as String?)
                ?? p.split(separator: ":").first.map(String.init) ?? ""
            if MetadataWriter.droppedXMPPrefixes.contains(prefix) || MetadataWriter.droppedXMPPaths.contains(p)
                || (pixelGridChanged && MetadataWriter.regionXMPPrefixes.contains(prefix))
                || (!keepLocation && MetadataWriter.isLocationTag(p)) {
                drop.append(p)
            }
            return true
        }
        guard total > drop.count else { return false }   // nothing descriptive left to merge
        for path in drop {
            _ = CGImageMetadataRemoveTagWithPath(filtered, nil, path as CFString)
        }

        var options: [CFString: Any] = [
            kCGImageDestinationMetadata: filtered,
            kCGImageDestinationMergeMetadata: true,
        ]
        if !keepLocation { options[kCGImageMetadataShouldExcludeGPS] = true }
        return rewriteLosslessly(url, type: type, options: options) { before, after in
            after.pixelSize == before.pixelSize
                && (!before.hasGainMap || after.hasGainMap)
                && (before.exif.isEmpty || !after.exif.isEmpty)
                && (keepLocation || !after.hasGPS)
        }
    }

    // MARK: Lossless location strip (passthrough with "Remove location")

    /// Copies `source` to `destination` with GPS and location tags removed and the encoded
    /// image data untouched (`CGImageDestinationCopyImageSource`). Documented for JPEG, PNG and
    /// TIFF; tried for HEIF. Returns false (no file left behind) if it can't be done or the
    /// result still contains location data, so the caller can fall back to a re-encode.
    static func copyRemovingLocation(from source: URL, to destination: URL, type: UTType) -> Bool {
        guard let before = inspect(source),
              let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let target = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { return false }
        let index = CGImageSourceGetPrimaryImageIndex(imageSource)
        var options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        // Merge mode removes a tag whose value is kCFNull (CGImageDestination.h).
        if let xmp = CGImageSourceCopyMetadataAtIndex(imageSource, index, nil),
           let removal = locationRemovalMetadata(for: xmp) {
            options[kCGImageDestinationMetadata] = removal
            options[kCGImageDestinationMergeMetadata] = true
        }
        let copied = CGImageDestinationCopyImageSource(target, imageSource, options as CFDictionary, nil)
        guard copied, let after = inspect(destination),
              after.pixelSize == before.pixelSize,
              !after.hasGPS, !after.hasLocationTags,
              !before.hasGainMap || after.hasGainMap
        else {
            try? FileManager.default.removeItem(at: destination)
            return false
        }
        return true
    }

    /// A metadata object holding only the location tags of `xmp`, each set to kCFNull.
    private static func locationRemovalMetadata(for xmp: CGImageMetadata) -> CGMutableImageMetadata? {
        let locationPaths = Set(locationTagPaths(in: xmp))
        guard !locationPaths.isEmpty, let removal = CGImageMetadataCreateMutableCopy(xmp) else { return nil }
        var others: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(xmp, nil, nil) { path, _ in
            let p = path as String
            if !locationPaths.contains(p) { others.append(p) }
            return true
        }
        for path in others {
            _ = CGImageMetadataRemoveTagWithPath(removal, nil, path as CFString)
        }
        var anySet = false
        for path in locationPaths {
            // NSNull bridges to kCFNull. If ImageIO refuses the value, drop the tag from the
            // request instead (the read-back check then decides whether a re-encode is needed).
            if CGImageMetadataSetValueWithPath(removal, nil, path as CFString, NSNull()) {
                anySet = true
            } else {
                _ = CGImageMetadataRemoveTagWithPath(removal, nil, path as CFString)
            }
        }
        return anySet ? removal : nil
    }

    // MARK: Orientation repair

    /// Sets Orientation = 1 without touching pixels (only needed if an encoder kept a stale tag).
    static func resetOrientation(of url: URL, type: UTType) -> Bool {
        let options: [CFString: Any] = [kCGImageDestinationOrientation: 1]
        return rewriteLosslessly(url, type: type, options: options) { before, after in
            after.orientation == 1 && after.pixelSize == before.pixelSize
                && (!before.hasGainMap || after.hasGainMap)
        }
    }

    // MARK: Read-back (§2.2 step 3)

    /// Reads what a file really contains. Nil if ImageIO can't open it.
    static func inspect(_ url: URL) -> ExportFileInspection? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else { return nil }
        let width = (props[key(kCGImagePropertyPixelWidth)] as? NSNumber)?.intValue ?? 0
        let height = (props[key(kCGImagePropertyPixelHeight)] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        let orientation = (props[key(kCGImagePropertyOrientation)] as? NSNumber)?.intValue ?? 1
        let exif = (props[key(kCGImagePropertyExifDictionary)] as? [String: Any]) ?? [:]
        let gps = (props[key(kCGImagePropertyGPSDictionary)] as? [String: Any]) ?? [:]
        let xmp = CGImageSourceCopyMetadataAtIndex(source, index, nil)
        return ExportFileInspection(
            pixelSize: CGSize(width: width, height: height),
            orientation: orientation,
            exif: exif,
            hasGPS: !gps.isEmpty,
            hasLocationTags: containsLocation(properties: props, xmp: xmp),
            hasGainMap: hasGainMap(source, index: index))
    }

    /// True when the file carries an HDR gain map (Apple, or ISO/Adaptive HDR on iOS 18+).
    static func hasGainMap(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return hasGainMap(source, index: CGImageSourceGetPrimaryImageIndex(source))
    }

    private static func hasGainMap(_ source: CGImageSource, index: Int) -> Bool {
        if #available(iOS 18.0, *),
           CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, kCGImageAuxiliaryDataTypeISOGainMap) != nil {
            return true
        }
        return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
    }

    /// The gain-map auxiliary image of `url` (data, description and metadata), so a re-written
    /// file can carry exactly the same gain map.
    static func gainMapAuxiliaryData(at url: URL) -> (type: CFString, info: CFDictionary)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        if #available(iOS 18.0, *),
           let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, kCGImageAuxiliaryDataTypeISOGainMap) {
            return (kCGImageAuxiliaryDataTypeISOGainMap, info)
        }
        if let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, kCGImageAuxiliaryDataTypeHDRGainMap) {
            return (kCGImageAuxiliaryDataTypeHDRGainMap, info)
        }
        return nil
    }

    // MARK: File plumbing

    /// Runs `CGImageDestinationCopyImageSource` from `url` into a sibling temp file and swaps
    /// it in only if `accept(before, after)` holds. The encoded image data is never modified.
    private static func rewriteLosslessly(_ url: URL, type: UTType, options: [CFString: Any],
                                          accept: (ExportFileInspection, ExportFileInspection) -> Bool) -> Bool {
        guard let before = inspect(url),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let temp = siblingTemporaryURL(for: url)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil),
              CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil),
              let after = inspect(temp), accept(before, after)
        else { return false }
        return (try? replaceFile(at: url, with: temp)) != nil
    }

    /// A unique, hidden file next to `url` with the same extension.
    static func siblingTemporaryURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".noor-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
    }

    /// Replaces `url` with `replacement` (which is moved, not copied).
    static func replaceFile(at url: URL, with replacement: URL) throws {
        let fm = FileManager.default
        do {
            _ = try fm.replaceItemAt(url, withItemAt: replacement)
        } catch {
            try? fm.removeItem(at: url)
            try fm.moveItem(at: replacement, to: url)
        }
    }
}
