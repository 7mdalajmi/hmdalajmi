import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import QuartzCore
import UIKit

// MARK: - Request

/// One preview frame to draw. A plain value: the editor model builds it on the main thread and the
/// renderer consumes it on its render queue. The viewport is not part of the request: the renderer
/// reads the canvas' latest viewport when it draws, so a pan never shows a stale position.
struct PreviewRequest: Sendable {
    enum Tier: Sendable {
        /// The interactive proxy (about screen size), used at fit and while anything moves.
        case proxy
        /// The full-resolution pipeline, limited to the visible region (zoomed in past the proxy).
        case detail
    }

    var recipe: EditRecipe
    /// Render `EditRecipe()` but keep the recipe's geometry (before/after compare).
    var showOriginal: Bool
    var tier: Tier
    /// Present HDR headroom (EDR) when the photo is HDR and the screen can show it.
    var edr: Bool
    /// The screen's current EDR headroom (1 = SDR).
    var targetHeadroom: Float
    /// Compute a histogram from the proxy result after presenting.
    var wantsHistogram: Bool
}

// MARK: - Preview renderer

/// Draws the editor canvas: original file -> recipe pipeline -> viewport -> `CAMetalLayer` drawable,
/// all on the GPU (no CPU readback, no 8-bit step), with the same `RecipeRenderer` the export uses.
///
/// Scheduling ("latest wins", no debounce): `submit` stores the request and enqueues a drain on a
/// private serial queue. A drain takes whatever request is newest at that moment, so any number of
/// slider ticks during one frame produce exactly one more frame. `CAMetalLayer.nextDrawable()` caps the
/// frames in flight (three drawables), which bounds latency.
///
/// Tiers: the proxy (`PhotoDocument.previewBase`, ~screen size) is drawn at fit and while anything moves;
/// the detail tier (`fullBase`, render scale 1) is the exact export look, cropped to the visible region
/// so its cost follows the visible pixels, not the photo size.
///
/// Thread safety: `submit`, `stop`, `onHistogram` and `proxyScale` may be used from any thread (one lock guards
/// the shared fields); `attach(canvas:)` runs on the main thread. Everything else, including the
/// histogram computer and every `CIFilter`, is confined to the render queue. The canvas view (main
/// actor) is never touched from the render queue: its viewport and surround are read from the
/// lock-protected `CanvasRenderState`, and size / EDR updates are sent back to the main actor.
final class PreviewRenderer: @unchecked Sendable {
    // MARK: Configuration

    /// Proxy long edge bounds: at least 2048 px, at most 3072 px (2560 x 1707 RGBAh is ~35 MB).
    private static let minimumProxyLongEdge: CGFloat = 2048
    private static let maximumProxyLongEdge: CGFloat = 3072
    /// Sampling margin (full-res px) kept around the visible region of a detail frame.
    private static let detailMargin: CGFloat = 4

    // MARK: Immutable

    private let document: PhotoDocument
    private let engine: RenderEngine
    private let queue = DispatchQueue(label: "noor.preview.render", qos: .userInteractive)

    // MARK: Lock-protected (any thread)

    private let lock = NSLock()
    private var pendingRequest: PreviewRequest?
    private var target: CanvasTarget?
    private var targetGeneration: UInt64 = 0
    /// Set by `stop()`: no request is accepted or drawn afterwards.
    private var isStopped = false
    private var histogramHandler: (@Sendable (Histogram) -> Void)?
    private var resolvedProxyLongEdge: CGFloat?
    private var measuredProxyScale: CGFloat?

    // MARK: Render-queue confined

    private let histogramComputer = HistogramComputer()
    /// The EDR state last sent to the current canvas (avoids a main-actor hop per frame).
    private var presentedEDR: (target: UInt64, enabled: Bool)?

    // MARK: Init

    init(document: PhotoDocument) {
        self.document = document
        self.engine = RenderEngine.shared
    }

    // MARK: Public API

    /// Receives a histogram after each frame that asked for one. Called on the render queue.
    var onHistogram: (@Sendable (Histogram) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return histogramHandler }
        set { lock.lock(); histogramHandler = newValue; lock.unlock() }
    }

    /// Proxy pixels per full-resolution pixel: the last proxy actually rendered, or an estimate from
    /// the screen-sized proxy target before the first frame.
    var proxyScale: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        if let measuredProxyScale { return measuredProxyScale }
        return estimatedProxyScale(longEdge: resolvedProxyLongEdge ?? PreviewRenderer.minimumProxyLongEdge)
    }

    /// Makes `canvas` the drawing target (replacing a previous canvas). Main thread.
    @MainActor
    func attach(canvas: CanvasView) {
        let layer = canvas.metalLayer
        let state = canvas.renderState
        lock.lock()
        defer { lock.unlock() }
        guard !isStopped else { return }
        targetGeneration &+= 1
        target = CanvasTarget(canvas: WeakCanvas(canvas), layer: layer, state: state, id: targetGeneration)
    }

    /// Ends drawing for good (the editor closed). Any thread. Drops the queued request, the canvas and
    /// the histogram handler; later `submit` / `attach` calls are ignored. Then, on the render queue
    /// (so after a frame that may still be rendering, and never on the main thread, where waiting
    /// for the document's decode lock could stall the UI), frees the document's full-resolution
    /// decode and the preview caches. A frame already in progress may still finish.
    func stop() {
        lock.lock()
        isStopped = true
        pendingRequest = nil
        target = nil
        histogramHandler = nil
        lock.unlock()
        let document = self.document
        let engine = self.engine
        queue.async {
            document.purgeFullResolution()
            engine.clearCaches()
        }
    }

    /// Queues `request`; a newer request submitted before the render queue gets to it replaces it.
    /// A histogram asked for by a replaced request is kept: the model often replaces a proxy request
    /// that wanted one with a detail request that does not, and that histogram must not be lost.
    func submit(_ request: PreviewRequest) {
        var next = request
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        if let replaced = pendingRequest, replaced.wantsHistogram {
            next.wantsHistogram = true
        }
        pendingRequest = next
        lock.unlock()
        queue.async { [weak self] in
            self?.drain()
        }
    }

    // MARK: Scheduling

    private func drain() {
        lock.lock()
        let request = pendingRequest
        pendingRequest = nil
        lock.unlock()
        // An earlier drain already took the newest request: nothing to do.
        guard let request else { return }
        autoreleasepool {
            render(request)
        }
    }

    // MARK: Rendering

    private func render(_ request: PreviewRequest) {
        guard let target = currentTarget(), let layer = target.layer else { return }
        let state = target.state
        let snapshot = state.viewport
        guard snapshot.isRenderable else { return }       // not laid out yet: nothing to draw into

        let recipe = request.showOriginal
            ? PreviewRenderer.originalRecipe(keepingGeometryOf: request.recipe)
            : request.recipe
        let proxyLongEdge = resolveProxyLongEdge(state: state, viewport: snapshot)

        // 1. Pipeline outputs (the expensive part: decode / RAW stage happen here, before a drawable
        //    is held). The proxy is also the fallback and the histogram source.
        var detail: PipelineOutput?
        var proxy: PipelineOutput?
        if request.tier == .detail, snapshot.needsDetail(proxyScale: proxyScale) {
            detail = detailOutput(for: recipe)
        }
        if detail == nil || request.wantsHistogram {
            proxy = proxyOutput(for: recipe, longEdge: proxyLongEdge)
        }
        guard var frame = detail ?? proxy else { return }

        // 2. A drawable, then the freshest viewport (a finger may have moved meanwhile).
        guard let drawable = layer.nextDrawable() else { return }
        let texture = drawable.texture
        guard texture.width > 0, texture.height > 0 else { return }
        let drawableSize = CGSize(width: texture.width, height: texture.height)
        var viewport = state.viewport
        guard viewport.isRenderable else { return }

        // A detail frame is only worth it while zoomed in, and only for the size the canvas expects.
        if frame.isDetail,
           !viewport.needsDetail(proxyScale: proxyScale) || PreviewRenderer.sizeDiffers(frame, from: viewport.imageSize) {
            guard let fallback = proxy ?? proxyOutput(for: recipe, longEdge: proxyLongEdge) else { return }
            proxy = fallback
            frame = fallback
        }
        // The canvas' picture size disagrees with what the pipeline produced (geometry changed without
        // the canvas being told): draw this frame refitted and correct the canvas on the main actor.
        // Only the newest request corrects the canvas, so an older frame that finishes after a
        // geometry change never undoes the size the model has just set.
        if PreviewRenderer.sizeDiffers(frame, from: viewport.imageSize) {
            let size = frame.fullResolutionSize
            viewport.imageSize = size
            viewport.fit()
            if !hasPendingRequest {
                sendImageSize(size, to: target.canvas)
            }
        }
        viewport = viewport.adapted(toDrawableSize: drawableSize)
        let bounds = CGRect(origin: .zero, size: drawableSize)

        // 3. Map onto the drawable (only the drawable's pixels are ever computed).
        var image = displayImage(frame, viewport: viewport).cropped(to: bounds)

        // 4. Fit to the display: HDR headroom (iOS 18) or SDR.
        var edrActive = false
        if request.edr, frame.isHDR, #available(iOS 18.0, *) {
            let toneMap = CIFilter.toneMapHeadroom()
            toneMap.inputImage = image
            toneMap.sourceHeadroom = max(document.headroom, 1)
            toneMap.targetHeadroom = request.targetHeadroom.isFinite ? max(request.targetHeadroom, 1) : 1
            if let mapped = toneMap.outputImage {
                image = mapped
                edrActive = true
            }
        }
        if !edrActive {
            image = RecipeRenderer.fitToSDR(image)
        }
        updatePresentedEDR(edrActive, target: target)

        // 5. Over the surround, into the drawable.
        let surround = CIImage(color: state.surroundColor).cropped(to: bounds)
        let composed = image.composited(over: surround)

        guard let commandBuffer = engine.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "noor.canvas"
        let destination = CIRenderDestination(width: texture.width, height: texture.height,
                                              pixelFormat: texture.pixelFormat, commandBuffer: commandBuffer,
                                              mtlTextureProvider: { texture })
        destination.colorSpace = engine.workingSpace          // == the layer's colorspace
        destination.isClamped = !edrActive
        do {
            _ = try engine.previewContext.startTask(toRender: composed, from: bounds, to: destination, at: .zero)
        } catch {
            return
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        // 6. Histogram of the whole proxy result (not the zoomed crop), after the frame is on its way.
        if request.wantsHistogram, let source = proxy, let handler = onHistogram,
           let histogram = histogramComputer.compute(source.image, context: engine.previewContext) {
            handler(histogram)
        }
    }

    /// The pipeline output placed on the drawable grid. A detail frame is first cropped to the visible
    /// region; at 100 % it stays pixel-aligned, and from 200 % it shows true pixels (nearest sampling).
    private func displayImage(_ frame: PipelineOutput, viewport: Viewport) -> CIImage {
        var image = frame.image
        var transform = viewport.transform(sourceSize: image.extent.size)
        if frame.isDetail {
            let visible = viewport.visibleRect
                .insetBy(dx: -PreviewRenderer.detailMargin, dy: -PreviewRenderer.detailMargin)
                .integral
                .intersection(image.extent)
            guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return CIImage.empty() }
            image = image.cropped(to: visible)
            if viewport.zoom >= 2 {
                image = image.samplingNearest()
            }
            if abs(transform.a - 1) < 1e-6, abs(transform.d - 1) < 1e-6 {
                transform.tx = transform.tx.rounded()
                transform.ty = transform.ty.rounded()
            }
        }
        return image.transformed(by: transform)
    }

    // MARK: Pipeline

    /// A pipeline result and how it maps onto the full-resolution picture.
    private struct PipelineOutput {
        /// Linear extended-range working space, extent origin (0, 0).
        let image: CIImage
        /// Output pixels per full-resolution pixel.
        let renderScale: CGFloat
        let isHDR: Bool
        let isDetail: Bool

        /// The output size in full-resolution pixels.
        var fullResolutionSize: CGSize {
            CGSize(width: (image.extent.width / renderScale).rounded(),
                   height: (image.extent.height / renderScale).rounded())
        }
    }

    private func proxyOutput(for recipe: EditRecipe, longEdge: CGFloat) -> PipelineOutput? {
        guard let base = document.previewBase(for: recipe, longEdge: longEdge),
              PreviewRenderer.isUsable(base) else { return nil }
        recordProxyScale(base.renderScale)
        let image = RecipeRenderer.render(recipe, base: base.image,
                                          options: renderOptions(.interactive, base: base, recipe: recipe))
        guard PreviewRenderer.isUsable(image.extent) else { return nil }
        return PipelineOutput(image: image, renderScale: base.renderScale, isHDR: base.isHDR, isDetail: false)
    }

    private func detailOutput(for recipe: EditRecipe) -> PipelineOutput? {
        guard let base = document.fullBase(for: recipe),
              PreviewRenderer.isUsable(base) else { return nil }
        let image = RecipeRenderer.render(recipe, base: base.image,
                                          options: renderOptions(.detail, base: base, recipe: recipe))
        guard PreviewRenderer.isUsable(image.extent) else { return nil }
        return PipelineOutput(image: image, renderScale: base.renderScale, isHDR: base.isHDR, isDetail: true)
    }

    private func renderOptions(_ purpose: RenderOptions.Purpose, base: RenderBase, recipe: EditRecipe) -> RenderOptions {
        // The airlight only feeds Dehaze; skipping its one-time estimate otherwise keeps the first
        // frame fast. Preview and export read the same cached value.
        let airlight = recipe.dehaze != 0 ? document.airlight() : SIMD3<Float>(repeating: 1)
        return RenderOptions(purpose: purpose,
                             renderScale: base.renderScale,
                             fullSize: document.uprightSize,
                             rawStageApplied: base.rawStageApplied,
                             airlight: airlight)
    }

    /// "Before": the camera/original look, with the same crop and rotation so nothing jumps.
    private static func originalRecipe(keepingGeometryOf recipe: EditRecipe) -> EditRecipe {
        var original = EditRecipe()
        original.geometry = recipe.geometry
        original.keepsHDR = recipe.keepsHDR
        return original
    }

    // MARK: Main-actor updates

    /// Corrects the canvas' picture size (refit) on the main actor.
    private func sendImageSize(_ size: CGSize, to canvas: WeakCanvas) {
        Task { @MainActor in
            canvas.view?.setImageSize(size, refit: true)
        }
    }

    /// Turns the layer's EDR presentation on or off (main actor) when it changes.
    private func updatePresentedEDR(_ enabled: Bool, target: CanvasTarget) {
        if let presented = presentedEDR, presented.target == target.id, presented.enabled == enabled { return }
        presentedEDR = (target: target.id, enabled: enabled)
        let canvas = target.canvas
        Task { @MainActor in
            canvas.view?.setExtendedDynamicRange(enabled)
        }
    }

    // MARK: Shared state

    /// The canvas being drawn into. Weak: the canvas (and its layer) belong to the view hierarchy.
    private struct CanvasTarget {
        let canvas: WeakCanvas
        weak var layer: CAMetalLayer?
        let state: CanvasRenderState
        let id: UInt64
    }

    /// A weak reference to the canvas view that travels with the render queue but is only ever
    /// dereferenced on the main actor. The render queue therefore never holds a strong reference to
    /// the `UIView`, so it can never be the one that releases it (a UIView must die on the main thread).
    private final class WeakCanvas: @unchecked Sendable {
        weak var view: CanvasView?

        init(_ view: CanvasView) {
            self.view = view
        }
    }

    private func currentTarget() -> CanvasTarget? {
        lock.lock()
        defer { lock.unlock() }
        return target
    }

    /// True when a newer request is waiting (the frame being drawn is already outdated).
    private var hasPendingRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequest != nil
    }

    /// min(3072, max(2048, screen long edge)), fixed once the screen is known so the document's
    /// proxy cache is not invalidated by layout changes.
    private func resolveProxyLongEdge(state: CanvasRenderState, viewport: Viewport) -> CGFloat {
        let screenLongEdge = state.screenLongEdgePixels       // its own lock: read before taking ours
        lock.lock()
        defer { lock.unlock() }
        if let resolvedProxyLongEdge { return resolvedProxyLongEdge }
        let known = screenLongEdge.isFinite && screenLongEdge > 0
        let reference = known
            ? screenLongEdge
            : max(viewport.drawableSize.width, viewport.drawableSize.height)
        let edge = min(PreviewRenderer.maximumProxyLongEdge,
                       max(PreviewRenderer.minimumProxyLongEdge, reference.isFinite ? reference.rounded() : 0))
        if known { resolvedProxyLongEdge = edge }
        return edge
    }

    private func recordProxyScale(_ scale: CGFloat) {
        lock.lock()
        measuredProxyScale = scale
        lock.unlock()
    }

    /// Caller holds `lock` (reads only immutable document metadata).
    private func estimatedProxyScale(longEdge: CGFloat) -> CGFloat {
        let full = document.uprightSize
        let fullLongEdge = max(full.width, full.height)
        guard fullLongEdge.isFinite, fullLongEdge > 0 else { return 1 }
        return min(1, longEdge / fullLongEdge)
    }

    // MARK: Validation

    private static func isUsable(_ base: RenderBase) -> Bool {
        base.renderScale.isFinite && base.renderScale > 0 && isUsable(base.image.extent)
    }

    private static func isUsable(_ extent: CGRect) -> Bool {
        !extent.isInfinite && !extent.isNull && extent.width >= 1 && extent.height >= 1
    }

    /// True when `output` is not the picture size the canvas expects. The tolerance absorbs a proxy
    /// crop snapped to whole proxy pixels (up to about 2 proxy pixels per axis).
    private static func sizeDiffers(_ output: PipelineOutput, from size: CGSize) -> Bool {
        let rendered = output.fullResolutionSize
        let tolerance = 2 + 2 / output.renderScale
        return abs(rendered.width - size.width) > tolerance || abs(rendered.height - size.height) > tolerance
    }
}
