import CoreGraphics
import CoreImage
import Foundation

// MARK: - Render options

/// Everything the recipe pipeline needs besides the recipe and the decoded base, so that the
/// interactive proxy, the 1:1 detail view, thumbnails and the export look identical.
struct RenderOptions: Sendable {
    /// Why the image is rendered. The look never depends on it (preview == export).
    enum Purpose: Sendable { case interactive, detail, thumbnail, export }

    var purpose: Purpose
    /// Base pixels per full-resolution pixel (1 = full resolution).
    var renderScale: CGFloat
    /// Upright full-resolution size of the source (before geometry).
    var fullSize: CGSize
    /// True when CIRAWFilter already applied white balance, exposure and noise reduction.
    var rawStageApplied: Bool
    /// Dehaze airlight (linear working-space RGB) from `PhotoDocument.airlight()`.
    var airlight: SIMD3<Float>
    /// False for the crop tool's frame image: no straighten rotation.
    var applyStraighten = true
    /// False returns the whole (oriented, optionally straightened) frame, without the crop and
    /// without the post-crop vignette.
    var applyCrop = true
}

// MARK: - Recipe renderer

/// The whole edit pipeline after decoding: a pure function from (recipe, base image) to a lazy
/// Core Image graph. Cheap to build; nothing is rendered here.
///
/// Order (Lightroom-like):
///   noise reduction (non-RAW) -> dehaze -> white balance (non-RAW) -> tone (exposure for
///   non-RAW, highlights/shadows, contrast, whites, blacks) -> clarity / texture -> tone curve ->
///   calibration -> colour mixer + vibrance/saturation, or B&W mix -> colour grading ->
///   sharpening -> geometry (quarter turns/flips exact, straighten, crop) -> post-crop vignette ->
///   grain.
/// Dehaze runs before the non-RAW white balance because the cached airlight was measured on the
/// un-balanced picture; a (diagonal) white balance commutes with the haze model, so this equals
/// balancing first with a balanced airlight.
///
/// Every stage whose parameters are at default is skipped, so an identity recipe returns the
/// base unchanged (only moved to origin (0, 0)). Nothing is clamped except in `fitToSDR`.
/// Every size is relative to the full-resolution picture and multiplied by the render scale.
enum RecipeRenderer {
    /// Grain pattern seed: constant, so the grain never changes between renders or exports.
    private static let grainSeed: UInt32 = 7_919

    /// Strength of the calibration controls at +-100.
    private static let calibrationMaxHueDegrees = 20.0
    private static let calibrationSaturationGain = 0.4
    private static let calibrationShadowTintChroma: Float = 0.08

    /// Whole pipeline after decode. Input: `RenderBase.image`. Output: linear extended-range
    /// working space, extent origin (0, 0), size = cropped frame at the render scale.
    static func render(_ recipe: EditRecipe, base: CIImage, options: RenderOptions) -> CIImage {
        let r = recipe.clamped()
        var image = movedToOrigin(base)
        let extent = image.extent
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return image }

        let scale = resolvedScale(options, baseExtent: extent)
        let renderLongEdge = max(extent.width, extent.height)

        if !options.rawStageApplied {
            image = NoorKernels.applyLuminanceNoiseReduction(image, amount: Float(r.noiseReduction / 100),
                                                             renderScale: scale)
            image = NoorKernels.applyChromaNoiseReduction(image, amount: Float(r.colorNoiseReduction / 100),
                                                          renderLongEdge: renderLongEdge)
        }
        if r.dehaze != 0 {
            image = NoorKernels.applyDehaze(image, amount: Float(r.dehaze / 100),
                                            airlight: airlight(options, recipe: r))
        }
        if !options.rawStageApplied {
            image = NoorKernels.applyWhiteBalance(image, temperature: r.temperature, tint: r.tint)
        }
        image = NoorKernels.applyTone(image, toneParams(r, rawStageApplied: options.rawStageApplied))
        image = NoorKernels.applyClarity(image, amount: Float(r.clarity / 100))
        image = NoorKernels.applyTexture(image, amount: Float(r.texture / 100), renderLongEdge: renderLongEdge)
        if !r.toneCurve.isIdentity {
            image = NoorKernels.applyCurves(image, lut: NoorKernels.curveLUT(r.toneCurve))
        }
        image = applyCalibration(image, r.calibration)
        if r.isMonochrome {
            // B&W replaces the colour mixer and vibrance/saturation; HSL luminance is the B&W mix.
            image = NoorKernels.applyMonochrome(image, mix: ColorBand.allCases.map { Float(r[band: $0].luminance / 100) })
        } else {
            image = NoorKernels.applyHSL(image, hslParams(r))
        }
        image = applyGrading(image, r.grading)
        if r.sharpening > 0 {
            image = NoorKernels.applySharpen(image, amount: Float(r.sharpening), radius: Float(r.sharpenRadius),
                                             masking: Float(r.sharpenMasking), renderScale: scale)
        }

        image = applyGeometry(image, r.geometry, options: options)

        if options.applyCrop && r.vignette.amount != 0 {
            let v = r.vignette
            image = NoorKernels.applyVignette(image, NoorKernels.VignetteParams(
                amount: Float(v.amount / 100), midpoint: Float(v.midpoint / 100), roundness: Float(v.roundness / 100),
                feather: Float(v.feather / 100), highlights: Float(v.highlights / 100)))
        }
        if r.grain.amount > 0 {
            let out = image.extent
            image = NoorKernels.applyGrain(image, amount: Float(r.grain.amount / 100), size: Float(r.grain.size / 100),
                                           roughness: Float(r.grain.roughness / 100), seed: grainSeed,
                                           renderScale: scale, fullLongEdge: max(out.width, out.height) / scale)
        }
        return image
    }

    /// Final bounding step for SDR targets: out-of-gamut colours desaturated toward their
    /// luminance, values above 1 rolled toward white with their hue kept. In-gamut values in
    /// [0, 1] pass through unchanged, so an unedited SDR photo is not altered.
    static func fitToSDR(_ image: CIImage) -> CIImage {
        NoorKernels.applyOutputFit(image, knee: 1, inMax: 1, outMax: 1)
    }

    // MARK: Parameters

    private static func resolvedScale(_ options: RenderOptions, baseExtent: CGRect) -> CGFloat {
        let s = options.renderScale
        if s.isFinite && s > 0 { return s }
        let fullLong = max(options.fullSize.width, options.fullSize.height)
        guard fullLong.isFinite, fullLong > 0 else { return 1 }
        return max(baseExtent.width, baseExtent.height) / fullLong
    }

    /// The cached airlight was measured on a camera-default decode (exposure 0). A RAW base
    /// already carries the recipe exposure, so the airlight is scaled to match it.
    private static func airlight(_ options: RenderOptions, recipe r: EditRecipe) -> SIMD3<Float> {
        var a = options.airlight
        for i in 0..<3 where !(a[i].isFinite && a[i] > 0) { a[i] = 1 }
        if options.rawStageApplied && r.exposure != 0 {
            a *= Float(exp2(r.exposure))
        }
        return a
    }

    private static func toneParams(_ r: EditRecipe, rawStageApplied: Bool) -> NoorKernels.ToneParams {
        NoorKernels.ToneParams(exposureEV: rawStageApplied ? 0 : Float(r.exposure),
                               contrast: Float(r.contrast / 100),
                               highlights: Float(r.highlights / 100),
                               shadows: Float(r.shadows / 100),
                               whites: Float(r.whites / 100),
                               blacks: Float(r.blacks / 100))
    }

    private static func hslParams(_ r: EditRecipe) -> NoorKernels.HSLParams {
        var p = NoorKernels.HSLParams()
        for (k, band) in ColorBand.allCases.enumerated() where k < 8 {
            let a = r[band: band]
            p.hue[k] = Float(a.hue / 100)
            p.saturation[k] = Float(a.saturation / 100)
            p.luminance[k] = Float(a.luminance / 100)
        }
        p.vibrance = Float(r.vibrance / 100)
        p.globalSaturation = Float(r.saturation / 100)
        return p
    }

    // MARK: Colour grading

    private static func applyGrading(_ image: CIImage, _ g: ColorGrading) -> CIImage {
        guard !g.isIdentity else { return image }
        func vector(_ w: GradeWheel) -> SIMD3<Float> {
            NoorKernels.gradeVector(hue: Float(w.hue), saturation: Float(w.saturation / 100),
                                    luminance: Float(w.luminance / 100))
        }
        return NoorKernels.applyGrade(image, shadows: vector(g.shadows), midtones: vector(g.midtones),
                                      highlights: vector(g.highlights), global: vector(g.global),
                                      blending: Float(g.blending / 100), balance: Float(g.balance / 100))
    }

    // MARK: Calibration

    /// Lightroom Calibration: red/green/blue primary hue & saturation as one 3x3 matrix in the
    /// linear working space, then the shadow tint (green <-> magenta, shadows only).
    private static func applyCalibration(_ image: CIImage, _ c: Calibration) -> CIImage {
        guard !c.isIdentity else { return image }
        var out = image
        if let m = calibrationMatrix(c) {
            out = NoorKernels.applyColorMatrix(out, m)
        }
        if c.shadowTint != 0 {
            // + = magenta, - = green: an OKLab offset along the magenta band's hue, shadows wheel only.
            let h = Double(NoorKernels.bandHues[7]) * .pi / 180
            let k = calibrationShadowTintChroma * Float(c.shadowTint / 100)
            let shadows = SIMD3<Float>(k * Float(cos(h)), k * Float(sin(h)), 0)
            out = NoorKernels.applyGrade(out, shadows: shadows, midtones: .zero, highlights: .zero, global: .zero,
                                         blending: 0.5, balance: 0)
        }
        return out
    }

    /// Moves each primary in OKLCH (hue rotation, chroma scale, lightness kept), then rescales the
    /// three new primaries so that white (1, 1, 1) maps exactly to itself (greys stay neutral).
    /// Extreme combinations that would collapse the gamut are scaled back until the matrix is
    /// well conditioned. Returns nil when the primaries are untouched.
    static func calibrationMatrix(_ c: Calibration) -> NoorKernels.Matrix3? {
        let hues = [c.redHue, c.greenHue, c.blueHue].map { $0 / 100 }
        let sats = [c.redSaturation, c.greenSaturation, c.blueSaturation].map { $0 / 100 }
        guard hues.contains(where: { $0 != 0 }) || sats.contains(where: { $0 != 0 }) else { return nil }

        func build(_ t: Double) -> NoorKernels.Matrix3? {
            var columns: [SIMD3<Double>] = []
            for i in 0..<3 {
                var primary = SIMD3<Double>(repeating: 0)
                primary[i] = 1
                let lab = NoorKernels.okLab(fromLinear: primary)
                let chromaGain = max(1 + t * sats[i] * calibrationSaturationGain, 0)
                let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot() * chromaGain
                let hue = atan2(lab.z, lab.y) + t * hues[i] * calibrationMaxHueDegrees * .pi / 180
                columns.append(NoorKernels.linear(fromOKLab: SIMD3(lab.x, chroma * cos(hue), chroma * sin(hue))))
            }
            let m = NoorKernels.Matrix3(r0: SIMD3(columns[0].x, columns[1].x, columns[2].x),
                                        r1: SIMD3(columns[0].y, columns[1].y, columns[2].y),
                                        r2: SIMD3(columns[0].z, columns[1].z, columns[2].z))
            // White balance of the new primaries: solve M * d = (1, 1, 1).
            guard let d = solve(m, SIMD3(repeating: 1)), d.min() >= 0.25, d.max() <= 4 else { return nil }
            let out = NoorKernels.Matrix3(r0: m.r0 * d, r1: m.r1 * d, r2: m.r2 * d)
            return out.isFinite ? out : nil
        }

        if let m = build(1) { return m }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if build(mid) != nil { lo = mid } else { hi = mid }
        }
        return lo > 0 ? build(lo) : nil
    }

    /// Cramer's rule; nil when the matrix is (nearly) singular.
    private static func solve(_ m: NoorKernels.Matrix3, _ b: SIMD3<Double>) -> SIMD3<Double>? {
        func det(_ p: SIMD3<Double>, _ q: SIMD3<Double>, _ s: SIMD3<Double>) -> Double {
            p.x * (q.y * s.z - q.z * s.y) - p.y * (q.x * s.z - q.z * s.x) + p.z * (q.x * s.y - q.y * s.x)
        }
        let d = det(m.r0, m.r1, m.r2)
        guard d.isFinite, abs(d) > 1e-9 else { return nil }
        // Replace column k with b.
        let x = det(SIMD3(b.x, m.r0.y, m.r0.z), SIMD3(b.y, m.r1.y, m.r1.z), SIMD3(b.z, m.r2.y, m.r2.z)) / d
        let y = det(SIMD3(m.r0.x, b.x, m.r0.z), SIMD3(m.r1.x, b.y, m.r1.z), SIMD3(m.r2.x, b.z, m.r2.z)) / d
        let z = det(SIMD3(m.r0.x, m.r0.y, b.x), SIMD3(m.r1.x, m.r1.y, b.y), SIMD3(m.r2.x, m.r2.y, b.z)) / d
        let s = SIMD3(x, y, z)
        return s.x.isFinite && s.y.isFinite && s.z.isFinite ? s : nil
    }

    // MARK: Geometry

    /// Quarter turns and flips (exact pixel permutations), then straighten (one Catmull-Rom
    /// resampling, edges repeated so no dark corners) and the crop, computed in render pixels.
    /// The crop is snapped to whole render pixels, so an un-straightened crop never resamples, and
    /// is kept inside the frame. The result is moved to origin (0, 0).
    private static func applyGeometry(_ image: CIImage, _ g: Geometry, options: RenderOptions) -> CIImage {
        var img = image
        if g.normalizedTurns != 0 || g.flipHorizontal || g.flipVertical {
            img = movedToOrigin(img.transformed(by: g.orientationTransform(for: img.extent.size)))
        }
        let frame = CGRect(origin: .zero, size: img.extent.size)
        var outRect = frame
        if options.applyCrop && !g.crop.isFull {
            let crop = g.ciCropRect(frameSize: frame.size, integral: true).intersection(frame)
            if !crop.isNull, crop.width >= 1, crop.height >= 1 { outRect = crop }
        }
        if options.applyStraighten && g.straighten != 0 {
            // Output pixel -> frame position (crop offset) -> un-rotated source position.
            let rotation = g.straightenTransform(frameSize: frame.size)
            let outputToSource = CGAffineTransform(translationX: outRect.minX, y: outRect.minY)
                .concatenating(rotation.inverted())
            return NoorKernels.applyResample(img, outputToSource: outputToSource, outputSize: outRect.size)
        }
        if outRect != frame {
            img = img.cropped(to: outRect)
                .transformed(by: CGAffineTransform(translationX: -outRect.minX, y: -outRect.minY))
        }
        return img
    }

    /// The same image with its extent origin at (0, 0) (integer moves only re-index pixels).
    private static func movedToOrigin(_ image: CIImage) -> CIImage {
        let o = image.extent.origin
        guard !image.extent.isInfinite, o.x != 0 || o.y != 0 else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -o.x, y: -o.y))
    }
}
