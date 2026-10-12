import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

// MARK: - Kernel library

/// Noor's Core Image Metal kernels (`Engine/Kernels.metal`, compiled into the app's
/// `default.metallib` with `-fcikernel` / `-cikernel`) and the thin Swift wrappers that apply them.
///
/// Every kernel is loaded once, lazily and thread-safely (`static let`). A missing library or
/// kernel never crashes the app: the failure is logged once and the matching wrapper returns its
/// input unchanged (or uses a built-in fallback), so editing and export keep working for every
/// other stage.
///
/// Units: wrappers take normalized values (Lightroom slider / 100) and sizes in RENDER pixels or
/// as fractions of the long edge. `RecipeRenderer` converts the recipe into these units.
/// The colour constants assume the extended linear Display P3 working space (`RenderEngine`).
///
/// Thread safety: kernels and `CIImage`s are immutable; every `CIFilter` is created inside the
/// call that uses it and never escapes, so all functions here may run on any thread.
enum NoorKernels {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Noor", category: "Kernels")

    /// Contents of `default.metallib`, or nil when it is missing from the bundle.
    static let library: Data? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else {
            log.error("default.metallib is missing from the app bundle; custom kernels are disabled")
            return nil
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            log.error("default.metallib could not be read: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    static let tone = colorKernel("noorTone")
    static let hsl = colorKernel("noorHSL")
    static let monochrome = colorKernel("noorMonochrome")
    static let grade = colorKernel("noorGrade")
    static let grain = colorKernel("noorGrain")
    static let vignette = colorKernel("noorVignette")
    static let dehazeDark = colorKernel("noorDehazeDark")
    static let dehaze = colorKernel("noorDehaze")
    static let localContrast = colorKernel("noorLocalContrast")
    static let chromaDenoise = colorKernel("noorChromaDenoise")
    static let lumaDenoise = colorKernel("noorLumaDenoise")
    static let colorMatrix = colorKernel("noorColorMatrix")
    static let outputFit = colorKernel("noorOutputFit")
    static let curves = generalKernel("noorCurves")
    static let resample = generalKernel("noorResample")

    private static func colorKernel(_ name: String) -> CIColorKernel? {
        guard let data = library else { return nil }
        do {
            return try CIColorKernel(functionName: name, fromMetalLibraryData: data)
        } catch {
            log.error("Kernel \(name, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func generalKernel(_ name: String) -> CIKernel? {
        guard let data = library else { return nil }
        do {
            return try CIKernel(functionName: name, fromMetalLibraryData: data)
        } catch {
            log.error("Kernel \(name, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Image helpers

extension NoorKernels {
    /// Gaussian blur without dark/transparent borders. `sigma` in render pixels.
    static func blur(_ image: CIImage, sigma: CGFloat) -> CIImage {
        guard sigma.isFinite, sigma > 0.16 else { return image }   // Core Image ignores smaller sigmas
        return image.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: image.extent)
    }

    /// Copy whose long edge is at most `longEdge` pixels (multi-pass, alias-free; never upscales).
    static func downscaled(_ image: CIImage, longEdge: CGFloat) -> CIImage {
        let e = image.extent
        let long = max(e.width, e.height)
        guard long > 0 else { return image }
        let s = min(1, longEdge / long)
        guard s < 1 else { return image }
        return image.transformed(by: CGAffineTransform(scaleX: s, y: s), highQualityDownsample: true)
    }

    /// Small analysis copy: long edge `workingLongEdge` (so effects computed on it do not depend on
    /// the render scale), and always at least 2x smaller than `image` so the guided upsample has
    /// something to upsample (tiny thumbnails).
    static func analysisCopy(_ image: CIImage, workingLongEdge: CGFloat = 512) -> CIImage {
        let long = max(image.extent.width, image.extent.height)
        return downscaled(image, longEdge: min(workingLongEdge, max(long / 2, 8)))
    }

    /// Edge-aware low-pass: blur a small analysis copy, then upsample it guided by `image` so
    /// strong edges stay put (no halos). `relativeSigma` is a fraction of the long edge.
    static func edgeAwareLowpass(_ image: CIImage, relativeSigma: CGFloat, workingLongEdge: CGFloat = 512) -> CIImage {
        let small = analysisCopy(image, workingLongEdge: workingLongEdge)
        let blurred = blur(small, sigma: relativeSigma * max(small.extent.width, small.extent.height))
        let up = CIFilter.edgePreserveUpsample()
        up.inputImage = image
        up.smallImage = blurred
        up.spatialSigma = 3
        up.lumaSigma = 0.15
        return (up.outputImage ?? image).cropped(to: image.extent)
    }

    static func vector(_ v: SIMD3<Float>) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z))
    }

    static func vector(_ v: SIMD4<Float>) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), w: CGFloat(v.w))
    }

    /// Bands 0...3 and 4...7 of an 8-band array as two `float4` vectors (order R O Y G | A B P M).
    static func bandVectors(_ values: [Float]) -> (lo: CIVector, hi: CIVector) {
        var v = values
        if v.count < 8 { v += [Float](repeating: 0, count: 8 - v.count) }
        return (vector(SIMD4(v[0], v[1], v[2], v[3])), vector(SIMD4(v[4], v[5], v[6], v[7])))
    }
}

// MARK: - Colour science (must match Kernels.metal, NOOR_WS_P3)

extension NoorKernels {
    /// A 3x3 matrix stored as rows (`out = M * rgb`).
    struct Matrix3: Equatable, Sendable {
        var r0: SIMD3<Double>
        var r1: SIMD3<Double>
        var r2: SIMD3<Double>

        static let identity = Matrix3(r0: SIMD3(1, 0, 0), r1: SIMD3(0, 1, 0), r2: SIMD3(0, 0, 1))

        static func * (m: Matrix3, v: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3((m.r0 * v).sum(), (m.r1 * v).sum(), (m.r2 * v).sum())
        }

        var isFinite: Bool {
            [r0, r1, r2].allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        }
    }

    /// Luminance weights of linear Display P3 (row Y of its RGB -> XYZ matrix).
    static let lumaWeights = SIMD3<Double>(0.2289745641, 0.6917385218, 0.0792869141)

    /// OKLCH hue (degrees) of Lightroom's 8 colour bands, R O Y G A B P M (the kernels' band centres).
    static let bandHues: [Float] = [29.23, 52.77, 109.79, 142.51, 194.81, 264.06, 293.77, 328.35]

    // Linear P3 -> LMS (rows sum to 1, so white maps to (1, 1, 1) and greys keep a = b = 0).
    private static let toLMS = Matrix3(r0: SIMD3(0.4813798551, 0.4621183723, 0.0565017725),
                                       r1: SIMD3(0.2288319424, 0.6532168190, 0.1179512386),
                                       r2: SIMD3(0.0839457536, 0.2241652693, 0.6918889771))
    private static let fromLMS = Matrix3(r0: SIMD3(3.1277689573, -2.2571357663, 0.1293668090),
                                         r1: SIMD3(-1.0910090160, 2.4133317135, -0.3223226975),
                                         r2: SIMD3(-0.0260108092, -0.5080413222, 1.5340521314))
    private static let lmsToLab = Matrix3(r0: SIMD3(0.2104542553, 0.7936177850, -0.0040720468),
                                          r1: SIMD3(1.9779984951, -2.4285922050, 0.4505937099),
                                          r2: SIMD3(0.0259040371, 0.7827717662, -0.8086757660))
    private static let labToLMS = Matrix3(r0: SIMD3(1, 0.3963377774, 0.2158037573),
                                          r1: SIMD3(1, -0.1055613458, -0.0638541728),
                                          r2: SIMD3(1, -0.0894841775, -1.2914855480))

    /// OKLab (L, a, b) of a linear working-space colour (signed cube root, extended range safe).
    static func okLab(fromLinear rgb: SIMD3<Double>) -> SIMD3<Double> {
        let lms = toLMS * rgb
        return lmsToLab * SIMD3(cbrt(lms.x), cbrt(lms.y), cbrt(lms.z))
    }

    /// Linear working-space colour of an OKLab (L, a, b) value.
    static func linear(fromOKLab lab: SIMD3<Double>) -> SIMD3<Double> {
        let l = labToLMS * lab
        return fromLMS * (l * l * l)
    }

    /// Lightroom / HSL hue (degrees) -> OKLCH hue (degrees), piecewise linear through the band anchors.
    static func okHue(fromLightroomHue h: Float) -> Float {
        let src: [Float] = [0, 30, 60, 120, 180, 240, 270, 300, 360]
        let dst: [Float] = bandHues + [bandHues[0] + 360]
        var x = h.isFinite ? h.truncatingRemainder(dividingBy: 360) : 0
        if x < 0 { x += 360 }
        var i = 0
        while i < 7 && x > src[i + 1] { i += 1 }
        let t = (x - src[i]) / (src[i + 1] - src[i])
        return dst[i] + (dst[i + 1] - dst[i]) * t
    }

    /// Colour-grading wheel -> kernel vector (OKLab chroma offset per unit lightness, log2 L gain).
    /// `hue` in Lightroom degrees, `saturation` 0...1, `luminance` -1...1.
    static func gradeVector(hue: Float, saturation: Float, luminance: Float) -> SIMD3<Float> {
        guard saturation != 0 || luminance != 0 else { return .zero }
        let a = okHue(fromLightroomHue: hue) * .pi / 180
        let c = 0.12 * saturation                                       // chroma per unit lightness
        return SIMD3(c * cos(a), c * sin(a), 0.3 * luminance)           // luminance: up to +-0.9 EV
    }
}

// MARK: - Stage wrappers

extension NoorKernels {
    // MARK: Tone

    /// Basic-panel tone. Sliders are Lightroom / 100 (-1...1); `exposureEV` in stops (non-RAW only).
    struct ToneParams: Equatable, Sendable {
        var exposureEV: Float = 0
        var contrast: Float = 0
        var highlights: Float = 0
        var shadows: Float = 0
        var whites: Float = 0
        var blacks: Float = 0
        var isIdentity: Bool { self == ToneParams() }
    }

    /// Highlights/Shadows act on an edge-aware base layer (local adaptation, detail kept);
    /// contrast/whites/blacks on the pixel. Without the kernel only exposure is applied.
    static func applyTone(_ image: CIImage, _ p: ToneParams) -> CIImage {
        guard !p.isIdentity else { return image }
        guard let kernel = tone else {
            guard p.exposureEV != 0 else { return image }
            let f = CIFilter.exposureAdjust()        // linear gain in the working space
            f.inputImage = image
            f.ev = p.exposureEV
            return f.outputImage?.cropped(to: image.extent) ?? image
        }
        let needsBase = p.highlights != 0 || p.shadows != 0
        let base = needsBase ? edgeAwareLowpass(image, relativeSigma: 0.02) : image
        return kernel.apply(extent: image.extent, arguments: [
            image, base, p.exposureEV, p.contrast, p.highlights, p.shadows, p.whites, p.blacks,
            needsBase ? Float(1) : Float(0),
        ]) ?? image
    }

    // MARK: HSL + vibrance / saturation

    /// Colour mixer. Arrays hold 8 bands (R O Y G A B P M), Lightroom / 100 (-1...1).
    struct HSLParams: Equatable, Sendable {
        var hue = [Float](repeating: 0, count: 8)
        var saturation = [Float](repeating: 0, count: 8)
        var luminance = [Float](repeating: 0, count: 8)
        var vibrance: Float = 0
        var globalSaturation: Float = 0
        var isIdentity: Bool { self == HSLParams() }
    }

    static func applyHSL(_ image: CIImage, _ p: HSLParams) -> CIImage {
        guard !p.isIdentity, let kernel = hsl,
              p.hue.count == 8, p.saturation.count == 8, p.luminance.count == 8 else { return image }
        var hueRadians = [Float](repeating: 0, count: 8)
        for k in 0..<8 {
            // Hue moves toward the neighbouring band, at most half way and at most 30 degrees.
            let next = bandHues[(k + 1) % 8] + (k == 7 ? 360 : 0)
            let prev = bandHues[(k + 7) % 8] - (k == 0 ? 360 : 0)
            let gap = p.hue[k] >= 0 ? next - bandHues[k] : bandHues[k] - prev
            hueRadians[k] = p.hue[k] * min(0.5 * gap, 30) * .pi / 180
        }
        let h = bandVectors(hueRadians)
        let s = bandVectors(p.saturation)
        let l = bandVectors(p.luminance.map { $0 * 0.5 })               // log2 on OKLab L (~ +-1.5 EV)
        return kernel.apply(extent: image.extent, arguments: [
            image, h.lo, h.hi, s.lo, s.hi, l.lo, l.hi, p.vibrance, p.globalSaturation,
        ]) ?? image
    }

    // MARK: Black & white

    /// B&W conversion with a per-band mix (8 bands, Lightroom / 100). Without the kernel the
    /// picture still turns into a neutral grey (plain luminance, no mix).
    static func applyMonochrome(_ image: CIImage, mix: [Float]) -> CIImage {
        guard let kernel = monochrome else {
            let w = lumaWeights
            return applyColorMatrix(image, Matrix3(r0: w, r1: w, r2: w))
        }
        let m = bandVectors(mix)
        return kernel.apply(extent: image.extent, arguments: [image, m.lo, m.hi]) ?? image
    }

    // MARK: Colour matrix

    /// `out = M * rgb` in the linear working space (calibration). Never clamps.
    static func applyColorMatrix(_ image: CIImage, _ m: Matrix3) -> CIImage {
        guard m != .identity, m.isFinite else { return image }
        func row(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
        if let kernel = colorMatrix {
            return kernel.apply(extent: image.extent, arguments: [
                image, vector(row(m.r0)), vector(row(m.r1)), vector(row(m.r2)),
            ]) ?? image
        }
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: CGFloat(m.r0.x), y: CGFloat(m.r0.y), z: CGFloat(m.r0.z), w: 0)
        f.gVector = CIVector(x: CGFloat(m.r1.x), y: CGFloat(m.r1.y), z: CGFloat(m.r1.z), w: 0)
        f.bVector = CIVector(x: CGFloat(m.r2.x), y: CGFloat(m.r2.y), z: CGFloat(m.r2.z), w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return f.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: Colour grading

    /// 3-way + global wheels. Vectors from `gradeVector`; blending 0...1, balance -1...1.
    static func applyGrade(_ image: CIImage, shadows: SIMD3<Float>, midtones: SIMD3<Float>,
                           highlights: SIMD3<Float>, global: SIMD3<Float>,
                           blending: Float, balance: Float) -> CIImage {
        let wheels = [shadows, midtones, highlights, global]
        guard wheels.contains(where: { $0 != .zero }), let kernel = grade else { return image }
        return kernel.apply(extent: image.extent, arguments: [
            image, vector(shadows), vector(midtones), vector(highlights), vector(global), blending, balance,
        ]) ?? image
    }

    // MARK: Tone curve

    /// Width of the curve LUT (texels per curve).
    static let curveLUTWidth = 1024

    /// `width` x 2 RGBAf LUT, not colour managed. Row 0 = master (R = G = B), row 1 = red, green,
    /// blue curves. A = 1 everywhere, so premultiplied == straight (required by bitmapData).
    /// Sampled with `CurveMath`, the same evaluator the curve editor draws with.
    static func curveLUT(_ curves: ToneCurves, width: Int = NoorKernels.curveLUTWidth) -> CIImage {
        let n = max(width, 2)
        let master = CurveMath.samples(curves.master, count: n)
        let red = CurveMath.samples(curves.red, count: n)
        let green = CurveMath.samples(curves.green, count: n)
        let blue = CurveMath.samples(curves.blue, count: n)
        var px = [Float](repeating: 1, count: n * 2 * 4)
        for i in 0..<n {
            px[i * 4 + 0] = master[i]
            px[i * 4 + 1] = master[i]
            px[i * 4 + 2] = master[i]
            let j = (n + i) * 4
            px[j + 0] = red[i]
            px[j + 1] = green[i]
            px[j + 2] = blue[i]
        }
        let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: n * 4 * MemoryLayout<Float>.size,
                       size: CGSize(width: n, height: 2), format: .RGBAf, colorSpace: nil)
    }

    /// Applies a LUT from `curveLUT` in perceptual (gamma 2.2) space; HDR values extrapolate.
    static func applyCurves(_ image: CIImage, lut: CIImage) -> CIImage {
        guard let kernel = curves else { return image }
        let lutExtent = lut.extent
        return kernel.apply(extent: image.extent,
                            roiCallback: { index, rect in index == 0 ? rect : lutExtent },
                            arguments: [image, lut, Float(lutExtent.width)]) ?? image
    }

    // MARK: Dehaze

    /// Dark-channel dehaze computed on a 512 px analysis copy (resolution independent).
    /// `amount` -1...1 (negative adds haze); `airlight` in linear working-space RGB.
    static func applyDehaze(_ image: CIImage, amount: Float, airlight: SIMD3<Float>) -> CIImage {
        guard amount != 0, let darkKernel = dehazeDark, let kernel = dehaze else { return image }
        let small = analysisCopy(image)
        guard let dark0 = darkKernel.apply(extent: small.extent, arguments: [small, vector(airlight)]) else {
            return image
        }
        // Window sizes are fixed fractions of the long edge (6 px and 4 px at 512 px).
        let unit = max(small.extent.width, small.extent.height) / 512
        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = dark0.clampedToExtent()
        erode.radius = Float(6 * unit)                                  // ~1.2 % of the long edge
        let dark = blur((erode.outputImage ?? dark0).cropped(to: small.extent), sigma: 4 * unit)
        let up = CIFilter.edgePreserveUpsample()
        up.inputImage = image
        up.smallImage = dark
        up.spatialSigma = 3
        up.lumaSigma = 0.15
        let darkFull = (up.outputImage ?? image).cropped(to: image.extent)
        return kernel.apply(extent: image.extent, arguments: [
            image, darkFull, vector(airlight), amount, Float(0.95), Float(0.1),
        ]) ?? image
    }

    // MARK: Clarity / texture / sharpening

    /// Clarity: mid-tone local contrast against an edge-aware low-pass at 1.25 % of the long edge.
    static func applyClarity(_ image: CIImage, amount: Float) -> CIImage {
        guard amount != 0, let kernel = localContrast else { return image }
        let coarse = edgeAwareLowpass(image, relativeSigma: 0.0125)
        return kernel.apply(extent: image.extent, arguments: [
            image, image, coarse, amount * 0.8, Float(1), Float(0), Float(0.12),
        ]) ?? image
    }

    /// Texture: band-pass detail (0.04 % ... 0.16 % of the long edge). `renderLongEdge` in render px.
    static func applyTexture(_ image: CIImage, amount: Float, renderLongEdge: CGFloat) -> CIImage {
        guard amount != 0, let kernel = localContrast else { return image }
        let fine = blur(image, sigma: 0.0004 * renderLongEdge)
        let coarse = blur(image, sigma: 0.0016 * renderLongEdge)
        return kernel.apply(extent: image.extent, arguments: [
            image, fine, coarse, amount * 1.5, Float(0.3), Float(0.002), Float(0.06),
        ]) ?? image
    }

    /// Luminance unsharp mask (Lightroom Detail panel): amount 0...150, radius 0.5...3 FULL-RES px,
    /// masking 0...100 (edge gate: 0 sharpens everything, 100 only strong edges).
    /// Skipped when the radius is below ~1/3 render pixel (invisible there; the 1:1 detail tier
    /// and the export render at scale 1 and show it).
    static func applySharpen(_ image: CIImage, amount: Float, radius: Float, masking: Float,
                             renderScale: CGFloat) -> CIImage {
        let sigma = CGFloat(radius) * renderScale
        guard amount > 0, sigma >= 0.35, let kernel = localContrast else { return image }
        let coarse = blur(image, sigma: sigma)
        let threshold = min(max(masking, 0), 100) / 100 * 0.04
        return kernel.apply(extent: image.extent, arguments: [
            image, image, coarse, amount / 150 * 2, Float(0), threshold, Float(0.1),
        ]) ?? image
    }

    // MARK: Noise reduction (non-RAW; RAW uses CIRAWFilter)

    /// Chroma noise: a/b from a blurred copy (edge-aware in the kernel). amount 0...1.
    static func applyChromaNoiseReduction(_ image: CIImage, amount: Float, renderLongEdge: CGFloat) -> CIImage {
        guard amount > 0, let kernel = chromaDenoise else { return image }
        let sigma = 0.0025 * CGFloat(amount) * renderLongEdge           // up to 0.25 % of the long edge
        guard sigma > 0.16 else { return image }
        let blurred = blur(image, sigma: sigma)
        return kernel.apply(extent: image.extent, arguments: [image, blurred, Float(1)]) ?? image
    }

    /// Luminance noise: sigma filter (smooth small differences, keep edges). amount 0...1.
    /// Radius in full-res pixels (noise is per pixel) times the render scale.
    static func applyLuminanceNoiseReduction(_ image: CIImage, amount: Float, renderScale: CGFloat) -> CIImage {
        guard amount > 0, let kernel = lumaDenoise else { return image }
        let sigma = CGFloat(0.6 + 1.4 * amount) * renderScale
        guard sigma >= 0.25 else { return image }
        let blurred = blur(image, sigma: sigma)
        let threshold = 0.01 + 0.04 * amount                            // perceptual (gamma 2.2) units
        return kernel.apply(extent: image.extent, arguments: [image, blurred, min(amount * 1.5, 1), threshold]) ?? image
    }

    // MARK: White balance (non-RAW)

    /// Incremental temperature / tint (Lightroom JPEG scale, -100...100) as a chromatic adaptation,
    /// consistent with `RAWStageSettings`: +-100 == +-150 mired (+ = warmer) and +-150 tint units
    /// (+ = magenta). The shift is split symmetrically around D65 (12 700 K <-> 4 400 K at the
    /// extremes) so both white points stay well inside the filter's range.
    static func applyWhiteBalance(_ image: CIImage, temperature: Double, tint: Double) -> CIImage {
        guard temperature != 0 || tint != 0 else { return image }
        let d65Mired = 1_000_000.0 / 6500.0
        let miredShift = 1.5 * temperature
        let tintShift = 1.5 * tint
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        // Source white warmer-than-target in kelvin => image turns warmer (Apple's own example).
        f.neutral = CIVector(x: CGFloat(1_000_000.0 / (d65Mired - miredShift / 2)), y: CGFloat(tintShift / 2))
        f.targetNeutral = CIVector(x: CGFloat(1_000_000.0 / (d65Mired + miredShift / 2)), y: CGFloat(-tintShift / 2))
        return f.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: Geometry resampling

    /// One high-quality resampling pass (straighten + crop offset). `outputToSource` maps an output
    /// pixel position to the source position it shows; the result has extent (0, 0, outputSize).
    /// The source is clamped to its extent, so rotated corners repeat edge pixels (never black).
    static func applyResample(_ source: CIImage, outputToSource m: CGAffineTransform, outputSize: CGSize) -> CIImage {
        let outRect = CGRect(origin: .zero, size: outputSize)
        let clamped = source.clampedToExtent()
        if let kernel = resample,
           let out = kernel.apply(extent: outRect,
                                  roiCallback: { _, rect in rect.applying(m).insetBy(dx: -3, dy: -3) },
                                  arguments: [clamped,
                                              CIVector(x: m.a, y: m.b, z: m.c, w: m.d),
                                              CIVector(x: m.tx, y: m.ty)]) {
            return out
        }
        // Fallback: Core Image's own (bilinear) affine sampling.
        return clamped.transformed(by: m.inverted()).cropped(to: outRect)
    }

    // MARK: Post-crop vignette and grain

    /// Lightroom post-crop vignette (highlight priority). Values Lightroom / 100.
    /// Relative to the image extent, i.e. the cropped frame.
    struct VignetteParams: Equatable, Sendable {
        var amount: Float = 0        // -1...1
        var midpoint: Float = 0.5    // 0...1
        var roundness: Float = 0     // -1...1
        var feather: Float = 0.5     // 0...1
        var highlights: Float = 0    // 0...1
    }

    static func applyVignette(_ image: CIImage, _ p: VignetteParams) -> CIImage {
        guard p.amount != 0, let kernel = vignette else { return image }
        let e = image.extent
        return kernel.apply(extent: e, arguments: [
            image, CIVector(x: e.minX, y: e.minY, z: e.width, w: e.height),
            p.amount, p.midpoint, p.roundness, p.feather, p.highlights,
        ]) ?? image
    }

    /// Film grain in full-resolution pixel coordinates anchored to the image origin, so the proxy
    /// shows statistically the same grain as the downsampled export. amount/size/roughness 0...1;
    /// `fullLongEdge` = long edge of the (cropped) image in full-res pixels.
    static func applyGrain(_ image: CIImage, amount: Float, size: Float, roughness: Float, seed: UInt32,
                           renderScale: CGFloat, fullLongEdge: CGFloat) -> CIImage {
        guard amount > 0, renderScale > 0, let kernel = grain else { return image }
        let cellFull = (0.5 + 3.5 * size) * Float(fullLongEdge / 3000)   // grain cell in full-res px
        let e = image.extent
        return kernel.apply(extent: e, arguments: [
            image, CIVector(x: e.minX, y: e.minY), Float(1 / renderScale), cellFull, amount, roughness,
            Float(seed % 16_777_216),
        ]) ?? image
    }

    // MARK: Output fit

    /// Gamut fix (negative channels desaturated toward luminance), optional highlight shoulder
    /// [knee, inMax] -> [knee, outMax], then a hue-preserving ceiling at `outMax`.
    static func applyOutputFit(_ image: CIImage, knee: Float, inMax: Float, outMax: Float) -> CIImage {
        guard let kernel = outputFit else { return image }
        return kernel.apply(extent: image.extent, arguments: [image, knee, inMax, outMax]) ?? image
    }
}
