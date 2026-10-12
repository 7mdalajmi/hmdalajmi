import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

// MARK: - Exporter
//
// Prime directive: zero quality loss. An export is always ONE encode of the original re-rendered
// through the recipe (never a re-encode of an encoded file), or no encode at all:
//   * Passthrough: an unedited photo in its own container is copied byte for byte; if only the
//     location must go, ImageIO rewrites the metadata without touching the image data.
//   * Render: fresh full-resolution decode → RecipeRenderer → optional Lanczos downsize →
//     fitToSDR (SDR targets) → CIContext.write…Representation straight to a file URL.
//     HDR sources on iOS 18+ also pass the unfitted render as `.hdrImage`, so Core Image writes
//     an Adaptive HDR file (SDR base + ISO gain map).
//   * Metadata: sanitized properties ride on the CIImage, the original's descriptive XMP is merged
//     losslessly afterwards, and the file is read back and verified before it is returned.

/// Builds export plans and writes export files. Stateless; `export` is synchronous and heavy,
/// so callers run it from `Task.detached`. Safe to call from any thread.
enum Exporter {

    // MARK: Plan

    /// What `export` would produce for these options. No pixel work (reads the original's
    /// metadata once, then cached), so the export sheet can call it on every change.
    static func plan(document: PhotoDocument, recipe: EditRecipe, options: ExportOptions) -> ExportPlan {
        let info = document.info
        let source = ExportSourceMetadata.cached(for: document.url, isRAW: info.isRAW)
        let format = resolvedFormat(options.format, info: info)
        let route = passthroughRoute(document: document, recipe: recipe, options: options,
                                     format: format, source: source)
        // A location strip is lossless for JPEG/PNG/TIFF; for HEIF it may need a re-encode,
        // so the plan conservatively describes the re-encode.
        let copyFormat = passthroughFormat(format, info: info, source: source)
        if route == .copy || (route == .stripLocation && container(of: copyFormat) != .heif) {
            return passthroughPlan(document: document, format: copyFormat, source: source)
        }

        let hdr = shouldWriteHDR(info: info, recipe: recipe, options: options, format: format)
        let fullSize = recipe.geometry.clamped().outputSize(for: document.uprightSize)
        let pixelSize = targetSize(for: fullSize, size: options.size)
        var bits = nominalBits(format)
        if format == .heif10, hdr, info.bitsPerComponent <= 8, EncoderCapabilities.shared.heif10SupportsGainMap == false {
            bits = 8   // this OS writes the gain map only with an 8-bit base (see encodeHEIF10)
        }
        let color = colorTarget(options.colorSpace, bits: nominalBits(format), info: info, source: source)
        let estimate = estimatedBytes(format: format, pixels: Double(pixelSize.width * pixelSize.height),
                                      quality: options.quality, hdr: hdr)
        return ExportPlan(format: format,
                          pixelSize: pixelSize,
                          bitsPerComponent: bits,
                          colorSpaceName: color.name,
                          isPassthrough: false,
                          writesHDR: hdr,
                          estimatedBytes: estimate,
                          fileExtension: fileExtension(for: format),
                          contentType: contentType(for: format))
    }

    // MARK: Export

    /// Writes the export into a fresh folder `tmp/Exports/<uuid>/<name>.<ext>` and returns it.
    /// Synchronous and GPU/CPU heavy: call from `Task.detached`. Honours task cancellation
    /// between stages. On failure nothing is left on disk.
    /// - Parameter baseName: the original's display name; the file is called
    ///   `options.fileName` or "<baseName>-noor".
    static func export(document: PhotoDocument, recipe: EditRecipe, options: ExportOptions, baseName: String,
                       progress: @escaping @Sendable (ExportStage) -> Void) throws -> ExportResult {
        progress(.preparing)
        try checkCancelled()
        removeStaleExports()
        let info = document.info
        let source = ExportSourceMetadata.cached(for: document.url, isRAW: info.isRAW)
        let format = resolvedFormat(options.format, info: info)
        let name = exportFileBaseName(requested: options.fileName, fallback: baseName)
        let directory = try makeExportDirectory()
        do {
            return try autoreleasepool {
                try exportFile(document: document, recipe: recipe, options: options, format: format,
                               source: source, directory: directory, name: name, progress: progress)
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw mapped(error)
        }
    }

    /// Deletes an export's temporary folder once it has been saved or shared. Only touches
    /// folders created by `export`.
    static func discard(_ result: ExportResult) {
        let folder = result.url.deletingLastPathComponent()
        // Compare path components: `path(percentEncoded:)` keeps a directory URL's trailing "/",
        // which would make two spellings of the same folder compare unequal.
        let parent = folder.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let root = exportsRoot.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard parent == root, folder.lastPathComponent != "..", folder.lastPathComponent != "." else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Pipeline

    private static func exportFile(document: PhotoDocument, recipe: EditRecipe, options: ExportOptions,
                                   format: ExportFormat, source: ExportSourceMetadata, directory: URL,
                                   name: String, progress: @Sendable (ExportStage) -> Void) throws -> ExportResult {
        let info = document.info

        // 1. Passthrough: the original's own bytes (or its own image data with location removed).
        let route = passthroughRoute(document: document, recipe: recipe, options: options,
                                     format: format, source: source)
        if route != .render {
            let copyFormat = passthroughFormat(format, info: info, source: source)
            let type = sourceContentType(info: info, source: source) ?? contentType(for: copyFormat)
            let ext = passthroughExtension(info: info, type: type, format: copyFormat)
            let url = directory.appendingPathComponent(name).appendingPathExtension(ext)
            switch route {
            case .copy:
                progress(.finishing)
                do {
                    try FileManager.default.copyItem(at: document.url, to: url)
                } catch {
                    throw ExportError.fileSystem(reason: error.localizedDescription)
                }
                return passthroughResult(url: url, type: type, document: document)
            case .stripLocation:
                progress(.finishing)
                if MetadataWriter.copyRemovingLocation(from: document.url, to: url, type: type) {
                    return passthroughResult(url: url, type: type, document: document)
                }
                // Not possible losslessly (e.g. HEIF): fall through to a single re-encode.
            case .render:
                break
            }
        }

        // 2. Render the ORIGINAL through the recipe at full resolution.
        progress(.rendering)
        try checkCancelled()
        let wantsHDR = shouldWriteHDR(info: info, recipe: recipe, options: options, format: format)
        // Free the 100 % detail tier and preview caches before allocating a full-size export.
        document.purgeFullResolution()
        RenderEngine.shared.clearCaches()
        guard let base = document.exportBase(for: recipe, hdr: wantsHDR) else {
            throw ExportError.sourceUnreadable
        }
        let renderOptions = RenderOptions(purpose: .export,
                                          renderScale: base.renderScale,
                                          fullSize: document.uprightSize,
                                          rawStageApplied: base.rawStageApplied,
                                          // The airlight only feeds Dehaze; skip the estimate otherwise.
                                          airlight: recipe.clamped().dehaze != 0
                                              ? document.airlight() : SIMD3<Float>(repeating: 1))
        guard let rendered = normalized(RecipeRenderer.render(recipe, base: base.image, options: renderOptions)) else {
            throw ExportError.renderFailed
        }
        let fullSize = rendered.extent.size
        let target = targetSize(for: fullSize, size: options.size)
        let scaled = resized(rendered, to: target)
        let canvas = CGRect(origin: .zero, size: target)
        // The output space decides how the SDR fit treats colours outside Display P3: an Adobe RGB
        // or ProPhoto file can hold them, so they are kept instead of being mapped into P3.
        let color = colorTarget(options.colorSpace, bits: nominalBits(format), info: info, source: source)
        let fitted = color.isWiderThanP3
            ? RecipeRenderer.fitToSDR(scaled, preservingWideGamut: true)
            : RecipeRenderer.fitToSDR(scaled)
        var sdr = opaque(fitted, in: canvas)
        var hdr: CIImage? = (wantsHDR && base.isHDR) ? opaque(scaled, in: canvas) : nil

        let context = RenderEngine.shared.makeExportContext()
        defer { context.clearCaches() }
        let maxSize = context.outputImageMaximumSize()
        guard target.width <= maxSize.width, target.height <= maxSize.height else {
            throw ExportError.tooLarge(width: Int(target.width), height: Int(target.height))
        }

        // 3. Sanitized metadata (written by the encoder from CIImage.properties).
        let pixelGridChanged = !recipe.geometry.clamped().isIdentity || target != fullSize
        func properties(for size: CGSize) -> [String: Any] {
            MetadataWriter.properties(from: source, outputSize: size, isSRGB: color.isSRGB,
                                      keepMetadata: options.keepMetadata, keepLocation: options.keepLocation,
                                      pixelGridChanged: pixelGridChanged)
        }
        var imageProperties = properties(for: target)
        sdr = sdr.settingProperties(imageProperties)
        hdr = hdr?.settingProperties(imageProperties)

        // 4. One encode, straight to the file.
        progress(.encoding)
        try checkCancelled()
        let type = contentType(for: format)
        let url = directory.appendingPathComponent(name).appendingPathExtension(fileExtension(for: format))
        let quality = min(max(options.quality.isFinite ? options.quality : 1, 0.5), 1)
        var outcome = try encode(sdr, hdr: hdr, format: format, colorSpace: color.space, quality: quality,
                                 sourceBits: info.bitsPerComponent, context: context, to: url)
        var outputSize = target

        // HEVC: if the encoder trimmed an odd dimension, redo it with an explicit even crop so the
        // pixels and the metadata agree (still one encode of the in-memory render, never of the file).
        if type == .heic, let written = MetadataWriter.inspect(url)?.pixelSize, written != outputSize {
            let even = CGRect(x: 0, y: 0,
                              width: floor(outputSize.width / 2) * 2, height: floor(outputSize.height / 2) * 2)
            guard even.width >= 2, even.height >= 2 else { throw ExportError.verificationFailed }
            outputSize = even.size
            imageProperties = properties(for: outputSize)
            sdr = sdr.cropped(to: even).settingProperties(imageProperties)
            hdr = hdr?.cropped(to: even).settingProperties(imageProperties)
            try? FileManager.default.removeItem(at: url)
            outcome = try encode(sdr, hdr: hdr, format: format, colorSpace: color.space, quality: quality,
                                 sourceBits: info.bitsPerComponent, context: context, to: url)
        }
        // Encoding is the long stage: honour a Cancel that arrived meanwhile (the caller deletes the folder).
        try checkCancelled()

        // 5. Lossless XMP merge, then read the file back and verify it.
        progress(.finishing)
        if options.keepMetadata {
            MetadataWriter.mergeXMP(from: source, into: url, type: type,
                                    keepLocation: options.keepLocation, pixelGridChanged: pixelGridChanged)
        }
        guard var check = MetadataWriter.inspect(url), check.pixelSize == outputSize else {
            throw ExportError.verificationFailed
        }
        if check.orientation != 1 {
            guard MetadataWriter.resetOrientation(of: url, type: type) else { throw ExportError.verificationFailed }
        }
        // Fallback B: the encoder dropped the EXIF it was given. Write the same in-memory render
        // through ImageIO with explicit properties (keeping the gain map it produced), at the
        // depth actually written (HEIF 10 may have fallen back to an 8-bit base + gain map).
        let writtenFormat: ExportFormat = (format == .heif10 && outcome.bits == 8) ? .heif8 : format
        if options.keepMetadata, let signature = MetadataWriter.signatureExifKey(of: source), check.exif[signature] == nil,
           !EncoderCapabilities.shared.isExifFallbackFutile(for: writtenFormat),
           reencodeWithImageIO(sdr, format: writtenFormat, colorSpace: color.space, properties: imageProperties,
                               quality: quality, gainMapSource: outcome.containsHDR ? url : nil,
                               context: context, type: type, to: url) {
            MetadataWriter.mergeXMP(from: source, into: url, type: type,
                                    keepLocation: options.keepLocation, pixelGridChanged: pixelGridChanged)
            guard let recheck = MetadataWriter.inspect(url), recheck.pixelSize == outputSize,
                  recheck.orientation == 1 else {
                throw ExportError.verificationFailed
            }
            if recheck.exif[signature] == nil {
                EncoderCapabilities.shared.recordFutileExifFallback(for: writtenFormat)
            }
            check = recheck
            outcome.containsHDR = outcome.containsHDR && recheck.hasGainMap
        }
        // Privacy guarantee: never hand out coordinates the user asked to remove (directly, or
        // by removing all metadata).
        if (!options.keepLocation || !options.keepMetadata) && check.hasGPS {
            throw ExportError.verificationFailed
        }

        return ExportResult(url: url,
                            contentType: type,
                            pixelSize: outputSize,
                            bitsPerComponent: outcome.bits,
                            colorSpaceName: color.name,
                            fileSize: fileSize(of: url),
                            wasPassthrough: false,
                            containsHDR: outcome.containsHDR)
    }

    // MARK: Encoding

    private struct EncodeOutcome {
        var bits: Int
        var containsHDR: Bool
    }

    /// Writes `sdr` (and the HDR rendition as a gain map, when given) with Core Image.
    private static func encode(_ sdr: CIImage, hdr: CIImage?, format: ExportFormat, colorSpace: CGColorSpace,
                               quality: Double, sourceBits: Int, context: CIContext,
                               to url: URL) throws -> EncodeOutcome {
        let qualityKey = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        let plain: [CIImageRepresentationOption: Any] = [qualityKey: quality]
        var withHDR = plain
        var hasHDRInput = false
        if #available(iOS 18.0, *), let hdr {
            // Core Image computes an ISO gain map from the HDR / SDR ratio (Adaptive HDR).
            withHDR[.hdrImage] = hdr
            hasHDRInput = true
        }

        switch format {
        case .jpeg:
            try context.writeJPEGRepresentation(of: sdr, to: url, colorSpace: colorSpace, options: withHDR)
            return EncodeOutcome(bits: 8, containsHDR: hasHDRInput && MetadataWriter.hasGainMap(at: url))
        case .heif8:
            try writeHEIF8(sdr, context: context, colorSpace: colorSpace, options: withHDR, to: url)
            return EncodeOutcome(bits: 8, containsHDR: hasHDRInput && MetadataWriter.hasGainMap(at: url))
        case .heif10, .original:
            return try encodeHEIF10(sdr, hasHDRInput: hasHDRInput, plain: plain, withHDR: withHDR,
                                    colorSpace: colorSpace, sourceBits: sourceBits, context: context, to: url)
        case .png16, .tiff16:
            try write16Bit(sdr, png: format == .png16, context: context, colorSpace: colorSpace, to: url)
            return EncodeOutcome(bits: 16, containsHDR: false)
        }
    }

    /// HEIF 10-bit. The header documents `.hdrImage` for JPEG and HEIF but not for the 10-bit
    /// writer, so the gain map is verified by reading the file back. If it is missing and the
    /// source is 8-bit, an 8-bit base + gain map (the iPhone's own HEIC layout) keeps the HDR
    /// without going below the source's bit depth; otherwise the 10-bit SDR file is kept.
    private static func encodeHEIF10(_ sdr: CIImage, hasHDRInput: Bool,
                                     plain: [CIImageRepresentationOption: Any],
                                     withHDR: [CIImageRepresentationOption: Any],
                                     colorSpace: CGColorSpace, sourceBits: Int, context: CIContext,
                                     to url: URL) throws -> EncodeOutcome {
        guard hasHDRInput else {
            try context.writeHEIF10Representation(of: sdr, to: url, colorSpace: colorSpace, options: plain)
            return EncodeOutcome(bits: 10, containsHDR: false)
        }
        let eightBitAllowed = sourceBits <= 8
        let capabilities = EncoderCapabilities.shared

        if capabilities.heif10SupportsGainMap != false {
            var wrote = false
            do {
                try context.writeHEIF10Representation(of: sdr, to: url, colorSpace: colorSpace, options: withHDR)
                wrote = true
            } catch {
                try? FileManager.default.removeItem(at: url)
            }
            if wrote {
                if MetadataWriter.hasGainMap(at: url) {
                    capabilities.recordHEIF10GainMap(true)
                    return EncodeOutcome(bits: 10, containsHDR: true)
                }
                capabilities.recordHEIF10GainMap(false)
                // The 10-bit file is a valid SDR export; replace it only if 8-bit + gain map works.
                guard eightBitAllowed else { return EncodeOutcome(bits: 10, containsHDR: false) }
                let candidate = MetadataWriter.siblingTemporaryURL(for: url)
                if (try? writeHEIF8(sdr, context: context, colorSpace: colorSpace, options: withHDR, to: candidate)) != nil,
                   MetadataWriter.hasGainMap(at: candidate) {
                    try MetadataWriter.replaceFile(at: url, with: candidate)
                    return EncodeOutcome(bits: 8, containsHDR: true)
                }
                try? FileManager.default.removeItem(at: candidate)
                return EncodeOutcome(bits: 10, containsHDR: false)
            }
        }

        // Known (or just found) that 10-bit + gain map isn't available.
        if eightBitAllowed {
            if (try? writeHEIF8(sdr, context: context, colorSpace: colorSpace, options: withHDR, to: url)) != nil,
               MetadataWriter.hasGainMap(at: url) {
                return EncodeOutcome(bits: 8, containsHDR: true)
            }
            try? FileManager.default.removeItem(at: url)
        }
        try context.writeHEIF10Representation(of: sdr, to: url, colorSpace: colorSpace, options: plain)
        return EncodeOutcome(bits: 10, containsHDR: false)
    }

    /// 8-bit HEIF. `.RGBX8` is opaque, so no (all-white) alpha auxiliary image is written;
    /// `.RGBA8` is the fallback if the writer rejects it.
    private static func writeHEIF8(_ image: CIImage, context: CIContext, colorSpace: CGColorSpace,
                                   options: [CIImageRepresentationOption: Any], to url: URL) throws {
        do {
            try context.writeHEIFRepresentation(of: image, to: url, format: .RGBX8, colorSpace: colorSpace, options: options)
        } catch {
            try? FileManager.default.removeItem(at: url)
            try context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: colorSpace, options: options)
        }
    }

    /// 16-bit PNG/TIFF. `.RGBX16` (opaque) first, `.RGBA16` (documented for PNG/TIFF) as fallback.
    private static func write16Bit(_ image: CIImage, png: Bool, context: CIContext, colorSpace: CGColorSpace,
                                   to url: URL) throws {
        func write(_ pixelFormat: CIFormat) throws {
            if png {
                try context.writePNGRepresentation(of: image, to: url, format: pixelFormat, colorSpace: colorSpace, options: [:])
            } else {
                try context.writeTIFFRepresentation(of: image, to: url, format: pixelFormat, colorSpace: colorSpace, options: [:])
            }
        }
        do {
            try write(.RGBX16)
        } catch {
            try? FileManager.default.removeItem(at: url)
            try write(.RGBA16)
        }
    }

    /// Fallback B (§2.2): render the same in-memory image to a CGImage and write it with
    /// ImageIO and explicit properties, copying the gain map of the Core Image file.
    /// Returns false (file untouched) if any step fails.
    private static func reencodeWithImageIO(_ image: CIImage, format: ExportFormat, colorSpace: CGColorSpace,
                                            properties: [String: Any], quality: Double, gainMapSource: URL?,
                                            context: CIContext, type: UTType, to url: URL) -> Bool {
        let candidates: [CIFormat]
        switch format {
        case .jpeg: candidates = [.RGBA8]
        case .heif8: candidates = [.RGBX8, .RGBA8]
        case .heif10, .original: candidates = [.RGB10]          // Apple's HDR sample writes 10-bit HEIC this way
        case .png16, .tiff16: candidates = [.RGBX16, .RGBA16]
        }
        let rect = image.extent
        var cgImage: CGImage?
        for pixelFormat in candidates where cgImage == nil {
            cgImage = context.createCGImage(image, from: rect, format: pixelFormat, colorSpace: colorSpace, deferred: true)
        }
        guard let rendered = cgImage else { return false }

        let temp = MetadataWriter.siblingTemporaryURL(for: url)
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        var fileProperties = properties
        if isLossy(format) {
            fileProperties[kCGImageDestinationLossyCompressionQuality as String] = quality
        }
        CGImageDestinationAddImage(destination, rendered, fileProperties as CFDictionary)
        if let gainMapSource, let gainMap = MetadataWriter.gainMapAuxiliaryData(at: gainMapSource) {
            CGImageDestinationAddAuxiliaryDataInfo(destination, gainMap.type, gainMap.info)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        do {
            try MetadataWriter.replaceFile(at: url, with: temp)
            return true
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
    }

    // MARK: Image helpers

    /// Integral extent at the origin. Fractional edges are filled by clamping (never resampled).
    private static func normalized(_ image: CIImage) -> CIImage? {
        let extent = image.extent
        guard !extent.isNull, !extent.isInfinite, !extent.isEmpty,
              extent.width.isFinite, extent.height.isFinite else { return nil }
        var result = image
        let dx = extent.minX.rounded()
        let dy = extent.minY.rounded()
        if dx != 0 || dy != 0 {
            result = result.transformed(by: CGAffineTransform(translationX: -dx, y: -dy))   // whole pixels: exact
        }
        let canvas = CGRect(x: 0, y: 0, width: max(1, extent.width.rounded()), height: max(1, extent.height.rounded()))
        if result.extent != canvas {
            result = result.clampedToExtent().cropped(to: canvas)
        }
        return result
    }

    /// Lanczos downsize to exactly `target` (never upscales). The input is clamped so edges
    /// don't fade to transparent, then cropped back.
    private static func resized(_ image: CIImage, to target: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              target.width < extent.width || target.height < extent.height else { return image }
        let sx = target.width / extent.width
        let sy = target.height / extent.height
        let canvas = CGRect(origin: .zero, size: target)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image.clampedToExtent()
        lanczos.scale = Float(sy)                 // vertical scale
        lanczos.aspectRatio = Float(sx / sy)      // horizontal = scale × aspectRatio
        if let output = lanczos.outputImage {
            return output.cropped(to: canvas)
        }
        return image.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy), highQualityDownsample: true)
            .cropped(to: canvas)
    }

    /// Fully opaque inside `canvas` (premultiplied and straight alpha become identical).
    private static func opaque(_ image: CIImage, in canvas: CGRect) -> CIImage {
        image.cropped(to: canvas).settingAlphaOne(in: canvas).cropped(to: canvas)
    }

    /// Output size for `size`: whole pixels, long edge reduced (never enlarged).
    static func targetSize(for full: CGSize, size: ExportSize) -> CGSize {
        let width = max(1, full.width.rounded())
        let height = max(1, full.height.rounded())
        let whole = CGSize(width: width, height: height)
        guard case .longEdge(let edge) = size, edge > 0 else { return whole }
        let longEdge = max(width, height)
        guard CGFloat(edge) < longEdge else { return whole }
        let scale = CGFloat(edge) / longEdge
        return CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
    }

    // MARK: Format rules

    /// `.original` → same family at the best quality, never below the source's bit depth:
    /// JPEG → JPEG, PNG → PNG 16, TIFF → TIFF 16, HEIF → HEIF 10, RAW/DNG → TIFF 16, else HEIF 10.
    static func resolvedFormat(_ choice: ExportFormat, info: SourceInfo) -> ExportFormat {
        guard choice == .original else { return choice }
        let candidate: ExportFormat
        if info.isRAW {
            candidate = .tiff16
        } else {
            switch UTType(info.typeIdentifier).flatMap({ container(of: $0) }) {
            case .jpeg?: candidate = .jpeg
            case .png?: candidate = .png16
            case .tiff?: candidate = .tiff16
            case .heif?, nil: candidate = .heif10
            }
        }
        return nominalBits(candidate) < info.bitsPerComponent ? .tiff16 : candidate
    }

    /// Adaptive HDR (SDR + gain map) needs iOS 18, an HDR source, HDR kept in both the recipe
    /// and the options, and a gain-map container (JPEG or HEIF).
    private static func shouldWriteHDR(info: SourceInfo, recipe: EditRecipe, options: ExportOptions,
                                       format: ExportFormat) -> Bool {
        guard info.isHDR, options.keepHDR, recipe.keepsHDR else { return false }
        switch format {
        case .jpeg, .heif8, .heif10:
            break
        case .original, .png16, .tiff16:
            return false
        }
        if #available(iOS 18.0, *) { return true }
        return false
    }

    private static func nominalBits(_ format: ExportFormat) -> Int {
        switch format {
        case .jpeg, .heif8: return 8
        case .heif10, .original: return 10
        case .png16, .tiff16: return 16
        }
    }

    private static func isLossy(_ format: ExportFormat) -> Bool {
        switch format {
        case .jpeg, .heif8, .heif10, .original: return true
        case .png16, .tiff16: return false
        }
    }

    private static func contentType(for format: ExportFormat) -> UTType {
        switch format {
        case .jpeg: return .jpeg
        case .heif8, .heif10, .original: return .heic
        case .png16: return .png
        case .tiff16: return .tiff
        }
    }

    private static func fileExtension(for format: ExportFormat) -> String {
        switch format {
        case .jpeg: return "jpg"
        case .heif8, .heif10, .original: return "heic"
        case .png16: return "png"
        case .tiff16: return "tif"
        }
    }

    /// Rough size estimate for the export sheet (bytes per pixel measured on typical photos).
    private static func estimatedBytes(format: ExportFormat, pixels: Double, quality: Double, hdr: Bool) -> Int64 {
        let q = min(max(quality.isFinite ? quality : 1, 0.5), 1)
        let t = (q - 0.5) / 0.5
        let lossyScale = 0.25 + 0.75 * t * t
        var perPixel: Double
        switch format {
        case .jpeg: perPixel = 0.6 * lossyScale
        case .heif8: perPixel = 0.3 * lossyScale
        case .heif10, .original: perPixel = 0.35 * lossyScale
        case .png16: perPixel = 4
        case .tiff16: perPixel = 6
        }
        if hdr { perPixel *= 1.15 }   // gain map
        return Int64((max(pixels, 0) * perPixel).rounded())
    }

    // MARK: Containers and passthrough

    private enum Container { case jpeg, png, tiff, heif }

    private static func container(of type: UTType) -> Container? {
        if type.conforms(to: .rawImage) || type.identifier == "com.adobe.raw-image" { return nil }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return .heif }
        if type.conforms(to: .tiff) { return .tiff }
        return nil
    }

    private static func container(of format: ExportFormat) -> Container? {
        switch format {
        case .jpeg: return .jpeg
        case .png16: return .png
        case .tiff16: return .tiff
        case .heif8, .heif10: return .heif
        case .original: return nil
        }
    }

    private enum PassthroughRoute { case render, copy, stripLocation }

    /// Byte copy when nothing would change; lossless metadata strip when only the location must go.
    private static func passthroughRoute(document: PhotoDocument, recipe: EditRecipe, options: ExportOptions,
                                         format: ExportFormat, source: ExportSourceMetadata) -> PassthroughRoute {
        let info = document.info
        guard recipe.isIdentity,
              keepsSourceColorSpace(options.colorSpace, info: info, source: source),
              options.keepMetadata,
              targetSize(for: document.uprightSize, size: options.size) == targetSize(for: document.uprightSize, size: .original),
              !info.isRAW,
              let sourceType = sourceContentType(info: info, source: source),
              let sourceContainer = container(of: sourceType)
        else { return .render }
        // "Original" keeps the original's own container, even when its depth made `.original`
        // resolve to TIFF 16 (e.g. a 12-bit HEIF): a byte copy loses nothing. An explicit format
        // must name the same container.
        if options.format != .original {
            guard sourceContainer == container(of: format) else { return .render }
            // An explicit format below the source's depth (e.g. HEIF 8-bit for a 10-bit HEIF)
            // asks for that depth.
            if nominalBits(format) < info.bitsPerComponent { return .render }
        }
        // An HDR original exported as SDR must be rendered.
        if info.isHDR && !(options.keepHDR && recipe.keepsHDR) { return .render }
        // A lowered quality on an explicit lossy format asks for a smaller file: re-encode.
        if options.format != .original && isLossy(format) && options.quality < 0.999 { return .render }
        if options.keepLocation || !source.hasLocation { return .copy }
        return .stripLocation
    }

    /// The chosen output space is the original's own: "Same as Original", or an explicit choice
    /// naming the space the original is already tagged with (e.g. a remembered "Display P3" for an
    /// iPhone photo), so the original's bytes already are that file.
    private static func keepsSourceColorSpace(_ choice: ExportColorSpace, info: SourceInfo,
                                              source: ExportSourceMetadata) -> Bool {
        guard choice != .matchSource else { return true }
        guard let space = source.colorSpace, space.model == .rgb, !space.isHDR(),
              let name = space.name as String? else { return false }
        switch choice {
        case .matchSource: return true
        case .displayP3: return name == (CGColorSpace.displayP3 as String)
        case .sRGB: return name == (CGColorSpace.sRGB as String)
        case .adobeRGB: return name == (CGColorSpace.adobeRGB1998 as String)
        case .proPhoto: return name == (CGColorSpace.rommrgb as String) && info.bitsPerComponent >= 16
        }
    }

    /// The format that names the original's own container, for describing a byte copy
    /// (`format` itself unless `.original` resolved to another family because of bit depth).
    private static func passthroughFormat(_ format: ExportFormat, info: SourceInfo,
                                          source: ExportSourceMetadata) -> ExportFormat {
        guard let sourceType = sourceContentType(info: info, source: source),
              let sourceContainer = container(of: sourceType),
              sourceContainer != container(of: format) else { return format }
        switch sourceContainer {
        case .jpeg: return .jpeg
        case .png: return .png16
        case .tiff: return .tiff16
        case .heif: return .heif10
        }
    }

    private static func passthroughPlan(document: PhotoDocument, format: ExportFormat,
                                        source: ExportSourceMetadata) -> ExportPlan {
        let info = document.info
        let type = sourceContentType(info: info, source: source) ?? contentType(for: format)
        return ExportPlan(format: format,
                          pixelSize: document.uprightSize,
                          bitsPerComponent: info.bitsPerComponent,
                          colorSpaceName: info.profileName ?? "sRGB",
                          isPassthrough: true,
                          writesHDR: info.isHDR,
                          estimatedBytes: source.fileSize,
                          fileExtension: passthroughExtension(info: info, type: type, format: format),
                          contentType: type)
    }

    private static func passthroughResult(url: URL, type: UTType, document: PhotoDocument) -> ExportResult {
        let info = document.info
        return ExportResult(url: url,
                            contentType: type,
                            pixelSize: document.uprightSize,
                            bitsPerComponent: info.bitsPerComponent,
                            colorSpaceName: info.profileName ?? "sRGB",
                            fileSize: fileSize(of: url),
                            wasPassthrough: true,
                            containsHDR: info.isHDR)
    }

    /// The original's real type (sniffed by ImageIO, else the type recorded at import).
    private static func sourceContentType(info: SourceInfo, source: ExportSourceMetadata) -> UTType? {
        source.typeIdentifier.flatMap { UTType($0) } ?? UTType(info.typeIdentifier)
    }

    /// Keeps the original's extension when it matches its content, else the type's preferred one.
    private static func passthroughExtension(info: SourceInfo, type: UTType, format: ExportFormat) -> String {
        let stored = info.fileExtension.lowercased()
        if !stored.isEmpty, let storedType = UTType(filenameExtension: stored),
           storedType == type || storedType.conforms(to: type) || type.conforms(to: storedType) {
            return stored
        }
        return type.preferredFilenameExtension ?? fileExtension(for: format)
    }

    // MARK: Colour space (§3)

    private struct ColorTarget {
        let space: CGColorSpace
        let name: String
        let isSRGB: Bool
        /// Adobe RGB / ProPhoto (/ BT.2020): reaches beyond the Display P3 working space, so the
        /// SDR fit must not pull colours into P3.
        var isWiderThanP3 = false
    }

    private static func colorTarget(_ choice: ExportColorSpace, bits: Int, info: SourceInfo,
                                    source: ExportSourceMetadata) -> ColorTarget {
        let displayP3 = ColorTarget(space: CGColorSpace(name: CGColorSpace.displayP3)!, name: "Display P3", isSRGB: false)
        let sRGB = ColorTarget(space: CGColorSpace(name: CGColorSpace.sRGB)!, name: "sRGB", isSRGB: true)
        switch choice {
        case .displayP3:
            return displayP3
        case .sRGB:
            return sRGB
        case .adobeRGB:
            return ColorTarget(space: CGColorSpace(name: CGColorSpace.adobeRGB1998)!, name: "Adobe RGB (1998)",
                               isSRGB: false, isWiderThanP3: true)
        case .proPhoto:
            // ProPhoto in 8 or 10 bits posterizes; it is only offered for 16-bit files.
            guard bits >= 16 else { return displayP3 }
            return ColorTarget(space: CGColorSpace(name: CGColorSpace.rommrgb)!, name: "ProPhoto RGB",
                               isSRGB: false, isWiderThanP3: true)
        case .matchSource:
            guard !info.isRAW, let space = source.colorSpace, space.model == .rgb, !space.isHDR() else {
                return displayP3
            }
            let spaceName = (space.name as String?) ?? ""
            if spaceName == "kCGColorSpaceDeviceRGB" { return sRGB }                 // untagged source
            if spaceName.contains("Linear") || spaceName.contains("Extended") { return displayP3 }
            if spaceName == (CGColorSpace.sRGB as String) { return sRGB }
            if spaceName == (CGColorSpace.displayP3 as String) { return displayP3 }
            let profile = info.profileName ?? String(localized: "Embedded profile")
            let isProPhoto = spaceName == (CGColorSpace.rommrgb as String)
                || profile.localizedCaseInsensitiveContains("ProPhoto") || profile.localizedCaseInsensitiveContains("ROMM")
            if isProPhoto && bits < 16 { return displayP3 }
            let isAdobeRGB = spaceName == (CGColorSpace.adobeRGB1998 as String)
                || profile.localizedCaseInsensitiveContains("Adobe RGB") || profile.localizedCaseInsensitiveContains("AdobeRGB")
            let isBT2020 = spaceName == (CGColorSpace.itur_2020 as String)
                || ["BT.2020", "BT2020", "Rec. 2020", "Rec.2020", "Rec2020"].contains { profile.localizedCaseInsensitiveContains($0) }
            let isSRGB = profile.lowercased().hasPrefix("srgb")
            return ColorTarget(space: space, name: profile, isSRGB: isSRGB,
                               isWiderThanP3: isProPhoto || isAdobeRGB || isBT2020)
        }
    }

    // MARK: Files

    private static var exportsRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    private static func makeExportDirectory() throws -> URL {
        let directory = exportsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ExportError.fileSystem(reason: error.localizedDescription)
        }
        return directory
    }

    /// Removes export folders left behind by earlier sessions (tmp is purged by iOS eventually,
    /// but a 48 MP TIFF is ~300 MB, so don't wait).
    private static func removeStaleExports(olderThan age: TimeInterval = 6 * 3600) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: exportsRoot,
                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (modified ?? .distantPast) < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    /// `requested` (sanitized) or "<fallback>-noor".
    static func exportFileBaseName(requested: String?, fallback: String) -> String {
        if let requested, let clean = sanitizedFileName(requested) { return clean }
        let base = sanitizedFileName(fallback) ?? "Noor"
        return base.lowercased().hasSuffix("-noor") ? base : "\(base)-noor"
    }

    /// Strips path separators and characters other file systems reject, a typed image
    /// extension and leading dots. Nil when nothing usable remains.
    private static func sanitizedFileName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedExtension = (name as NSString).pathExtension
        if !typedExtension.isEmpty, let type = UTType(filenameExtension: typedExtension), type.conforms(to: .image) {
            name = (name as NSString).deletingPathExtension
        }
        let forbidden = CharacterSet(charactersIn: "/\\:?*|\"<>").union(.controlCharacters).union(.newlines)
        name = String(name.unicodeScalars.map { forbidden.contains($0) ? Character("-") : Character($0) })
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > 120 { name = String(name.prefix(120)) }
        return name.isEmpty ? nil : name
    }

    private static func fileSize(of url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: Errors and cancellation

    private static func checkCancelled() throws {
        if Task.isCancelled { throw ExportError.cancelled }
    }

    private static func mapped(_ error: Error) -> Error {
        if error is ExportError { return error }
        if error is CancellationError { return ExportError.cancelled }
        let ns = error as NSError
        if (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError)
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC)) {
            return ExportError.notEnoughSpace
        }
        return ExportError.encodeFailed(reason: error.localizedDescription)
    }
}

// MARK: - Encoder capabilities (learned per launch)

/// What this OS's encoders turned out to support, learned on the first export that needed it,
/// so later exports don't repeat a full encode that can't help:
///   * whether Core Image's HEIF 10-bit writer honours `.hdrImage` (only JPEG and HEIF are
///     documented), and
///   * formats for which fallback B (ImageIO re-encode) still produced no EXIF.
/// Thread-safe (lock-protected).
private final class EncoderCapabilities: @unchecked Sendable {
    static let shared = EncoderCapabilities()

    private let lock = NSLock()
    private var heif10GainMap: Bool?
    private var futileExifFallback: Set<ExportFormat> = []

    /// nil until the first HDR HEIF 10-bit export of this launch.
    var heif10SupportsGainMap: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return heif10GainMap
    }

    func recordHEIF10GainMap(_ supported: Bool) {
        lock.lock()
        defer { lock.unlock() }
        heif10GainMap = supported
    }

    func isExifFallbackFutile(for format: ExportFormat) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return futileExifFallback.contains(format)
    }

    func recordFutileExifFallback(for format: ExportFormat) {
        lock.lock()
        defer { lock.unlock() }
        futileExifFallback.insert(format)
    }
}
