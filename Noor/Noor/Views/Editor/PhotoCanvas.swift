import CoreImage
import Metal
import QuartzCore
import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

/// The live photo in the editor: a `CanvasView` that the preview renderer draws into.
///
/// The editor model owns every piece of state (recipe, zoom requests, before/after, histogram); this
/// wrapper only creates the canvas once, hands it to the model, and keeps the surround colour in sync
/// with Settings. The photo and its coordinates are always left-to-right (never mirrored in Arabic).
struct PhotoCanvas: UIViewRepresentable {
    let model: EditorModel

    @Environment(AppModel.self) private var app

    func makeUIView(context: Context) -> CanvasView {
        let canvas = CanvasView(device: RenderEngine.shared.device)
        canvas.surround = app.settings.surround
        model.attach(canvas: canvas)
        return canvas
    }

    func updateUIView(_ canvas: CanvasView, context: Context) {
        canvas.surround = app.settings.surround
    }

    static func dismantleUIView(_ canvas: CanvasView, coordinator: ()) {
        canvas.prepareForRemoval()
    }
}

// MARK: - Shared render state

/// The canvas values the preview renderer reads from its own queue: the latest viewport, the surround
/// colour and the screen size (for the proxy resolution).
///
/// Thread safety: every property is guarded by one lock, so the canvas writes on the main thread and
/// the renderer reads on its render queue without ever touching the (main-actor) view itself.
final class CanvasRenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedViewport = Viewport()
    private var storedSurround: CIColor
    private var storedScreenLongEdge: CGFloat = 0

    init(surround: CIColor) {
        storedSurround = surround
    }

    /// The canvas' current viewport (updated on every gesture step).
    var viewport: Viewport {
        get { lock.lock(); defer { lock.unlock() }; return storedViewport }
        set { lock.lock(); storedViewport = newValue; lock.unlock() }
    }

    /// Neutral grey behind the photo (letterbox), as a Core Image colour in the working space.
    var surroundColor: CIColor {
        get { lock.lock(); defer { lock.unlock() }; return storedSurround }
        set { lock.lock(); storedSurround = newValue; lock.unlock() }
    }

    /// Long edge of the screen showing the canvas in device pixels (0 until the view is in a window).
    var screenLongEdgePixels: CGFloat {
        get { lock.lock(); defer { lock.unlock() }; return storedScreenLongEdge }
        set { lock.lock(); storedScreenLongEdge = newValue; lock.unlock() }
    }
}

// MARK: - Canvas view

/// The photo canvas: a `UIView` backed by a `CAMetalLayer` (RGBA half float, extended linear Display P3,
/// EDR when the renderer shows HDR) that `PreviewRenderer` draws into from its render queue.
///
/// The view itself never renders. It owns the `Viewport` (which part of the photo is visible, and how
/// large) and turns gestures into viewport changes:
///   * pinch: zoom between fit and 800 % around the fingers; pan: move (with a short glide);
///   * double-tap: fit <-> 100 % around the tapped point;
///   * press and hold (0.25 s, one finger, <= 12 pt movement): show the original while held;
///   * two-finger tap: toggle the histogram.
/// Each change is reported through `onViewportChange` (`settled == false` while a finger or an
/// animation is still moving), so the model can request a fast proxy frame now and a sharp
/// full-resolution frame once the view settles.
///
/// Always left-to-right: gestures and pixels are never mirrored for right-to-left languages.
final class CanvasView: UIView, UIGestureRecognizerDelegate {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    // MARK: Public state

    /// What is visible. Mirrored into `renderState` for the render queue on every change.
    var viewport = Viewport() {
        didSet { renderState.viewport = viewport }
    }

    /// Called after every viewport change; `settled` is false while a gesture or animation continues.
    var onViewportChange: ((Viewport, _ settled: Bool) -> Void)?
    /// Press-and-hold began (true) or ended (false): show the original while held.
    var onPressChanged: ((Bool) -> Void)?
    /// Two-finger tap (toggles the histogram, Lightroom habit).
    var onTwoFingerTap: (() -> Void)?

    /// Colour around the photo (Settings). A change triggers a redraw through `onViewportChange`.
    var surround: CanvasSurround = .dark {
        didSet {
            guard surround != oldValue else { return }
            applySurround()
            if viewport.isRenderable { reportSettled() }
        }
    }

    /// Values the preview renderer reads from its own queue.
    let renderState: CanvasRenderState

    /// The backing Metal layer.
    var metalLayer: CAMetalLayer {
        // `layerClass` guarantees the layer type, so this cannot fail.
        guard let metal = layer as? CAMetalLayer else {
            preconditionFailure("CanvasView: layerClass must be CAMetalLayer")
        }
        return metal
    }

    // MARK: Private state

    private var simultaneousRecognizers: [UIGestureRecognizer] = []
    private var isPressing = false
    /// A change was reported with `settled == false` and no settled report has followed yet.
    private var hasUnsettledChange = false
    private var animation: CanvasViewportAnimation?
    private var displayLink: CADisplayLink?
    /// Redraws after EDR was turned on (see `setExtendedDynamicRange`).
    private var headroomRefresh: Task<Void, Never>?

    /// Pinch / double-tap snapping tolerance (relative zoom).
    private static let snapTolerance: CGFloat = 0.04
    /// Pan glide: ease-out over `glideDuration`, starting at the finger's speed.
    private static let glideDuration: CFTimeInterval = 0.45
    private static let glideMinimumSpeed: CGFloat = 200      // points per second
    private static let doubleTapDuration: CFTimeInterval = 0.25
    private static let snapDuration: CFTimeInterval = 0.15
    /// When to redraw after EDR was turned on (the display's headroom ramps up over about a second).
    private static let headroomRefreshDelays: [Duration] = [.milliseconds(300), .milliseconds(900)]

    // MARK: Init

    init(device: MTLDevice) {
        renderState = CanvasRenderState(surround: CanvasView.surroundColor(for: .dark))
        super.init(frame: .zero)
        configureLayer(device: device)
        configureView()
        installGestures()
        configureAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configureLayer(device: MTLDevice) {
        let metal = metalLayer
        metal.device = device
        metal.pixelFormat = .rgba16Float                       // half float: no 8-bit banding, EDR capable
        metal.colorspace = RenderEngine.shared.workingSpace    // extended linear Display P3
        metal.framebufferOnly = false                          // Core Image may write with compute kernels
        metal.isOpaque = true
        metal.maximumDrawableCount = 3
        metal.wantsExtendedDynamicRangeContent = false         // the renderer turns it on for HDR frames
    }

    private func configureView() {
        semanticContentAttribute = .forceLeftToRight
        isOpaque = true
        clipsToBounds = true
        isMultipleTouchEnabled = true
        applySurround()
    }

    private func configureAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Photo")
        accessibilityTraits = .image
        accessibilityIgnoresInvertColors = true
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: String(localized: "Zoom to Fit")) { [weak self] _ in
                self?.zoomToFit()
                return true
            },
            UIAccessibilityCustomAction(name: String(localized: "Actual Size")) { [weak self] _ in
                self?.zoomToActualSize()
                return true
            },
        ]
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = currentDisplayScale
        if contentScaleFactor != scale { contentScaleFactor = scale }
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard size.width >= 1, size.height >= 1, size.width.isFinite, size.height.isFinite else { return }
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        guard size != viewport.drawableSize else { return }
        stopAnimation()
        viewport = viewport.adapted(toDrawableSize: size)
        reportSettled()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let screen = window?.windowScene?.screen {
            let native = screen.nativeBounds
            renderState.screenLongEdgePixels = max(native.width, native.height)
            setNeedsLayout()                                   // the display scale may differ per screen
        } else {
            stopAnimation()
            headroomRefresh?.cancel()
            headroomRefresh = nil
            setPressing(false)
        }
    }

    // MARK: Canvas API

    /// Size of the rendered (cropped) picture in full-resolution pixels. `refit` shows the whole
    /// picture; otherwise zoom and centre are kept (clamped to the new size).
    func setImageSize(_ size: CGSize, refit: Bool) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        stopAnimation()
        var next = viewport
        next.imageSize = size
        if refit {
            next.fit()
        } else {
            next.clampZoom()
            next.clampCenter()
        }
        if next != viewport { viewport = next }
    }

    /// Turns EDR presentation on for HDR frames (called by the preview renderer on the main thread).
    func setExtendedDynamicRange(_ enabled: Bool) {
        guard metalLayer.wantsExtendedDynamicRangeContent != enabled else { return }
        metalLayer.wantsExtendedDynamicRangeContent = enabled
        headroomRefresh?.cancel()
        headroomRefresh = nil
        guard enabled else { return }
        // The screen only raises its current EDR headroom once EDR content is requested, so the frame
        // that turned EDR on was tone mapped for the old (usually SDR) headroom. Redraw a couple of
        // times while the display ramps up, so a photo that is just looked at still shows its HDR.
        headroomRefresh = Task { @MainActor [weak self] in
            for delay in CanvasView.headroomRefreshDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.redrawForHeadroomChange()
            }
        }
    }

    /// A settled redraw (the model reads the screen's new headroom), unless something is moving.
    private func redrawForHeadroomChange() {
        guard window != nil, metalLayer.wantsExtendedDynamicRangeContent,
              animation == nil, !hasUnsettledChange, viewport.isRenderable else { return }
        reportSettled()
    }

    /// Zoom to show the whole picture (animated).
    func zoomToFit() {
        guard viewport.isRenderable else { return }
        var target = viewport
        target.fit()
        animate(to: target, duration: CanvasView.doubleTapDuration, curve: .easeInOut)
    }

    /// Zoom to 100 % (one photo pixel per device pixel) around the centre of the view (animated).
    func zoomToActualSize() {
        guard viewport.isRenderable else { return }
        var target = viewport
        target.setZoom(1, around: CGPoint(x: target.drawableSize.width / 2, y: target.drawableSize.height / 2))
        animate(to: target, duration: CanvasView.doubleTapDuration, curve: .easeInOut)
    }

    /// Called when SwiftUI removes the canvas: ends a press in progress and drops the callbacks.
    func prepareForRemoval() {
        stopAnimation()
        headroomRefresh?.cancel()
        headroomRefresh = nil
        setPressing(false)
        onViewportChange = nil
        onPressChanged = nil
        onTwoFingerTap = nil
    }

    // MARK: Gestures

    private func installGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        hold.minimumPressDuration = 0.25
        hold.allowableMovement = 12
        hold.numberOfTouchesRequired = 1

        let continuous: [UIGestureRecognizer] = [pinch, pan, hold]
        for recognizer in continuous { recognizer.delegate = self }
        simultaneousRecognizers = continuous

        let all: [UIGestureRecognizer] = [pinch, pan, doubleTap, twoFingerTap, hold]
        for recognizer in all { addGestureRecognizer(recognizer) }
    }

    /// Pinch, pan and press-and-hold work together (zoom while moving, compare while panning).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        simultaneousRecognizers.contains { $0 === gestureRecognizer }
            && simultaneousRecognizers.contains { $0 === otherGestureRecognizer }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            stopAnimation()
            guard viewport.isRenderable else {
                recognizer.scale = 1
                return
            }
            let before = viewport
            viewport.zoomBy(recognizer.scale, around: drawablePoint(recognizer.location(in: self)))
            recognizer.scale = 1
            if viewport != before { reportChange() }
        case .ended, .cancelled, .failed:
            finishZoom(around: drawablePoint(recognizer.location(in: self)))
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            stopAnimation()
            let translation = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            guard viewport.isRenderable else { return }
            let s = pixelsPerPoint
            let before = viewport
            // UIKit is y-down, the viewport is y-up: the picture follows the finger.
            viewport.pan(byDrawable: CGPoint(x: translation.x * s, y: -translation.y * s))
            if viewport != before { reportChange() }
        case .ended:
            finishPan(velocity: recognizer.velocity(in: self))
        case .cancelled, .failed:
            settleIfNeeded()
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, viewport.isRenderable else { return }
        let point = drawablePoint(recognizer.location(in: self))
        var target = viewport
        let fit = target.fitZoom
        if target.zoom <= fit * 1.001 {
            // Fit -> 100 % at the tapped point (a picture smaller than the view: 2x fit).
            target.setZoom(fit < 1 ? 1 : min(fit * 2, target.maximumZoom), around: point)
        } else {
            target.fit()
        }
        animate(to: target, duration: CanvasView.doubleTapDuration, curve: .easeInOut)
    }

    @objc private func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTwoFingerTap?()
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            setPressing(true)
        case .ended, .cancelled, .failed:
            setPressing(false)
        default:
            break
        }
    }

    private func setPressing(_ pressing: Bool) {
        guard pressing != isPressing else { return }
        isPressing = pressing
        onPressChanged?(pressing)
    }

    /// End of a pinch: snap to fit or to 100 % when close, then report a settled viewport.
    private func finishZoom(around point: CGPoint) {
        guard viewport.isRenderable else { return }
        var target = viewport
        let fit = target.fitZoom
        if abs(target.zoom / fit - 1) < CanvasView.snapTolerance {
            target.fit()
        } else if fit < 1, abs(target.zoom - 1) < CanvasView.snapTolerance {
            target.setZoom(1, around: point)
        }
        animate(to: target, duration: CanvasView.snapDuration, curve: .easeOut)
    }

    /// End of a pan: glide on in the direction of the flick, decelerating, then settle.
    private func finishPan(velocity: CGPoint) {
        // A pinch that ended at the same moment may be snapping; that animation reports the rest.
        guard animation == nil else { return }
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        guard viewport.isRenderable, speed.isFinite, speed > CanvasView.glideMinimumSpeed else {
            settleIfNeeded()
            return
        }
        // An ease-out cubic starts at 3 x distance / duration, so this matches the finger's speed.
        let factor = CGFloat(CanvasView.glideDuration) / 3
        let s = pixelsPerPoint
        var target = viewport
        target.pan(byDrawable: CGPoint(x: velocity.x * s * factor, y: -velocity.y * s * factor))
        animate(to: target, duration: CanvasView.glideDuration, curve: .easeOut)
    }

    // MARK: Animation

    /// Animates to `target` with a display link (snaps when Reduce Motion is on or off screen).
    /// The final step always reports a settled viewport.
    private func animate(to target: Viewport, duration: CFTimeInterval, curve: CanvasViewportAnimation.Curve) {
        stopAnimation()
        guard target != viewport else {
            settleIfNeeded()
            return
        }
        guard duration > 0, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            viewport = target
            reportSettled()
            return
        }
        animation = CanvasViewportAnimation(from: viewport, to: target, start: CACurrentMediaTime(),
                                      duration: duration, curve: curve)
        let link = CADisplayLink(target: CanvasDisplayLinkTarget(view: self),
                                 selector: #selector(CanvasDisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// One display-link frame of the running animation.
    fileprivate func advanceAnimation() {
        guard let running = animation else {
            stopAnimation()
            return
        }
        let elapsed = CACurrentMediaTime() - running.start
        let progress = CGFloat(elapsed / running.duration)
        if progress >= 1 {
            stopAnimation()
            viewport = running.to
            reportSettled()
        } else {
            viewport = running.from.interpolated(to: running.to, progress: running.curve.value(at: progress))
            reportChange()
        }
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        animation = nil
    }

    // MARK: Reporting

    /// A step of a gesture or animation: the model renders a fast proxy frame.
    private func reportChange() {
        hasUnsettledChange = true
        onViewportChange?(viewport, false)
    }

    /// The view came to rest: the model renders the final (detail when zoomed in) frame.
    private func reportSettled() {
        hasUnsettledChange = false
        onViewportChange?(viewport, true)
    }

    /// Ends a gesture that moved the view; a gesture that changed nothing (a pan at fit) stays silent.
    private func settleIfNeeded() {
        if hasUnsettledChange { reportSettled() }
    }

    // MARK: Coordinates

    /// Device pixels per point (the drawable is laid out at the screen's native scale).
    private var currentDisplayScale: CGFloat {
        let traitScale = traitCollection.displayScale
        if traitScale.isFinite, traitScale > 0 { return traitScale }
        if let screenScale = window?.windowScene?.screen.scale, screenScale > 0 { return screenScale }
        return 1
    }

    /// Drawable pixels per point, from the actual drawable so rounding never drifts.
    private var pixelsPerPoint: CGFloat {
        if bounds.width > 0, viewport.drawableSize.width > 0 {
            return viewport.drawableSize.width / bounds.width
        }
        return currentDisplayScale
    }

    /// UIKit point (y down) -> drawable pixel (y up).
    private func drawablePoint(_ point: CGPoint) -> CGPoint {
        let s = pixelsPerPoint
        return CGPoint(x: point.x * s, y: (bounds.height - point.y) * s)
    }

    // MARK: Surround

    private func applySurround() {
        backgroundColor = UIColor(Theme.surround(surround))
        renderState.surroundColor = CanvasView.surroundColor(for: surround)
    }

    /// The Settings surround (`Theme.surround`, the same colour SwiftUI paints around the canvas) as a
    /// Core Image colour. Converted explicitly into the renderer's working space (extended linear
    /// Display P3) and tagged with it, so the drawn letterbox matches the theme exactly whether or
    /// not Core Image colour-matches a `CIColor` from its own space.
    private static func surroundColor(for surround: CanvasSurround) -> CIColor {
        let source = UIColor(Theme.surround(surround)).cgColor
        let space = RenderEngine.shared.workingSpace
        if let converted = source.converted(to: space, intent: .defaultIntent, options: nil),
           let c = converted.components, c.count >= 3,
           let color = CIColor(red: c[0], green: c[1], blue: c[2], colorSpace: space) {
            return color
        }
        return CIColor(cgColor: source)
    }
}

// MARK: - Animation support

/// A running viewport animation (double-tap zoom, pinch snapping, pan glide).
private struct CanvasViewportAnimation {
    enum Curve {
        case easeOut
        case easeInOut

        func value(at t: CGFloat) -> CGFloat {
            let x = min(max(t, 0), 1)
            switch self {
            case .easeOut:
                let u = 1 - x
                return 1 - u * u * u
            case .easeInOut:
                if x < 0.5 { return 4 * x * x * x }
                let u = 2 - 2 * x
                return 1 - u * u * u / 2
            }
        }
    }

    let from: Viewport
    let to: Viewport
    let start: CFTimeInterval
    let duration: CFTimeInterval
    let curve: Curve
}

/// Display-link trampoline: holds the canvas weakly (a `CADisplayLink` retains its target), and stops
/// the link once the canvas is gone.
@MainActor
private final class CanvasDisplayLinkTarget: NSObject {
    private weak var view: CanvasView?

    init(view: CanvasView) {
        self.view = view
        super.init()
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else {
            link.invalidate()
            return
        }
        view.advanceAnimation()
    }
}
