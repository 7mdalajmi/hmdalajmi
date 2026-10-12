import Foundation
import CoreGraphics
import CoreImage

/// Small, display-only renders of a photo through its recipe: library cells, the preset strip and the
/// crop tool's frame image.
///
/// The photo goes through exactly the same `RecipeRenderer` pipeline as the canvas and export, from a
/// small cached base, then is tone-fitted to SDR and encoded as 8-bit Display P3. These bitmaps are only
/// ever shown on screen; nothing is exported from them.
///
/// Thread safety: stateless. `render` is synchronous and may run on any background thread; the
/// document and the engine serialize their own caches.
enum ThumbnailRenderer {
    enum Stage {
        case final          // the full recipe, including straighten and crop
        case frameOnly      // quarter turns + flips applied, NO straighten, NO crop (crop tool backdrop)
    }

    /// Bases up to this long edge come from the document's baked thumbnail base (camera defaults, cheap
    /// and shared by every preset thumbnail). Larger requests (crop tool, deep crops) use the preview proxy,
    /// which already carries the recipe's RAW stage and is usually cached by the canvas.
    private static let thumbnailBaseLimit: CGFloat = 1024

    /// Largest base a thumbnail may ask for (the canvas proxy's upper size). Without it a thumbnail of a
    /// very deep crop would bake a full-resolution RGBAh proxy (384 MB for 48 MP) and keep it cached;
    /// such thumbnails come out a little smaller than `longEdge` instead.
    private static let maximumBaseLongEdge: CGFloat = 3072

    /// Provably safe: a built-in named color space.
    private static let displaySpace = CGColorSpace(name: CGColorSpace.displayP3)!

    /// Placeholder airlight for recipes without dehaze (the renderer never reads it then).
    private static let neutralAirlight = SIMD3<Float>(repeating: 1)

    // MARK: Rendering

    /// Synchronous; call off the main thread. 8-bit Display P3 (tone-fitted to SDR) for display only.
    /// `longEdge` is the long edge of the result in pixels (it is never upscaled past the original).
    static func render(_ document: PhotoDocument, recipe: EditRecipe, longEdge: CGFloat, stage: Stage = .final) -> CGImage? {
        guard longEdge.isFinite, longEdge >= 1 else { return nil }
        return autoreleasepool {
            renderImage(document, recipe: recipe, longEdge: longEdge.rounded(), stage: stage)
        }
    }

    private static func renderImage(_ document: PhotoDocument, recipe: EditRecipe, longEdge: CGFloat,
                                    stage: Stage) -> CGImage? {
        let fullSize = document.uprightSize
        let fullLong = max(fullSize.width, fullSize.height)
        guard fullLong >= 1 else { return nil }

        // Resolution the base needs so the (possibly cropped) result still reaches `longEdge`.
        let geometry = recipe.geometry.clamped()
        let outputSize = stage == .final ? geometry.outputSize(for: fullSize) : geometry.frameSize(for: fullSize)
        let outputLong = max(outputSize.width, outputSize.height, 1)
        let scale = min(1, longEdge / outputLong)
        let baseLong = min((fullLong * scale).rounded(.up), maximumBaseLongEdge)

        guard let base = makeBase(document, recipe: recipe, baseLongEdge: baseLong) else { return nil }

        // The airlight only feeds dehaze. Skipping it at dehaze 0 saves a separate analysis decode
        // (a demosaic for RAW) per library / preset thumbnail; the pixels are identical either way.
        let airlight = recipe.clamped().dehaze != 0 ? document.airlight() : neutralAirlight
        var options = RenderOptions(purpose: .thumbnail,
                                    renderScale: base.renderScale,
                                    fullSize: fullSize,
                                    rawStageApplied: base.rawStageApplied,
                                    airlight: airlight)
        options.applyStraighten = stage == .final
        options.applyCrop = stage == .final

        let edited = RecipeRenderer.render(recipe, base: base.image, options: options)
        let fitted = RecipeRenderer.fitToSDR(edited)
        return encode(fitted, longEdge: longEdge, context: RenderEngine.shared.utilityContext)
    }

    /// Small requests share the camera-default thumbnail base; large ones use the recipe's preview proxy.
    /// Each falls back to the other if its decode fails.
    private static func makeBase(_ document: PhotoDocument, recipe: EditRecipe, baseLongEdge: CGFloat) -> RenderBase? {
        if baseLongEdge <= thumbnailBaseLimit {
            return document.thumbnailBase(longEdge: baseLongEdge)
                ?? document.previewBase(for: recipe, longEdge: baseLongEdge)
        }
        return document.previewBase(for: recipe, longEdge: baseLongEdge)
            ?? document.thumbnailBase(longEdge: thumbnailBaseLimit)
    }

    // MARK: Encoding

    /// Moves the result to the origin, downsizes it (alias-free) to `longEdge` when larger, and renders an
    /// RGBA8 Display P3 bitmap of whole pixels.
    private static func encode(_ image: CIImage, longEdge: CGFloat, context: CIContext) -> CGImage? {
        var output = image
        var extent = output.extent
        guard !extent.isInfinite, !extent.isNull, extent.width >= 0.5, extent.height >= 0.5 else { return nil }
        if extent.minX != 0 || extent.minY != 0 {
            output = output.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            extent = output.extent
        }

        var size = CGSize(width: max(1, (extent.width + 0.001).rounded(.down)),
                          height: max(1, (extent.height + 0.001).rounded(.down)))
        let longest = max(extent.width, extent.height)
        if longest > longEdge + 0.5 {
            let s = longEdge / longest
            let target = CGSize(width: max(1, (extent.width * s).rounded()),
                                height: max(1, (extent.height * s).rounded()))
            let transform = CGAffineTransform(scaleX: target.width / extent.width, y: target.height / extent.height)
            output = output.transformed(by: transform, highQualityDownsample: true)
            size = target
        }

        // Edge pixels are extended so a fractional extent never leaves a half-transparent border.
        let rect = CGRect(origin: .zero, size: size)
        return context.createCGImage(output.clampedToExtent().cropped(to: rect), from: rect,
                                     format: .RGBA8, colorSpace: displaySpace)
    }
}
