import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// MARK: - Source description

/// What Noor knows about an original file, read from its metadata without decoding pixels.
struct SourceInfo: Hashable, Sendable {
    var typeIdentifier: String       // UTType id of the ORIGINAL ("public.heic", "com.adobe.raw-image", …)
    var fileExtension: String        // lowercased, from the stored file name
    var isRAW: Bool
    var uprightSize: CGSize          // full-res pixels, orientation applied (RAW: decoder output size)
    var bitsPerComponent: Int        // 8, 10, 12, 14, 16, 32
    var isFloat: Bool
    var hasAlpha: Bool
    var profileName: String?         // ICC description ("Display P3", "sRGB IEC61966-2.1", …)
    var hasGainMap: Bool             // Apple or ISO (iOS 18) gain map
    var isHDR: Bool                  // gain map, or HDR transfer function (PQ/HLG)
    var asShotKelvin: Double         // RAW: CIRAWFilter default neutralTemperature; others 5500
    var asShotTint: Double           // RAW: default neutralTint; others 0
    var cameraName: String?          // "Apple iPhone 16 Pro" from EXIF/TIFF Make+Model, if present
    var captureDate: Date?           // EXIF DateTimeOriginal, if present
}

/// One base image ready for the recipe pipeline.
struct RenderBase {
    let image: CIImage               // upright, extent origin (0,0), working space, may exceed 1.0 when isHDR
    let renderScale: CGFloat         // base pixels / full-res pixels (1 = full resolution)
    let rawStageApplied: Bool        // true: CIRAWFilter already applied WB/exposure/NR from the recipe
    let isHDR: Bool
}

/// Why a file could not be opened.
enum PhotoDocumentError: Error {
    case unreadable      // the bytes could not be read, or no image size could be determined
    case unsupported     // no system decoder (e.g. a RAW camera this iOS version cannot develop)
}

// MARK: - Document

/// The original file plus its decoders and caches. The original bytes are memory-mapped and never
/// modified; every base image is decoded from them.
///
/// Tiers:
///   * preview   - interactive proxy (~screen size). RAW: `CIRAWFilter` with `scaleFactor` and the RAW stage
///                 (WB, exposure, NR) taken from the recipe, cached per settings so post-RAW sliders never
///                 re-demosaic. Bitmaps: one subsampled ImageIO decode, oriented, downscaled and baked to RGBAh.
///   * detail    - full-resolution lazy image for the 100 % view (cached, purgeable).
///   * export    - full resolution from fresh decoder objects; touches no cache.
///   * thumbnail - small baked SDR base with camera defaults, cached in a few size buckets.
///
/// Thread safety: every method may be called from any thread. Mutable state is confined behind one
/// `NSLock` per tier. `CIRAWFilter` instances (mutable, NOT thread-safe) are only touched while their
/// tier's lock is held, and export / thumbnails create a private filter per call. The `CIImage`s handed
/// out are immutable snapshots, safe to render on any thread. Lock order: `airlightLock` before
/// `thumbnailLock` (the airlight analysis reads a thumbnail base); no other lock is taken while one is held.
///
/// Memory: no full-resolution bitmap is ever kept. Full-resolution bases are lazy `CIImage`s that Core
/// Image decodes per region; the only bitmaps held are the baked proxies and thumbnails. A full-size
/// decode only happens transiently while baking a proxy of a small image or a format ImageIO cannot subsample.
final class PhotoDocument: @unchecked Sendable {
    let url: URL
    let info: SourceInfo

    var uprightSize: CGSize { info.uprightSize }

    // MARK: Immutable decode inputs (read-only after init, safe from any thread)

    /// The original bytes, memory-mapped (clean pages: a 75 MB DNG does not count as dirty memory).
    private let data: Data
    /// EXIF orientation of a bitmap source; `.up` for RAW (CIRAWFilter output is already upright).
    private let orientation: CGImagePropertyOrientation
    /// PQ / HLG transfer function: decodes as HDR by default, so an SDR decode needs an explicit tone map.
    private let hasHDRTransfer: Bool
    /// Camera defaults of a RAW file; nil for bitmaps.
    private let rawDefaults: RAWDefaults?
    /// Apple gain-map headroom from the MakerApple tags (iOS 17 fallback for `headroom`).
    private let appleGainMapHeadroom: Float?
    private let fullLongEdge: CGFloat

    // MARK: Preview tier (guarded by previewLock)

    private let previewLock = NSLock()
    /// Dedicated RAW filter for the proxy, reconfigured per request.
    private var previewRAWFilter: CIRAWFilter?
    /// Most recently used last. Holds lazy images; the demosaiced pixels live in Core Image's cache.
    private var rawPreviewCache: [(key: RAWPreviewKey, base: RenderBase)] = []
    /// Baked bitmap proxies, one per HDR flag.
    private var bitmapPreviewCache: [Bool: BakedBase] = [:]

    // MARK: Detail tier (guarded by detailLock)

    private let detailLock = NSLock()
    private var detailRAWFilter: CIRAWFilter?
    private var detailRAWCache: (settings: RAWStageSettings, base: RenderBase)?
    private var detailBitmapCache: (hdr: Bool, base: RenderBase)?

    // MARK: Thumbnail tier (guarded by thumbnailLock)

    private let thumbnailLock = NSLock()
    /// Baked SDR bases keyed by their bucket long edge (see `thumbnailBuckets`).
    private var thumbnailCache: [CGFloat: RenderBase] = [:]

    // MARK: Analysis (one lock each)

    private let airlightLock = NSLock()
    private var cachedAirlight: SIMD3<Float>?
    private let headroomLock = NSLock()
    private var cachedHeadroom: Float?

    // MARK: Constants

    /// RAW proxies kept per document: the current settings plus a few for undo and show-original toggles.
    private static let rawPreviewCacheLimit = 4
    /// A cached RAW proxy with the same settings is reused for requests down to 1 / this of its long edge.
    private static let rawPreviewReuseLimit: CGFloat = 2
    /// Thumbnail bases are baked at the smallest bucket >= the request, so a preset strip and a library
    /// cell share one decode without rendering oversized bases.
    private static let thumbnailBuckets: [CGFloat] = [128, 256, 512, 1024]
    private static let thumbnailCacheLimit = 6
    /// Smallest long edge any base is decoded at.
    private static let minimumLongEdge: CGFloat = 16
    /// Long edge of the analysis copy used for the airlight estimate.
    private static let airlightAnalysisEdge: CGFloat = 128
    /// Neutral airlight used when the estimate fails (slightly below white, linear).
    private static let fallbackAirlight = SIMD3<Float>(repeating: 0.95)
    /// iOS 17 headroom assumptions where the OS cannot report the real value (`contentHeadroom` is iOS 18):
    /// a gain map without Apple metadata is assumed to add one stop; PQ / HLG content is assumed graded
    /// for ~1000 nits over a 203-nit reference white (ITU-R BT.2408).
    private static let assumedGainMapHeadroom: Float = 2.0
    private static let assumedTransferHeadroom: Float = 1000.0 / 203.0
    /// ICC descriptions for named color spaces whose files carry no profile name (e.g. HEIC with nclx).
    private static let knownProfileNames: [String: String] = [
        CGColorSpace.displayP3 as String: "Display P3",
        CGColorSpace.sRGB as String: "sRGB IEC61966-2.1",
        CGColorSpace.adobeRGB1998 as String: "Adobe RGB (1998)",
        CGColorSpace.itur_2100_PQ as String: "Rec. ITU-R BT.2100 PQ",
        CGColorSpace.itur_2100_HLG as String: "Rec. ITU-R BT.2100 HLG",
        CGColorSpace.genericGrayGamma2_2 as String: "Generic Gray Gamma 2.2 Profile",
    ]

    // MARK: Private types

    /// Camera defaults read from a fresh `CIRAWFilter` ("the default value varies by image").
    private struct RAWDefaults {
        let exposure: Float
        let neutralTemperature: Float
        let neutralTint: Float
        let luminanceNR: Float
        let colorNR: Float
    }

    private struct RAWPreviewKey: Hashable {
        let settings: RAWStageSettings
        let longEdge: CGFloat
    }

    private struct BakedBase {
        let base: RenderBase
        let longEdge: CGFloat
    }

    // MARK: - Init

    /// Inspects the file: metadata, decoder availability and RAW defaults. No pixels are decoded.
    init(url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw PhotoDocumentError.unreadable
        }
        guard !data.isEmpty else { throw PhotoDocumentError.unreadable }

        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        let source = CGImageSourceCreateWithData(data as CFData, noCache)
        let imageCount = source.map { CGImageSourceGetCount($0) } ?? 0
        let index = source.map { CGImageSourceGetPrimaryImageIndex($0) } ?? 0
        var properties: [String: Any] = [:]
        if let source, imageCount > 0 {
            properties = (CGImageSourceCopyPropertiesAtIndex(source, index, noCache) as? [String: Any]) ?? [:]
        }

        let fileExtension = url.pathExtension.lowercased()
        var typeIdentifier = source.flatMap { CGImageSourceGetType($0) }.map { $0 as String } ?? ""
        if typeIdentifier.isEmpty, !fileExtension.isEmpty,
           let type = UTType(filenameExtension: fileExtension) {
            typeIdentifier = type.identifier
        }

        // RAW detection: declared RAW types, DNG data typed as TIFF, or data ImageIO cannot read at all.
        // CIRAWFilter has the final word.
        let declaredRAW = PhotoDocument.isRAWType(typeIdentifier)
        let hasDNGTags = properties[kCGImagePropertyDNGDictionary as String] != nil
        var rawFilter: CIRAWFilter?
        var rawOutput: CIImage?
        if declaredRAW || hasDNGTags || imageCount == 0 {
            rawFilter = CIRAWFilter(imageData: data, identifierHint: typeIdentifier.isEmpty ? nil : typeIdentifier)
            rawOutput = rawFilter?.outputImage
            if rawOutput == nil { rawFilter = nil }
        }
        let isRAW = rawFilter != nil
        if !isRAW {
            // A RAW file the system cannot develop is refused rather than silently edited from its
            // embedded 8-bit preview (that would lose quality).
            guard imageCount > 0, !declaredRAW else { throw PhotoDocumentError.unsupported }
        }
        if properties.isEmpty, let rawFilter {
            properties = (rawFilter.properties as? [String: Any]) ?? [:]
        }

        // Orientation and upright size.
        let orientationValue = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        var uprightSize: CGSize
        if let rawOutput {
            uprightSize = PhotoDocument.integralAtOrigin(rawOutput).extent.size
        } else {
            let storedWidth = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
            let storedHeight = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
            var stored = CGSize(width: storedWidth, height: storedHeight)
            if stored.width <= 0 || stored.height <= 0 {
                // Lazy: CIImage(data:) parses the header, pixels are decoded only when rendered.
                stored = CIImage(data: data)?.extent.size ?? .zero
            }
            uprightSize = PhotoDocument.swapsAxes(orientation)
                ? CGSize(width: stored.height, height: stored.width)
                : stored
        }
        uprightSize = CGSize(width: uprightSize.width.rounded(), height: uprightSize.height.rounded())
        guard uprightSize.width >= 1, uprightSize.height >= 1 else { throw PhotoDocumentError.unreadable }

        // Pixel format.
        let depth = (properties[kCGImagePropertyDepth as String] as? NSNumber)?.intValue
        let bitsPerComponent: Int
        if isRAW {
            // ImageIO reports the developed depth for RAW; sensor data carries 12-14 bits.
            bitsPerComponent = max(depth ?? 14, 12)
        } else {
            bitsPerComponent = max(depth ?? 8, 1)
        }
        let isFloat = (properties[kCGImagePropertyIsFloat as String] as? NSNumber)?.boolValue ?? false
        let hasAlpha = isRAW ? false : ((properties[kCGImagePropertyHasAlpha as String] as? NSNumber)?.boolValue ?? false)

        // Color. A header-only CGImage (no kCGImageSourceShouldCacheImmediately) decodes no pixels, but
        // its color space names the profile and tells whether the transfer function is PQ / HLG.
        var colorSpace: CGColorSpace?
        if !isRAW, let source, imageCount > 0 {
            colorSpace = CGImageSourceCreateImageAtIndex(source, index, noCache)?.colorSpace
        }
        var profileName = properties[kCGImagePropertyProfileName as String] as? String
        if profileName?.isEmpty ?? true {
            profileName = PhotoDocument.profileName(for: colorSpace)
        }
        let hasHDRTransfer = colorSpace.map { CGColorSpaceUsesITUR_2100TF($0) } ?? false

        // Gain map (copies only the small auxiliary image, typically 1/4 resolution).
        var hasGainMap = false
        var hasAppleGainMap = false
        if let source, imageCount > 0 {
            hasAppleGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source, index, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
            hasGainMap = hasAppleGainMap
            if !hasGainMap, #available(iOS 18.0, *) {
                hasGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                    source, index, kCGImageAuxiliaryDataTypeISOGainMap) != nil
            }
        }
        let isHDR = hasGainMap || hasHDRTransfer

        // RAW camera defaults: always read from the file, never assumed.
        var defaults: RAWDefaults?
        if let rawFilter {
            defaults = RAWDefaults(exposure: rawFilter.exposure,
                                   neutralTemperature: rawFilter.neutralTemperature,
                                   neutralTint: rawFilter.neutralTint,
                                   luminanceNR: rawFilter.luminanceNoiseReductionAmount,
                                   colorNR: rawFilter.colorNoiseReductionAmount)
        }
        var asShotKelvin = 5500.0
        var asShotTint = 0.0
        if let defaults, defaults.neutralTemperature.isFinite, defaults.neutralTemperature > 0 {
            asShotKelvin = Double(defaults.neutralTemperature)
            asShotTint = defaults.neutralTint.isFinite ? Double(defaults.neutralTint) : 0
        }

        self.url = url
        self.data = data
        self.orientation = isRAW ? .up : orientation
        self.hasHDRTransfer = hasHDRTransfer
        self.rawDefaults = defaults
        self.appleGainMapHeadroom = hasAppleGainMap ? PhotoDocument.appleHeadroom(from: properties) : nil
        self.fullLongEdge = max(uprightSize.width, uprightSize.height)
        // The inspection filter is fresh and still at camera defaults: it becomes the proxy filter.
        self.previewRAWFilter = rawFilter
        self.info = SourceInfo(
            typeIdentifier: typeIdentifier,
            fileExtension: fileExtension,
            isRAW: isRAW,
            uprightSize: uprightSize,
            bitsPerComponent: bitsPerComponent,
            isFloat: isFloat,
            hasAlpha: hasAlpha,
            profileName: profileName,
            hasGainMap: hasGainMap,
            isHDR: isHDR,
            asShotKelvin: asShotKelvin,
            asShotTint: asShotTint,
            cameraName: PhotoDocument.cameraName(from: properties),
            captureDate: PhotoDocument.captureDate(from: properties))
    }

    // MARK: - Preview tier

    /// Interactive proxy (~longEdge px). RAW: CIRAWFilter(scaleFactor) with RAWStageSettings from `recipe`
    /// (cached by those settings; post-RAW sliders don't re-decode). Non-RAW: subsampled decode baked once
    /// to RGBAh (cached; a cached proxy at least as large is reused). HDR decode when
    /// recipe.keepsHDR && info.isHDR.
    func previewBase(for recipe: EditRecipe, longEdge: CGFloat) -> RenderBase? {
        guard let target = clampedLongEdge(longEdge) else { return nil }
        if let defaults = rawDefaults {
            return rawPreview(settings: rawSettings(for: recipe), longEdge: target, defaults: defaults)
        }
        return bitmapPreview(hdr: wantsHDR(recipe), longEdge: target)
    }

    private func rawPreview(settings: RAWStageSettings, longEdge: CGFloat, defaults: RAWDefaults) -> RenderBase? {
        previewLock.lock()
        defer { previewLock.unlock() }

        let key = RAWPreviewKey(settings: settings, longEdge: longEdge)
        if let i = rawPreviewCache.firstIndex(where: { $0.key == key }) {
            let entry = rawPreviewCache.remove(at: i)
            rawPreviewCache.append(entry)
            return entry.base
        }
        // The same RAW stage at a larger size (e.g. the crop tool's frame image while the canvas holds a
        // screen-sized proxy) is reused instead of demosaicing again. Only up to twice the size: a much
        // larger entry (a deep-crop thumbnail's base) would make every interactive frame far slower.
        if let entry = rawPreviewCache.last(where: {
            $0.key.settings == settings && $0.key.longEdge >= longEdge
                && $0.key.longEdge <= longEdge * PhotoDocument.rawPreviewReuseLimit
        }) {
            return entry.base
        }

        guard let filter = previewRAWFilter ?? makeRAWFilter() else { return nil }
        previewRAWFilter = filter
        PhotoDocument.configure(filter, settings: settings, defaults: defaults,
                                scale: Float(min(1, longEdge / fullLongEdge)))
        guard let output = filter.outputImage else { return nil }
        let image = PhotoDocument.integralAtOrigin(output)
        guard image.extent.width >= 1, image.extent.height >= 1 else { return nil }
        let base = RenderBase(image: image.insertingIntermediate(cache: true),
                              renderScale: image.extent.width / info.uprightSize.width,
                              rawStageApplied: true,
                              isHDR: settings.hdr)
        rawPreviewCache.append((key: key, base: base))
        if rawPreviewCache.count > PhotoDocument.rawPreviewCacheLimit {
            rawPreviewCache.removeFirst(rawPreviewCache.count - PhotoDocument.rawPreviewCacheLimit)
        }
        return base
    }

    private func bitmapPreview(hdr: Bool, longEdge: CGFloat) -> RenderBase? {
        previewLock.lock()
        defer { previewLock.unlock() }

        // Never upscale a smaller proxy; a larger one is fine (renderScale reports its real size).
        if let cached = bitmapPreviewCache[hdr], cached.longEdge >= longEdge {
            return cached.base
        }
        let context = RenderEngine.shared.previewContext
        // If an HDR decode fails, an SDR proxy (isHDR false) still lets the photo be edited.
        guard let base = bakeBitmap(longEdge: longEdge, hdr: hdr, context: context)
                ?? (hdr ? bakeBitmap(longEdge: longEdge, hdr: false, context: context) : nil) else {
            return nil
        }
        bitmapPreviewCache[hdr] = BakedBase(base: base, longEdge: longEdge)
        return base
    }

    // MARK: - Detail tier

    /// Full-resolution lazy base for the 100 % detail view (cached, purgeable).
    func fullBase(for recipe: EditRecipe) -> RenderBase? {
        detailLock.lock()
        defer { detailLock.unlock() }

        if let defaults = rawDefaults {
            let settings = rawSettings(for: recipe)
            if let cached = detailRAWCache, cached.settings == settings {
                return cached.base
            }
            guard let filter = detailRAWFilter ?? makeRAWFilter() else { return nil }
            detailRAWFilter = filter
            PhotoDocument.configure(filter, settings: settings, defaults: defaults, scale: 1)
            guard let output = filter.outputImage else { return nil }
            // Cacheable intermediate: repeated detail frames of the same region skip the demosaic while
            // post-RAW sliders move (Core Image caches only the regions it rendered).
            let base = RenderBase(image: PhotoDocument.integralAtOrigin(output).insertingIntermediate(cache: true),
                                  renderScale: 1, rawStageApplied: true, isHDR: settings.hdr)
            detailRAWCache = (settings: settings, base: base)
            return base
        }

        let hdr = wantsHDR(recipe)
        if let cached = detailBitmapCache, cached.hdr == hdr {
            return cached.base
        }
        // Same SDR fallback as the proxy when an HDR decode fails.
        let decoded: (image: CIImage, isHDR: Bool)?
        if let image = decodeFullBitmap(hdr: hdr) {
            decoded = (image: image, isHDR: hdr)
        } else if hdr, let image = decodeFullBitmap(hdr: false) {
            decoded = (image: image, isHDR: false)
        } else {
            decoded = nil
        }
        guard let decoded else { return nil }
        let base = RenderBase(image: decoded.image.insertingIntermediate(cache: true),
                              renderScale: 1, rawStageApplied: false, isHDR: decoded.isHDR)
        detailBitmapCache = (hdr: hdr, base: base)
        return base
    }

    /// Drops the detail decoder and its cached base (before an export, on memory warnings, on close).
    func purgeFullResolution() {
        detailLock.lock()
        detailRAWFilter = nil
        detailRAWCache = nil
        detailBitmapCache = nil
        detailLock.unlock()
    }

    // MARK: - Export

    /// Fresh full-resolution base for export (new decoder objects, no shared caches). `hdr` chooses HDR decode.
    func exportBase(for recipe: EditRecipe, hdr: Bool) -> RenderBase? {
        let decodeHDR = hdr && info.isHDR
        if let defaults = rawDefaults {
            // A private filter, never shared with the preview or detail tiers.
            guard let filter = makeRAWFilter() else { return nil }
            var settings = rawSettings(for: recipe)
            settings.hdr = decodeHDR
            PhotoDocument.configure(filter, settings: settings, defaults: defaults, scale: 1)
            guard let output = filter.outputImage else { return nil }
            return RenderBase(image: PhotoDocument.integralAtOrigin(output), renderScale: 1,
                              rawStageApplied: true, isHDR: decodeHDR)
        }
        if let image = decodeFullBitmap(hdr: decodeHDR) {
            return RenderBase(image: image, renderScale: 1, rawStageApplied: false, isHDR: decodeHDR)
        }
        // Same SDR fallback as the preview and detail tiers: an HDR decode failure must not make the
        // photo unexportable (isHDR false tells the exporter to write SDR only).
        guard decodeHDR, let image = decodeFullBitmap(hdr: false) else { return nil }
        return RenderBase(image: image, renderScale: 1, rawStageApplied: false, isHDR: false)
    }

    // MARK: - Thumbnails

    /// Small baked SDR base with camera defaults (rawStageApplied == false), cached. For thumbnails.
    /// It is baked at the smallest size bucket >= `longEdge`, so it may be somewhat larger than asked.
    func thumbnailBase(longEdge: CGFloat) -> RenderBase? {
        guard let wanted = clampedLongEdge(longEdge) else { return nil }
        let bucket = min(PhotoDocument.thumbnailBuckets.first(where: { $0 >= wanted }) ?? wanted, fullLongEdge)

        thumbnailLock.lock()
        defer { thumbnailLock.unlock() }

        if let cached = thumbnailCache[bucket] {
            return cached
        }
        let context = RenderEngine.shared.utilityContext
        let made: RenderBase?
        if let defaults = rawDefaults {
            made = bakeRAWThumbnail(longEdge: bucket, defaults: defaults, context: context)
        } else {
            made = bakeBitmap(longEdge: bucket, hdr: false, context: context)
        }
        guard let base = made else { return nil }
        if thumbnailCache.count >= PhotoDocument.thumbnailCacheLimit {
            thumbnailCache.removeAll()
        }
        thumbnailCache[bucket] = base
        return base
    }

    /// Camera-default RAW develop for thumbnails: a private filter decoded at twice the target size,
    /// then an alias-free downscale and a bake.
    private func bakeRAWThumbnail(longEdge: CGFloat, defaults: RAWDefaults, context: CIContext) -> RenderBase? {
        guard let filter = makeRAWFilter() else { return nil }
        PhotoDocument.configure(filter, settings: nil, defaults: defaults,
                                scale: Float(min(1, 2 * longEdge / fullLongEdge)))
        guard let output = filter.outputImage else { return nil }
        let size = targetSize(longEdge: longEdge)
        guard let baked = bake(PhotoDocument.integralAtOrigin(output), to: size, context: context) else { return nil }
        return RenderBase(image: baked, renderScale: baked.extent.width / info.uprightSize.width,
                          rawStageApplied: false, isHDR: false)
    }

    // MARK: - Analysis

    /// Dehaze airlight (linear working-space RGB), estimated once per photo and cached (preview == export).
    func airlight() -> SIMD3<Float> {
        airlightLock.lock()
        defer { airlightLock.unlock() }
        if let cachedAirlight { return cachedAirlight }
        let value = estimateAirlight() ?? PhotoDocument.fallbackAirlight
        cachedAirlight = value
        return value
    }

    /// Dark channel prior on a ~128 px camera-default SDR copy: the per-pixel minimum over RGB, eroded
    /// with a 5x5 window; the airlight is the mean colour of the brightest 0.1 % of that dark channel
    /// (at least 10 pixels), clamped to 0.05...1.
    private func estimateAirlight() -> SIMD3<Float>? {
        guard let base = thumbnailBase(longEdge: PhotoDocument.airlightAnalysisEdge) else { return nil }
        let engine = RenderEngine.shared
        var image = base.image
        let longest = max(image.extent.width, image.extent.height)
        guard longest >= 4 else { return nil }
        if longest > PhotoDocument.airlightAnalysisEdge {
            let s = PhotoDocument.airlightAnalysisEdge / longest
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s), highQualityDownsample: true)
        }
        image = PhotoDocument.atOrigin(image)
        let width = Int((image.extent.width + 0.001).rounded(.down))
        let height = Int((image.extent.height + 0.001).rounded(.down))
        guard width >= 4, height >= 4 else { return nil }

        let count = width * height
        var pixels = [Float](repeating: 0, count: count * 4)
        let rowBytes = width * 4 * MemoryLayout<Float>.size
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            engine.utilityContext.render(image, toBitmap: address, rowBytes: rowBytes, bounds: bounds,
                                         format: .RGBAf, colorSpace: engine.workingSpace)
        }

        // Unpremultiplied linear RGB (NaN / inf read as 0) and its per-pixel minimum.
        var rgb = [SIMD3<Float>](repeating: SIMD3<Float>(repeating: 0), count: count)
        var minimum = [Float](repeating: 0, count: count)
        var brightest: Float = 0
        for i in 0..<count {
            let alpha = pixels[i * 4 + 3]
            let scale: Float = alpha > 1e-3 ? 1 / alpha : 0
            let r = PhotoDocument.finite(pixels[i * 4] * scale)
            let g = PhotoDocument.finite(pixels[i * 4 + 1] * scale)
            let b = PhotoDocument.finite(pixels[i * 4 + 2] * scale)
            rgb[i] = SIMD3<Float>(r, g, b)
            minimum[i] = min(r, min(g, b))
            brightest = max(brightest, max(r, max(g, b)))
        }
        // Nothing was rendered (or the photo is black): no meaningful estimate.
        guard brightest > 1e-4 else { return nil }

        // 5x5 erosion, separable: horizontal then vertical.
        let radius = 2
        var horizontal = [Float](repeating: 0, count: count)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var m = Float.greatestFiniteMagnitude
                for dx in -radius...radius {
                    let xx = min(max(x + dx, 0), width - 1)
                    m = min(m, minimum[row + xx])
                }
                horizontal[row + x] = m
            }
        }
        var dark = [Float](repeating: 0, count: count)
        for y in 0..<height {
            for x in 0..<width {
                var m = Float.greatestFiniteMagnitude
                for dy in -radius...radius {
                    let yy = min(max(y + dy, 0), height - 1)
                    m = min(m, horizontal[yy * width + x])
                }
                dark[y * width + x] = m
            }
        }

        let topCount = min(count, max(10, count / 1000))
        let order = dark.indices.sorted { dark[$0] > dark[$1] }
        var sum = SIMD3<Float>(repeating: 0)
        for i in order.prefix(topCount) {
            sum += rgb[i]
        }
        let mean = sum / Float(topCount)
        func bounded(_ v: Float) -> Float { v.isFinite ? min(max(v, 0.05), 1) : 0.95 }
        return SIMD3<Float>(bounded(mean.x), bounded(mean.y), bounded(mean.z))
    }

    /// HDR headroom of the source (1 = SDR).
    ///
    /// iOS 18 reads `contentHeadroom` from the HDR decode. iOS 17 cannot: Apple gain maps use Apple's
    /// published MakerApple formula ("Applying Apple HDR effect to your photos"); other HDR sources use
    /// the documented assumptions `assumedGainMapHeadroom` (2.0) and `assumedTransferHeadroom` (~4.9).
    var headroom: Float {
        headroomLock.lock()
        defer { headroomLock.unlock() }
        if let cachedHeadroom { return cachedHeadroom }
        let value = computeHeadroom()
        cachedHeadroom = value
        return value
    }

    private func computeHeadroom() -> Float {
        guard info.isHDR else { return 1 }
        if #available(iOS 18.0, *), !info.isRAW,
           let image = CIImage(data: data, options: [.expandToHDR: true]) {
            let value = image.contentHeadroom          // 0 = unknown, 1 = SDR, > 1 = HDR
            if value.isFinite, value > 1 { return value }
        }
        if let appleGainMapHeadroom { return appleGainMapHeadroom }
        return hasHDRTransfer ? PhotoDocument.assumedTransferHeadroom : PhotoDocument.assumedGainMapHeadroom
    }

    // MARK: - Decoding helpers

    private func wantsHDR(_ recipe: EditRecipe) -> Bool {
        info.isHDR && recipe.keepsHDR
    }

    /// RAW-stage settings of `recipe` (validated first, exactly as the RecipeRenderer does).
    private func rawSettings(for recipe: EditRecipe) -> RAWStageSettings {
        RAWStageSettings(recipe: recipe.clamped(), asShotKelvin: info.asShotKelvin,
                         asShotTint: info.asShotTint, sourceIsHDR: info.isHDR)
    }

    /// Whole-pixel long edge between `minimumLongEdge` and the full resolution; nil for invalid input.
    private func clampedLongEdge(_ longEdge: CGFloat) -> CGFloat? {
        guard longEdge.isFinite, longEdge > 0 else { return nil }
        return min(max(longEdge.rounded(), PhotoDocument.minimumLongEdge), fullLongEdge)
    }

    /// Upright pixel size of a base whose long edge is `longEdge` (never larger than the original).
    private func targetSize(longEdge: CGFloat) -> CGSize {
        let scale = min(1, longEdge / fullLongEdge)
        let full = info.uprightSize
        return CGSize(width: max(1, (full.width * scale).rounded()),
                      height: max(1, (full.height * scale).rounded()))
    }

    private func makeRAWFilter() -> CIRAWFilter? {
        CIRAWFilter(imageData: data, identifierHint: info.typeIdentifier.isEmpty ? nil : info.typeIdentifier)
    }

    /// Applies the RAW stage (or the camera defaults when `settings` is nil) to `filter`. Every property
    /// Noor controls is written each time, so a reused filter never keeps stale values. Sharpness, boost,
    /// local tone mapping, lens correction and gamut mapping stay at the camera defaults in every tier.
    private static func configure(_ filter: CIRAWFilter, settings: RAWStageSettings?, defaults: RAWDefaults,
                                  scale: Float) {
        filter.scaleFactor = scale.isFinite ? min(max(scale, 0.01), 1) : 1
        filter.isDraftModeEnabled = false
        if let settings {
            let extraEV = settings.exposureEV.isFinite ? settings.exposureEV : 0
            filter.exposure = defaults.exposure + extraEV
            filter.neutralTemperature = settings.kelvin
            filter.neutralTint = settings.tint
            if filter.isLuminanceNoiseReductionSupported {
                filter.luminanceNoiseReductionAmount = boosted(defaults.luminanceNR, by: settings.luminanceNR)
            }
            if filter.isColorNoiseReductionSupported {
                filter.colorNoiseReductionAmount = boosted(defaults.colorNR, by: settings.colorNR)
            }
            filter.extendedDynamicRangeAmount = settings.hdr ? 1 : 0
        } else {
            filter.exposure = defaults.exposure
            filter.neutralTemperature = defaults.neutralTemperature
            filter.neutralTint = defaults.neutralTint
            if filter.isLuminanceNoiseReductionSupported {
                filter.luminanceNoiseReductionAmount = defaults.luminanceNR
            }
            if filter.isColorNoiseReductionSupported {
                filter.colorNoiseReductionAmount = defaults.colorNR
            }
            filter.extendedDynamicRangeAmount = 0
        }
    }

    /// Camera default plus `extra` (0...1) of the remaining range: 0 keeps the default, 1 is maximum.
    private static func boosted(_ base: Float, by extra: Float) -> Float {
        let b = base.isFinite ? min(max(base, 0), 1) : 0
        let e = extra.isFinite ? min(max(extra, 0), 1) : 0
        return b + e * (1 - b)
    }

    /// Full-resolution lazy bitmap decode, upright, origin (0,0). Deep sources stay deep (10-bit HEIC,
    /// 16-bit PNG/TIFF, float TIFF). `hdr` expands gain maps; SDR decodes of PQ/HLG are tone mapped.
    private func decodeFullBitmap(hdr: Bool) -> CIImage? {
        var options: [CIImageOption: Any] = [:]
        if info.isHDR {
            if hdr {
                options[.expandToHDR] = true
            } else if hasHDRTransfer {
                options[.toneMapHDRtoSDR] = true
            }
        }
        guard let image = CIImage(data: data, options: options) else { return nil }
        return PhotoDocument.atOrigin(image.oriented(orientation))
    }

    /// Bitmap base at `longEdge`: a subsampled ImageIO decode (falling back to the lazy full decode),
    /// oriented explicitly, scaled to the exact target size and baked once to RGBAh in the working space.
    private func bakeBitmap(longEdge: CGFloat, hdr: Bool, context: CIContext) -> RenderBase? {
        let decodeHDR = hdr && info.isHDR
        guard let decoded = subsampledBitmap(longEdge: longEdge, hdr: decodeHDR) ?? decodeFullBitmap(hdr: decodeHDR),
              let baked = bake(decoded, to: targetSize(longEdge: longEdge), context: context) else {
            return nil
        }
        return RenderBase(image: baked, renderScale: baked.extent.width / info.uprightSize.width,
                          rawStageApplied: false, isHDR: decodeHDR)
    }

    /// ImageIO decode reduced at decode time (2x / 4x / 8x, JPEG / HEIF / TIFF / PNG) to the smallest
    /// size still >= `longEdge`, so no full-resolution decode spike occurs. Floats and deep formats are kept.
    private func subsampledBitmap(longEdge: CGFloat, hdr: Bool) -> CIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        var options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            // Decode once now; the bitmap is released as soon as the bake is done.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if info.isHDR {
            options[kCGImageSourceDecodeRequest] = hdr ? kCGImageSourceDecodeToHDR : kCGImageSourceDecodeToSDR
        }
        if let factor = [8, 4, 2].first(where: { fullLongEdge / CGFloat($0) >= longEdge }) {
            options[kCGImageSourceSubsampleFactor] = factor
            if let cgImage = CGImageSourceCreateImageAtIndex(source, index, options as CFDictionary) {
                return PhotoDocument.atOrigin(CIImage(cgImage: cgImage).oriented(orientation))
            }
            // Some format / decode-request combinations reject subsampling: decode at full size.
            options[kCGImageSourceSubsampleFactor] = nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, options as CFDictionary) else { return nil }
        return PhotoDocument.atOrigin(CIImage(cgImage: cgImage).oriented(orientation))
    }

    /// Scales `image` (origin 0,0) to exactly `size` with Core Image's multi-pass alias-free downsample
    /// (never upscales a smaller decode) and renders it once into an RGBAh bitmap in the working space.
    private func bake(_ image: CIImage, to size: CGSize, context: CIContext) -> CIImage? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, extent.width >= 1, extent.height >= 1 else { return nil }
        var scaled = image
        var outputSize = CGSize(width: (extent.width + 0.001).rounded(.down),
                                height: (extent.height + 0.001).rounded(.down))
        let differs = abs(extent.width - size.width) > 0.01 || abs(extent.height - size.height) > 0.01
        let coversTarget = extent.width + 0.5 >= size.width && extent.height + 0.5 >= size.height
        if differs && coversTarget {
            let transform = CGAffineTransform(scaleX: size.width / extent.width, y: size.height / extent.height)
            scaled = image.transformed(by: transform, highQualityDownsample: true)
            outputSize = size
        }
        let rect = CGRect(origin: .zero, size: outputSize)
        guard let cgImage = context.createCGImage(scaled, from: rect, format: .RGBAh,
                                                  colorSpace: RenderEngine.shared.workingSpace) else {
            return nil
        }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Static helpers

    /// Moves the extent origin to (0,0) so normalized recipe coordinates are stable.
    private static func atOrigin(_ image: CIImage) -> CIImage {
        let e = image.extent
        guard !e.isInfinite, !e.isNull, e.minX != 0 || e.minY != 0 else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }

    /// `atOrigin`, then cropped to whole pixels if the decoder reported a fractional extent.
    private static func integralAtOrigin(_ image: CIImage) -> CIImage {
        let moved = atOrigin(image)
        let e = moved.extent
        guard !e.isInfinite, !e.isNull else { return moved }
        let width = (e.width + 0.001).rounded(.down)
        let height = (e.height + 0.001).rounded(.down)
        guard width >= 1, height >= 1, width != e.width || height != e.height else { return moved }
        return moved.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func swapsAxes(_ orientation: CGImagePropertyOrientation) -> Bool {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }

    private static func isRAWType(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        if identifier == "com.adobe.raw-image" { return true }
        return UTType(identifier)?.conforms(to: .rawImage) ?? false
    }

    private static func profileName(for colorSpace: CGColorSpace?) -> String? {
        guard let name = colorSpace?.name else { return nil }
        return knownProfileNames[name as String]
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }

    /// Apple's published headroom formula for its gain maps (MakerApple tags 33 and 48).
    private static func appleHeadroom(from properties: [String: Any]) -> Float? {
        guard let maker = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any],
              let m33 = (maker["33"] as? NSNumber)?.floatValue,
              let m48 = (maker["48"] as? NSNumber)?.floatValue,
              m33.isFinite, m48.isFinite else { return nil }
        let stops: Float
        if m33 < 1 {
            stops = m48 <= 0.01 ? -20 * m48 + 1.8 : -0.101 * m48 + 1.601
        } else {
            stops = m48 <= 0.01 ? -70 * m48 + 3 : -0.303 * m48 + 2.303
        }
        let headroom = Float(pow(2.0, Double(max(stops, 0))))
        return headroom.isFinite ? max(headroom, 1) : nil
    }

    /// "Apple iPhone 16 Pro" from TIFF Make + Model (the make is not repeated when the model starts with it).
    private static func cameraName(from properties: [String: Any]) -> String? {
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let make = cleaned(tiff?[kCGImagePropertyTIFFMake as String] as? String)
        let model = cleaned(tiff?[kCGImagePropertyTIFFModel as String] as? String)
        guard let model else { return make }
        guard let make else { return model }
        let brand = make.split(separator: " ").first.map(String.init) ?? make
        if model.lowercased().hasPrefix(brand.lowercased()) { return model }
        return "\(make) \(model)"
    }

    /// EXIF DateTimeOriginal (else DateTimeDigitized), in its EXIF offset time zone when one is recorded.
    private static func captureDate(from properties: [String: Any]) -> Date? {
        guard let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return nil }
        let keys: [(date: CFString, offset: CFString)] = [
            (kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifOffsetTimeOriginal),
            (kCGImagePropertyExifDateTimeDigitized, kCGImagePropertyExifOffsetTimeDigitized),
        ]
        for key in keys {
            guard let text = cleaned(exif[key.date as String] as? String) else { continue }
            let offset = cleaned(exif[key.offset as String] as? String)
            if let date = parseExifDate(text, offset: offset) { return date }
        }
        return nil
    }

    private static func parseExifDate(_ text: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = offset.flatMap { PhotoDocument.timeZone(fromExifOffset: $0) } ?? TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: String(text.prefix(19)))
    }

    /// "+03:00" / "-05:30" -> a fixed-offset time zone.
    private static func timeZone(fromExifOffset text: String) -> TimeZone? {
        let chars = Array(text)
        guard chars.count >= 6, chars[0] == "+" || chars[0] == "-", chars[3] == ":",
              let hours = Int(String(chars[1...2])), let minutes = Int(String(chars[4...5])) else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (chars[0] == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\u{0}")))
        return trimmed.isEmpty ? nil : trimmed
    }
}
