import Foundation
import CoreGraphics

// MARK: - Crop / rotate / flip / straighten
//
// Coordinate model (shared by the crop UI and the render engine, so preview == export):
//   1. The upright source (orientation already applied) is rotated clockwise in exact 90° steps,
//      then flipped. These are pixel permutations: no resampling, no quality loss.
//      The result is the "frame" (frameSize = source size with axes swapped for odd turns).
//   2. Straighten rotates the picture inside that frame about its centre (+ = clockwise).
//      This is the only geometry step that resamples.
//   3. `crop` is a rectangle in the frame, normalized 0...1 with a TOP-LEFT origin (UI convention).
//      When straighten != 0 the crop must stay inside the rotated picture (see `constrained`).
//   Core Image uses a bottom-left origin; the conversions live here and nowhere else.

struct NormalizedRect: Codable, Hashable, Sendable {
    var x = 0.0
    var y = 0.0
    var width = 1.0
    var height = 1.0

    static let full = NormalizedRect()

    var isFull: Bool {
        abs(x) < 1e-6 && abs(y) < 1e-6 && abs(width - 1) < 1e-6 && abs(height - 1) < 1e-6
    }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
}

enum CropAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, free, square, r4x5, r5x4, r3x2, r2x3, r16x9, r9x16
    var id: String { rawValue }

    /// width / height in pixels, or nil for free-form.
    func ratio(frameSize: CGSize) -> Double? {
        switch self {
        case .original: return frameSize.height > 0 ? Double(frameSize.width / frameSize.height) : nil
        case .free: return nil
        case .square: return 1
        case .r4x5: return 4.0 / 5.0
        case .r5x4: return 5.0 / 4.0
        case .r3x2: return 3.0 / 2.0
        case .r2x3: return 2.0 / 3.0
        case .r16x9: return 16.0 / 9.0
        case .r9x16: return 9.0 / 16.0
        }
    }

    /// The same ratio in the other orientation (portrait <-> landscape).
    var swapped: CropAspect {
        switch self {
        case .r4x5: return .r5x4
        case .r5x4: return .r4x5
        case .r3x2: return .r2x3
        case .r2x3: return .r3x2
        case .r16x9: return .r9x16
        case .r9x16: return .r16x9
        default: return self
        }
    }

    /// Short label shown on the aspect chips ("1:1", "4:5", ...). Original/Free are localized by the UI.
    var ratioLabel: String? {
        switch self {
        case .original, .free: return nil
        case .square: return "1:1"
        case .r4x5: return "4:5"
        case .r5x4: return "5:4"
        case .r3x2: return "3:2"
        case .r2x3: return "2:3"
        case .r16x9: return "16:9"
        case .r9x16: return "9:16"
        }
    }
}

struct Geometry: Codable, Hashable, Sendable {
    var quarterTurns = 0            // clockwise 90° steps, 0...3
    var flipHorizontal = false      // applied after the quarter turns, in the frame
    var flipVertical = false
    var straighten = 0.0            // degrees, -45...45, + = clockwise
    var crop = NormalizedRect.full  // in the frame, top-left origin
    var aspect: CropAspect = .original

    init() {}

    var isIdentity: Bool {
        normalizedTurns == 0 && !flipHorizontal && !flipVertical && straighten == 0 && crop.isFull
    }
    /// True when only lossless steps (turns, flips, pixel-aligned crop) are used.
    var isLossless: Bool { straighten == 0 }
    var normalizedTurns: Int { ((quarterTurns % 4) + 4) % 4 }
    var swapsAxes: Bool { normalizedTurns % 2 == 1 }

    func clamped() -> Geometry {
        var g = self
        g.quarterTurns = normalizedTurns
        g.straighten = straighten.isFinite ? min(max(straighten, -45), 45) : 0
        var c = crop
        let ok = [c.x, c.y, c.width, c.height].allSatisfy(\.isFinite)
        if !ok { c = .full }
        c.width = min(max(c.width, 0.01), 1)
        c.height = min(max(c.height, 0.01), 1)
        c.x = min(max(c.x, 0), 1 - c.width)
        c.y = min(max(c.y, 0), 1 - c.height)
        g.crop = c
        return g
    }

    // MARK: Sizes

    /// Frame size (after quarter turns) for an upright source of `size`.
    func frameSize(for size: CGSize) -> CGSize {
        swapsAxes ? CGSize(width: size.height, height: size.width) : size
    }

    /// Full-resolution output pixel size for an upright source of `sourceSize`.
    func outputSize(for sourceSize: CGSize) -> CGSize {
        ciCropRect(frameSize: frameSize(for: sourceSize), integral: true).size
    }

    // MARK: Core Image transforms (y-up)

    /// Exact integer transform: clockwise quarter turns, then flips. Maps an image whose extent is
    /// (0, 0, size) onto (0, 0, frameSize). No resampling happens for these matrices.
    func orientationTransform(for size: CGSize) -> CGAffineTransform {
        var t = CGAffineTransform.identity
        var w = size.width
        var h = size.height
        for _ in 0..<normalizedTurns {
            // 90° clockwise in a y-up space: (x, y) -> (y, w - x); new size is h × w.
            t = t.concatenating(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
            swap(&w, &h)
        }
        if flipHorizontal {
            t = t.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
        }
        if flipVertical {
            t = t.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h))
        }
        return t
    }

    /// Straighten rotation about the frame centre (+ degrees = clockwise on screen).
    func straightenTransform(frameSize: CGSize) -> CGAffineTransform {
        let cx = frameSize.width / 2
        let cy = frameSize.height / 2
        let radians = CGFloat(straighten * .pi / 180)
        // y-up space: a clockwise turn is a negative angle.
        return CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: -radians)
            .translatedBy(x: -cx, y: -cy)
    }

    /// Crop rectangle in Core Image coordinates of a frame of `frameSize`.
    /// `integral: true` snaps to whole pixels (export: a pixel-exact, lossless crop).
    func ciCropRect(frameSize: CGSize, integral: Bool) -> CGRect {
        let W = Double(frameSize.width)
        let H = Double(frameSize.height)
        var minX = crop.x * W
        var maxX = (crop.x + crop.width) * W
        var maxYTop = (crop.y + crop.height) * H     // distance from the top edge
        var minYTop = crop.y * H
        if integral {
            minX = minX.rounded(); maxX = maxX.rounded()
            minYTop = minYTop.rounded(); maxYTop = maxYTop.rounded()
        }
        minX = min(max(minX, 0), W)
        maxX = min(max(maxX, minX + 1), max(W, minX + 1))
        minYTop = min(max(minYTop, 0), H)
        maxYTop = min(max(maxYTop, minYTop + 1), max(H, minYTop + 1))
        return CGRect(x: minX, y: H - maxYTop, width: maxX - minX, height: maxYTop - minYTop)
    }

    // MARK: Crop constraints (shared by the crop UI and the engine)

    /// Shrinks / moves `rect` (about its centre) until it only covers picture pixels once the
    /// picture is straightened by `degrees` inside a frame of `frameSize`. Aspect is preserved.
    static func constrained(_ rect: NormalizedRect, frameSize: CGSize, straighten degrees: Double) -> NormalizedRect {
        let W = Double(max(frameSize.width, 1))
        let H = Double(max(frameSize.height, 1))
        var r = rect
        r.width = min(max(r.width, 0.01), 1)
        r.height = min(max(r.height, 0.01), 1)
        r.x = min(max(r.x, 0), 1 - r.width)
        r.y = min(max(r.y, 0), 1 - r.height)
        guard degrees != 0 else { return r }

        let th = degrees * .pi / 180
        let c = cos(th)
        let s = sin(th)
        // Pixel coordinates relative to the frame centre, y down (same sense as the UI).
        func inside(_ px: Double, _ py: Double) -> Bool {
            let u = c * px + s * py
            let v = -s * px + c * py
            return abs(u) <= W / 2 + 1e-6 && abs(v) <= H / 2 + 1e-6
        }
        var cx = (r.midX - 0.5) * W
        var cy = (r.midY - 0.5) * H
        let hw = r.width * W / 2
        let hh = r.height * H / 2

        if !inside(cx, cy) {
            var lo = 0.0, hi = 1.0
            for _ in 0..<40 {
                let m = (lo + hi) / 2
                if inside(cx * m, cy * m) { lo = m } else { hi = m }
            }
            cx *= lo; cy *= lo
        }
        func fits(_ k: Double) -> Bool {
            inside(cx - hw * k, cy - hh * k) && inside(cx + hw * k, cy - hh * k)
                && inside(cx - hw * k, cy + hh * k) && inside(cx + hw * k, cy + hh * k)
        }
        var k = 1.0
        if !fits(1) {
            var lo = 0.0, hi = 1.0
            for _ in 0..<50 {
                let m = (lo + hi) / 2
                if fits(m) { lo = m } else { hi = m }
            }
            k = lo
        }
        let nw = max(r.width * k, 0.01)
        let nh = max(r.height * k, 0.01)
        return NormalizedRect(x: cx / W + 0.5 - nw / 2, y: cy / H + 0.5 - nh / 2, width: nw, height: nh)
    }

    /// The largest centred crop with `aspect` (width/height in pixels; nil = frame aspect) that
    /// fits the frame and, when straightened, contains only picture pixels.
    static func maximalCrop(frameSize: CGSize, straighten degrees: Double, aspect: Double?) -> NormalizedRect {
        let W = Double(max(frameSize.width, 1))
        let H = Double(max(frameSize.height, 1))
        let a = aspect ?? (W / H)
        var w = W
        var h = W / a
        if h > H { h = H; w = H * a }
        let r = NormalizedRect(x: 0.5 - w / W / 2, y: 0.5 - h / H / 2, width: w / W, height: h / H)
        return constrained(r, frameSize: frameSize, straighten: degrees)
    }
}
