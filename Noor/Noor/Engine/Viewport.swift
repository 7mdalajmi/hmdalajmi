import CoreGraphics
import Foundation

// MARK: - Viewport

/// Which part of the displayed photo the canvas shows, and how large.
///
/// Coordinates follow Core Image (y up) so a viewport maps straight onto the render graph:
///   * `imageSize` and `center` are in FULL-RESOLUTION pixels of the displayed picture, i.e. after
///     geometry (quarter turns, flips, straighten and crop). A proxy or the 1:1 detail image is placed
///     on that grid with `transform(sourceScale:)` / `transform(sourceSize:)`.
///   * `drawableSize` is the canvas' Metal drawable in device pixels (y up, origin bottom-left).
///   * `zoom` is drawable pixels per full-resolution pixel: 1 = 100 % (one photo pixel on one device
///     pixel), `fitZoom` shows the whole picture, `maximumZoom` is 800 %.
///
/// A plain value (Equatable, Sendable): the canvas owns the live copy on the main thread and hands
/// snapshots to the render queue, so nothing here ever needs a lock.
struct Viewport: Equatable, Sendable {
    var drawableSize: CGSize = .zero     // device pixels
    var imageSize: CGSize = .zero        // full-res pixels of the displayed (cropped) picture
    var zoom: CGFloat = 1                // drawable px per full-res px; 1 = 100 %
    var center: CGPoint = .zero          // full-res point shown at the drawable centre (y up)

    /// 800 %: enough to judge grain and sharpening; the detail tier keeps it sharp.
    static let maxZoom: CGFloat = 8

    // MARK: State

    /// The canvas has been laid out (a drawable exists).
    var hasDrawable: Bool { Viewport.isPositive(drawableSize) }
    /// The displayed picture has a known size.
    var hasImage: Bool { Viewport.isPositive(imageSize) }
    /// Both sizes are known and the zoom is usable, so a frame can be drawn.
    var isRenderable: Bool { hasDrawable && hasImage && zoom.isFinite && zoom > 0 }

    // MARK: Zoom limits

    /// The zoom that shows the whole picture (letterboxed). 1 until both sizes are known, so a
    /// viewport that is not laid out yet never carries a zero or infinite zoom.
    var fitZoom: CGFloat {
        guard hasDrawable, hasImage else { return 1 }
        let z = min(drawableSize.width / imageSize.width, drawableSize.height / imageSize.height)
        return z.isFinite && z > 0 ? z : 1
    }

    /// Pinching never goes below "fit".
    var minZoom: CGFloat { fitZoom }

    /// 800 %, or "fit" for a picture so small that fitting it already magnifies more than that.
    var maximumZoom: CGFloat { max(Viewport.maxZoom, fitZoom) }

    /// True when the whole picture is shown (within 0.1 %).
    var isFit: Bool {
        guard isRenderable else { return true }
        return abs(zoom - fitZoom) <= fitZoom * 0.001
    }

    /// Shows the whole picture, centred.
    mutating func fit() {
        zoom = fitZoom
        center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
    }

    // MARK: Mapping

    /// Full-resolution picture pixels -> drawable pixels.
    var imageToDrawable: CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom,
                          tx: drawableSize.width / 2 - center.x * zoom,
                          ty: drawableSize.height / 2 - center.y * zoom)
    }

    /// Maps an image whose pixel grid is `s` x full resolution (proxy: s < 1, detail: s = 1) into
    /// drawable pixels.
    func transform(sourceScale s: CGFloat) -> CGAffineTransform {
        let scale = s.isFinite && s > 0 ? s : 1
        return CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).concatenating(imageToDrawable)
    }

    /// Maps an image that covers the whole displayed picture with `sourceSize` pixels (extent origin
    /// (0, 0)) into drawable pixels. Per axis, so a proxy whose crop was snapped to whole proxy pixels
    /// lines up exactly with the full-resolution detail tier.
    func transform(sourceSize: CGSize) -> CGAffineTransform {
        guard Viewport.isPositive(sourceSize), hasImage else { return imageToDrawable }
        let sx = imageSize.width / sourceSize.width
        let sy = imageSize.height / sourceSize.height
        return CGAffineTransform(scaleX: sx, y: sy).concatenating(imageToDrawable)
    }

    /// The part of the picture (full-res pixels, y up) covered by the drawable. May extend past the
    /// picture when it is letterboxed; intersect with the image extent before cropping.
    var visibleRect: CGRect {
        guard isRenderable else { return .zero }
        let w = drawableSize.width / zoom
        let h = drawableSize.height / zoom
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    /// True when the proxy (`proxyScale` proxy px per full-res px) would be magnified, i.e. blurry,
    /// so the full-resolution detail tier should be rendered. Never true for a proxy that already is
    /// full resolution, or before the canvas is laid out.
    func needsDetail(proxyScale s: CGFloat) -> Bool {
        guard isRenderable, s.isFinite, s > 0, s < 0.999 else { return false }
        return zoom / s > 1.01
    }

    /// Picture point (full-res px, y up) under drawable point `p`.
    func imagePoint(atDrawable p: CGPoint) -> CGPoint {
        let z = zoom > 0 ? zoom : 1
        return CGPoint(x: center.x + (p.x - drawableSize.width / 2) / z,
                       y: center.y + (p.y - drawableSize.height / 2) / z)
    }

    // MARK: Gestures

    /// Zooms by `factor`, keeping the picture point under drawable point `p` in place.
    mutating func zoomBy(_ factor: CGFloat, around p: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        setZoom(zoom * factor, around: p)
    }

    /// Zooms to `target` (clamped to fit...800 %), keeping the picture point under `p` in place.
    mutating func setZoom(_ target: CGFloat, around p: CGPoint) {
        guard target.isFinite, target > 0, hasDrawable else { return }
        let anchor = imagePoint(atDrawable: p)
        zoom = min(max(target, minZoom), maximumZoom)
        center = CGPoint(x: anchor.x - (p.x - drawableSize.width / 2) / zoom,
                         y: anchor.y - (p.y - drawableSize.height / 2) / zoom)
        clampCenter()
    }

    /// Moves the picture by `d` drawable pixels (y up); the picture follows the finger.
    mutating func pan(byDrawable d: CGPoint) {
        guard zoom > 0, d.x.isFinite, d.y.isFinite else { return }
        center.x -= d.x / zoom
        center.y -= d.y / zoom
        clampCenter()
    }

    /// Keeps the zoom inside fit...800 %.
    mutating func clampZoom() {
        guard zoom.isFinite, zoom > 0 else { zoom = fitZoom; return }
        zoom = min(max(zoom, minZoom), maximumZoom)
    }

    /// Keeps the picture on screen: an axis that fits is centred, a larger one cannot be panned past
    /// its edges.
    mutating func clampCenter() {
        guard isRenderable else { return }
        let hw = drawableSize.width / (2 * zoom)
        let hh = drawableSize.height / (2 * zoom)
        center.x = imageSize.width <= 2 * hw
            ? imageSize.width / 2
            : min(max(center.x, hw), imageSize.width - hw)
        center.y = imageSize.height <= 2 * hh
            ? imageSize.height / 2
            : min(max(center.y, hh), imageSize.height - hh)
    }

    /// The same view for a drawable of `size` (rotation, split view, first layout). A fitted view
    /// stays fitted; a zoomed one keeps its zoom and centre (clamped).
    func adapted(toDrawableSize size: CGSize) -> Viewport {
        guard size != drawableSize else { return self }
        var v = self
        let wasFit = !hasDrawable || isFit
        v.drawableSize = size
        if wasFit {
            v.fit()
        } else {
            v.clampZoom()
            v.clampCenter()
        }
        return v
    }

    // MARK: Animation

    /// The viewport `progress` (0...1) of the way to `target`. The zoom moves geometrically and the
    /// centre moves with 1/zoom, which keeps a zoom anchor exactly in place on screen (the double-tap
    /// point stays under the finger the whole way).
    func interpolated(to target: Viewport, progress: CGFloat) -> Viewport {
        let t = progress.isFinite ? min(max(progress, 0), 1) : 1
        guard t < 1 else { return target }
        var v = target
        let z0 = zoom
        let z1 = target.zoom
        var w = t
        if z0 > 0, z1 > 0, z0.isFinite, z1.isFinite {
            let l0 = log(Double(z0))
            let l1 = log(Double(z1))
            let z = CGFloat(exp(l0 + (l1 - l0) * Double(t)))
            v.zoom = z
            let span = 1 / z0 - 1 / z1
            if abs(span) > 1e-12 { w = (1 / z0 - 1 / z) / span }
        } else {
            v.zoom = z0 + (z1 - z0) * t
        }
        v.center = CGPoint(x: center.x + (target.center.x - center.x) * w,
                           y: center.y + (target.center.y - center.y) * w)
        return v
    }

    // MARK: Helpers

    private static func isPositive(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
