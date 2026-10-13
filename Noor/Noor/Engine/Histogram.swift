import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

// MARK: - Histogram

/// The tonal distribution of the edited photo as the user sees it on an SDR display: display-encoded
/// Display P3 values (not linear light), after the same SDR fit the canvas applies.
///
/// Every array has `Histogram.binCount` bins (bin 0 = black, bin 255 = white), normalized for drawing
/// so the tallest bin is 1. The two end bins are left out of that maximum (and capped at 1) so a large
/// clipped area does not flatten the rest of the graph; how much is clipped is reported exactly by
/// `shadowClipping` / `highlightClipping` instead.
struct Histogram: Equatable, Sendable {
    static let binCount = 256

    var red: [Float]
    var green: [Float]
    var blue: [Float]
    /// Luminance (Display P3 weights, computed in linear light, then display-encoded).
    var luma: [Float]
    /// Fraction of pixels (0...1) with at least one channel at black (worst channel).
    var shadowClipping: Float
    /// Fraction of pixels (0...1) with at least one channel at white (worst channel).
    var highlightClipping: Float
}

// MARK: - Histogram computer

/// Computes a `Histogram` from a rendered (linear, extended-range) working-space image.
///
/// Pipeline, all lazy until the single readback:
///   1. alias-free downscale to at most 512 px (a histogram does not need more samples);
///   2. `RecipeRenderer.fitToSDR` (gamut + highlight shoulder: what an SDR display shows);
///   3. display encoding to Display P3, plus a luminance copy;
///   4. two `CIAreaHistogram` reductions (256 bins, bins sum to 1) placed side by side;
///   5. one synchronous float readback (2 x 256 RGBA floats = 8 KB) in the working space, so Core
///      Image applies no colour matching to the counts.
///
/// Confinement: NOT thread-safe (it reuses one readback buffer). The preview renderer owns one and
/// only uses it on its serial render queue.
final class HistogramComputer {
    /// Long edge of the analysed copy.
    private static let analysisLongEdge: CGFloat = 512
    /// Relative luminance of linear Display P3 primaries (D65).
    private static let lumaWeights = (r: CGFloat(0.2289746), g: CGFloat(0.6917385), b: CGFloat(0.0792869))

    /// Provably safe: a built-in named colour space that exists on every supported OS.
    private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
    /// RGBA float readback: RGB histogram in pixels 0..<256, luminance histogram in 256..<512.
    private var buffer = [Float](repeating: 0, count: Histogram.binCount * 2 * 4)

    /// Histogram of `image` rendered with `context`. Synchronous (waits for the GPU); call off the
    /// main thread. Returns nil for an empty or infinite image or when a filter cannot be built.
    func compute(_ image: CIImage, context: CIContext) -> Histogram? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull,
              extent.width >= 1, extent.height >= 1 else { return nil }

        // 1. Small, alias-free copy at origin (0, 0).
        var small = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let scale = min(1, HistogramComputer.analysisLongEdge / max(extent.width, extent.height))
        if scale < 1 {
            small = small.transformed(by: CGAffineTransform(scaleX: scale, y: scale), highQualityDownsample: true)
        }
        // Whole pixels only: a partially covered edge pixel would count as a darker value.
        let region = CGRect(x: 0, y: 0,
                            width: max(1, (extent.width * scale).rounded(.down)),
                            height: max(1, (extent.height * scale).rounded(.down)))

        // 2. What an SDR display shows (values in 0...1, gamut fitted).
        let fitted = RecipeRenderer.fitToSDR(small)

        // 3. Display-encoded colour and luminance.
        guard let encoded = fitted.matchedFromWorkingSpace(to: displayP3),
              let lumaLinear = HistogramComputer.luminance(of: fitted),
              let lumaEncoded = lumaLinear.matchedFromWorkingSpace(to: displayP3) else { return nil }

        // 4. Both reductions in one graph: RGB bins at x 0..<256, luminance bins at x 256..<512.
        let count = Histogram.binCount
        guard let colorBins = HistogramComputer.areaHistogram(of: encoded, region: region, count: count),
              let lumaBins = HistogramComputer.areaHistogram(of: lumaEncoded, region: region, count: count)
        else { return nil }
        let combined = lumaBins
            .transformed(by: CGAffineTransform(translationX: CGFloat(count), y: 0))
            .composited(over: colorBins)

        // 5. Float readback in the working space (no colour matching of the counts).
        let width = count * 2
        let bounds = CGRect(x: 0, y: 0, width: width, height: 1)
        let rowBytes = width * 4 * MemoryLayout<Float>.size
        let space = context.workingColorSpace ?? RenderEngine.shared.workingSpace
        var rendered = false
        buffer.withUnsafeMutableBytes { raw in
            guard let address = raw.baseAddress, raw.count >= rowBytes else { return }
            context.render(combined, toBitmap: address, rowBytes: rowBytes, bounds: bounds,
                           format: .RGBAf, colorSpace: space)
            rendered = true
        }
        guard rendered else { return nil }

        var red = [Float](repeating: 0, count: count)
        var green = red
        var blue = red
        var luma = red
        for i in 0..<count {
            red[i] = HistogramComputer.sanitized(buffer[i * 4])
            green[i] = HistogramComputer.sanitized(buffer[i * 4 + 1])
            blue[i] = HistogramComputer.sanitized(buffer[i * 4 + 2])
            luma[i] = HistogramComputer.sanitized(buffer[(count + i) * 4])
        }

        let last = count - 1
        let shadows = max(HistogramComputer.fraction(red, bin: 0),
                          HistogramComputer.fraction(green, bin: 0),
                          HistogramComputer.fraction(blue, bin: 0))
        let highlights = max(HistogramComputer.fraction(red, bin: last),
                             HistogramComputer.fraction(green, bin: last),
                             HistogramComputer.fraction(blue, bin: last))

        return Histogram(red: HistogramComputer.normalized(red),
                         green: HistogramComputer.normalized(green),
                         blue: HistogramComputer.normalized(blue),
                         luma: HistogramComputer.normalized(luma),
                         shadowClipping: shadows,
                         highlightClipping: highlights)
    }

    // MARK: Filters

    /// Grey image (R = G = B = Y) of the linear luminance; alpha unchanged.
    private static func luminance(of image: CIImage) -> CIImage? {
        let w = lumaWeights
        let row = CIVector(x: w.r, y: w.g, z: w.b, w: 0)
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = row
        filter.gVector = row
        filter.bVector = row
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return filter.outputImage
    }

    /// `count` x 1 histogram image of `region` (bins of each channel sum to 1), moved to origin (0, 0).
    private static func areaHistogram(of image: CIImage, region: CGRect, count: Int) -> CIImage? {
        let filter = CIFilter.areaHistogram()
        filter.inputImage = image
        filter.extent = region
        filter.count = count
        filter.scale = 1
        guard let output = filter.outputImage else { return nil }
        let e = output.extent
        if e.isInfinite || e.isNull {
            return output.cropped(to: CGRect(x: 0, y: 0, width: count, height: 1))
        }
        return output.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }

    // MARK: Numbers

    private static func sanitized(_ value: Float) -> Float {
        value.isFinite && value > 0 ? value : 0
    }

    /// Share of all counted pixels that fell into `bin`.
    private static func fraction(_ bins: [Float], bin: Int) -> Float {
        guard bins.indices.contains(bin) else { return 0 }
        let total = bins.reduce(0, +)
        guard total > 0, total.isFinite else { return 0 }
        return min(max(bins[bin] / total, 0), 1)
    }

    /// Scales bins so the tallest interior bin is 1 (end bins capped at 1). Falls back to the
    /// overall maximum when every pixel sits in an end bin (a black or white frame).
    private static func normalized(_ bins: [Float]) -> [Float] {
        guard bins.count > 2 else { return bins }
        var peak = bins[1..<(bins.count - 1)].max() ?? 0
        if peak <= 0 { peak = bins.max() ?? 0 }
        guard peak > 0, peak.isFinite else { return [Float](repeating: 0, count: bins.count) }
        return bins.map { min($0 / peak, 1) }
    }
}
