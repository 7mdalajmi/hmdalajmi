import SwiftUI
import Foundation

// MARK: - Crop workspace

/// Replaces the photo canvas while the Crop tool is selected.
///
/// Shows `model.cropFrameImage` (the photo after quarter turns and flips, with every other edit
/// applied, but neither straightened nor cropped) aspect-fit in the available space. The picture is
/// rotated by the straighten angle inside the frame rectangle and clipped to it — exactly the
/// engine's geometry model — and the crop rectangle is drawn over it: the outside is dimmed, a
/// rule-of-thirds grid appears while dragging (a fine grid while straightening), with corner and
/// edge handles (44-pt reach). Dragging inside the rectangle moves it.
///
/// All edits are `NormalizedRect`s (top-left origin) of the frame, kept valid with
/// `Geometry.constrained(_:frameSize:straighten:)` and the aspect lock, and written through
/// `model.binding(\EditRecipe.geometry.crop)` between `beginInteraction()` and
/// `endInteraction("Crop")`. The workspace is a physical surface, so it is always left-to-right.
/// Nothing here touches pixels: the preview image is display-only and export re-renders the original.
@MainActor
struct CropWorkspace: View {
    let model: EditorModel

    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @State private var session: CropDragSession?
    @State private var sessionCounter = 0
    @GestureState private var isTouching = false

    var body: some View {
        GeometryReader { geo in
            let layout = CropWorkspaceLayout(size: geo.size, frameSize: model.frameSize)
            ZStack {
                Theme.surround(app.settings.surround)
                if layout.isUsable {
                    picture(layout)
                    cropOverlay(layout)
                    if session?.grab != nil || model.isInteracting {
                        sizeBadge(layout)
                            .position(x: geo.size.width / 2, y: 14)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(cropGesture(layout))
        }
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: isTouching) { _, touching in
            guard !touching, let id = session?.id else { return }
            // The gesture was cancelled by the system (onEnded never ran): close the edit.
            Task { @MainActor in
                if session?.id == id { dragEnded() }
            }
        }
        .onDisappear { dragEnded() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Crop"))
        .accessibilityValue(Text(verbatim: pixelSizeText(model.recipe.geometry.crop, frameSize: model.frameSize)))
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: Text("Reset Crop")) { resetCrop() }
    }

    // MARK: Picture

    private func picture(_ layout: CropWorkspaceLayout) -> some View {
        let frame = layout.frameRect
        return pictureContent(layout)
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(.degrees(model.recipe.geometry.straighten))
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pictureContent(_ layout: CropWorkspaceLayout) -> some View {
        if let image = model.cropFrameImage, CropEditMath.aspectMatches(image, frameSize: layout.frameSize) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
        } else {
            // Not rendered yet (or still showing the previous orientation).
            ZStack {
                Theme.surface2
                ProgressView()
                    .tint(Theme.textSecondary)
            }
        }
    }

    // MARK: Overlay

    /// Dimmed outside, guides, border and handles. (Not named `overlay`, which would shadow
    /// SwiftUI's `View.overlay` overloads inside `body`.)
    private func cropOverlay(_ layout: CropWorkspaceLayout) -> some View {
        let frameRect = layout.frameRect
        let cropRect = layout.viewRect(model.recipe.geometry.crop)
        let grid: CropGridStyle
        if session?.grab != nil {
            grid = .thirds
        } else if model.isInteracting {
            grid = .fine          // the straighten ruler is being dragged
        } else {
            grid = .none
        }
        return Canvas { context, _ in
            CropOverlayRenderer.draw(in: &context, frameRect: frameRect, cropRect: cropRect, grid: grid)
        }
        .allowsHitTesting(false)
    }

    private func sizeBadge(_ layout: CropWorkspaceLayout) -> some View {
        Text(verbatim: pixelSizeText(model.recipe.geometry.crop, frameSize: layout.frameSize))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.scrim))
            .allowsHitTesting(false)
    }

    /// "4032 × 3024": the output size of the crop in full-resolution pixels.
    private func pixelSizeText(_ crop: NormalizedRect, frameSize: CGSize) -> String {
        let style = IntegerFormatStyle<Int>(locale: locale).grouping(.never)
        let w = (crop.width * Double(frameSize.width)).rounded()
        let h = (crop.height * Double(frameSize.height)).rounded()
        // `Int(_:)` traps on NaN / infinity; this text is built in `body`, so never risk it.
        guard w.isFinite, h.isFinite, abs(w) < 1e9, abs(h) < 1e9 else { return "" }
        return "\(Int(w).formatted(style)) × \(Int(h).formatted(style))"
    }

    // MARK: Gesture

    private func cropGesture(_ layout: CropWorkspaceLayout) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { value in dragChanged(value, layout: layout) }
            .onEnded { _ in dragEnded() }
    }

    private func dragChanged(_ value: DragGesture.Value, layout: CropWorkspaceLayout) {
        guard layout.isUsable else { return }
        let frameSize = layout.frameSize
        let geometry = model.recipe.geometry

        if session == nil {
            sessionCounter += 1
            // Start from a valid rectangle (a preset or an older recipe may hold an invalid one).
            let current = Geometry.constrained(geometry.crop, frameSize: frameSize, straighten: geometry.straighten)
            guard let grab = CropEditMath.grab(at: value.startLocation, cropRect: layout.viewRect(current)) else {
                session = CropDragSession(id: sessionCounter, grab: nil, start: current, ratio: nil)
                return
            }
            let ratio = geometry.aspect.ratio(frameSize: frameSize)
            var start = current
            if let ratio {
                start = CropEditMath.fitted(current, ratio: ratio, frameSize: frameSize, straighten: geometry.straighten)
            }
            session = CropDragSession(id: sessionCounter, grab: grab, start: start, ratio: ratio)
            model.beginInteraction()
        }

        guard let active = session, let grab = active.grab else { return }
        let frame = layout.frameRect
        let dx = Double(value.translation.width / frame.width)
        let dy = Double(value.translation.height / frame.height)
        let minWidth = min(Double(CropWorkspaceLayout.minimumCropSide / frame.width), 0.5)
        let minHeight = min(Double(CropWorkspaceLayout.minimumCropSide / frame.height), 0.5)

        let rect: NormalizedRect
        if grab.movesWholeRect {
            rect = CropEditMath.moved(active.start, dx: dx, dy: dy,
                                      frameSize: frameSize, straighten: geometry.straighten)
        } else {
            rect = CropEditMath.resized(active.start, grab: grab, dx: dx, dy: dy, ratio: active.ratio,
                                        minWidth: minWidth, minHeight: minHeight,
                                        frameSize: frameSize, straighten: geometry.straighten)
        }
        if rect != geometry.crop {
            model.binding(\EditRecipe.geometry.crop).wrappedValue = rect
        }
    }

    private func dragEnded() {
        guard let ended = session else { return }
        session = nil
        if ended.grab != nil { model.endInteraction(String(localized: "Crop")) }
    }

    // MARK: Actions

    /// Largest valid crop for the current aspect and angle.
    private func resetCrop() {
        let frameSize = model.frameSize
        model.apply(String(localized: "Reset Crop")) { recipe in
            let g = recipe.geometry
            recipe.geometry.crop = Geometry.maximalCrop(frameSize: frameSize, straighten: g.straighten,
                                                        aspect: g.aspect.ratio(frameSize: frameSize))
        }
    }
}

// MARK: - Layout

/// Where the frame sits in the workspace (aspect-fit, inset so the handles stay reachable).
struct CropWorkspaceLayout {
    /// Breathing room around the frame for the handles.
    static let inset: CGFloat = 24
    /// Smallest crop side on screen, so the handles never collapse onto each other.
    static let minimumCropSide: CGFloat = 48

    let frameSize: CGSize
    let frameRect: CGRect

    init(size: CGSize, frameSize: CGSize) {
        self.frameSize = frameSize
        let bounds = CGRect(origin: .zero, size: size)
            .insetBy(dx: CropWorkspaceLayout.inset, dy: CropWorkspaceLayout.inset)
        frameRect = CropEditMath.fitRect(content: frameSize, in: bounds)
    }

    var isUsable: Bool {
        frameRect.width >= 8 && frameRect.height >= 8 && frameSize.width > 0 && frameSize.height > 0
    }

    /// A frame-normalized rectangle in workspace points.
    func viewRect(_ r: NormalizedRect) -> CGRect {
        CGRect(x: frameRect.minX + CGFloat(r.x) * frameRect.width,
               y: frameRect.minY + CGFloat(r.y) * frameRect.height,
               width: CGFloat(r.width) * frameRect.width,
               height: CGFloat(r.height) * frameRect.height)
    }
}

// MARK: - Drag state

/// One touch in the workspace, from touch-down to lift-off.
private struct CropDragSession {
    let id: Int
    /// What the touch moves; nil when it started away from the crop (the touch is ignored).
    let grab: CropEditMath.Grab?
    /// The crop when the drag began (valid and, when locked, of the exact aspect).
    let start: NormalizedRect
    /// Locked pixel aspect (width / height), or nil for free-form.
    let ratio: Double?
}

private enum CropGridStyle {
    case none, thirds, fine
}

// MARK: - Drawing

private enum CropOverlayRenderer {
    static func draw(in context: inout GraphicsContext, frameRect: CGRect, cropRect: CGRect, grid: CropGridStyle) {
        guard frameRect.width > 0, frameRect.height > 0 else { return }

        // Dim everything in the frame outside the crop (even-odd: frame minus crop).
        var dim = Path()
        dim.addRect(frameRect)
        dim.addRect(cropRect)
        context.fill(dim, with: .color(Theme.scrim), style: FillStyle(eoFill: true))

        // Guides.
        let divisions: Int
        let opacity: Double
        switch grid {
        case .none: divisions = 0; opacity = 0
        case .thirds: divisions = 3; opacity = 0.5
        case .fine: divisions = 8; opacity = 0.3
        }
        if divisions > 1 {
            var lines = Path()
            for i in 1..<divisions {
                let f = CGFloat(i) / CGFloat(divisions)
                let x = cropRect.minX + f * cropRect.width
                let y = cropRect.minY + f * cropRect.height
                lines.move(to: CGPoint(x: x, y: cropRect.minY))
                lines.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                lines.move(to: CGPoint(x: cropRect.minX, y: y))
                lines.addLine(to: CGPoint(x: cropRect.maxX, y: y))
            }
            context.stroke(lines, with: .color(Theme.thumb.opacity(opacity)), lineWidth: 0.5)
        }

        // Border.
        context.stroke(Path(cropRect), with: .color(Theme.thumb.opacity(0.9)), lineWidth: 1)

        // Corner L-handles (3 × 20 pt) and edge handles, scaled down for very small crops.
        let arm = min(20, cropRect.width / 3, cropRect.height / 3)
        var handles = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: cropRect.minX, y: cropRect.minY), 1, 1),
            (CGPoint(x: cropRect.maxX, y: cropRect.minY), -1, 1),
            (CGPoint(x: cropRect.minX, y: cropRect.maxY), 1, -1),
            (CGPoint(x: cropRect.maxX, y: cropRect.maxY), -1, -1),
        ]
        for (corner, sx, sy) in corners {
            handles.move(to: CGPoint(x: corner.x, y: corner.y + sy * arm))
            handles.addLine(to: corner)
            handles.addLine(to: CGPoint(x: corner.x + sx * arm, y: corner.y))
        }
        if cropRect.width > 3 * arm {
            handles.move(to: CGPoint(x: cropRect.midX - arm / 2, y: cropRect.minY))
            handles.addLine(to: CGPoint(x: cropRect.midX + arm / 2, y: cropRect.minY))
            handles.move(to: CGPoint(x: cropRect.midX - arm / 2, y: cropRect.maxY))
            handles.addLine(to: CGPoint(x: cropRect.midX + arm / 2, y: cropRect.maxY))
        }
        if cropRect.height > 3 * arm {
            handles.move(to: CGPoint(x: cropRect.minX, y: cropRect.midY - arm / 2))
            handles.addLine(to: CGPoint(x: cropRect.minX, y: cropRect.midY + arm / 2))
            handles.move(to: CGPoint(x: cropRect.maxX, y: cropRect.midY - arm / 2))
            handles.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.midY + arm / 2))
        }
        context.stroke(handles, with: .color(Theme.thumb),
                       style: StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .miter))
    }
}

// MARK: - Crop maths

/// Pure crop maths shared by the crop workspace and the crop panel. Works in the frame's
/// normalized, top-left-origin coordinates and asks `Geometry.constrained` — the function the
/// engine relies on — whether a rectangle is valid, so the UI can never produce a crop that shows
/// empty corners after straightening.
enum CropEditMath {
    /// Which edges a drag moves. No edge means the whole rectangle moves.
    struct Grab: Equatable {
        var left = false
        var right = false
        var top = false
        var bottom = false

        var movesWholeRect: Bool { !left && !right && !top && !bottom }
        var isCorner: Bool { (left || right) && (top || bottom) }
    }

    // MARK: Hit testing

    /// What a touch at `point` grabs on a crop drawn at `cropRect`, or nil when it is too far away.
    /// The reach shrinks for small crops so the inside stays draggable.
    static func grab(at point: CGPoint, cropRect: CGRect, reach maxReach: CGFloat = 22) -> Grab? {
        let reach = min(maxReach, max(10, min(cropRect.width, cropRect.height) / 3))
        guard point.x >= cropRect.minX - reach, point.x <= cropRect.maxX + reach,
              point.y >= cropRect.minY - reach, point.y <= cropRect.maxY + reach else { return nil }
        var g = Grab()
        let dl = abs(point.x - cropRect.minX)
        let dr = abs(point.x - cropRect.maxX)
        let dt = abs(point.y - cropRect.minY)
        let db = abs(point.y - cropRect.maxY)
        if min(dl, dr) <= reach {
            if dl <= dr { g.left = true } else { g.right = true }
        }
        if min(dt, db) <= reach {
            if dt <= db { g.top = true } else { g.bottom = true }
        }
        // No edge in reach means the touch is inside the rectangle: move it.
        return g
    }

    // MARK: Validity

    static func isValid(_ r: NormalizedRect, frameSize: CGSize, straighten: Double) -> Bool {
        approximatelyEqual(Geometry.constrained(r, frameSize: frameSize, straighten: straighten), r, tolerance: 1e-9)
    }

    static func approximatelyEqual(_ a: NormalizedRect, _ b: NormalizedRect, tolerance: Double) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// Pixel aspect (width / height) of a frame-normalized rectangle.
    static func pixelAspect(_ r: NormalizedRect, frameSize: CGSize) -> Double {
        let h = r.height * Double(frameSize.height)
        guard h > 0 else { return 0 }
        return r.width * Double(frameSize.width) / h
    }

    /// True when `r` is the full frame or the largest valid crop of `ratio` at this angle.
    static func isMaximal(_ r: NormalizedRect, ratio: Double, frameSize: CGSize, straighten: Double) -> Bool {
        if r.isFull { return true }
        let maximal = Geometry.maximalCrop(frameSize: frameSize, straighten: straighten, aspect: ratio)
        return approximatelyEqual(r, maximal, tolerance: 1e-4)
    }

    /// Largest `t` in 0...1 for which `ok(t)` holds, given `ok(0)`. Valid sets here are convex, so
    /// validity along a straight path is an interval starting at 0 and bisection is exact.
    private static func maxValid(_ ok: (Double) -> Bool) -> Double {
        if ok(1) { return 1 }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            if ok(mid) { lo = mid } else { hi = mid }
        }
        return lo
    }

    // MARK: Editing

    /// `r` shrunk about its centre to exactly `ratio` (pixel width / height), then kept valid.
    static func fitted(_ r: NormalizedRect, ratio: Double, frameSize: CGSize, straighten: Double) -> NormalizedRect {
        let W = Double(max(frameSize.width, 1))
        let H = Double(max(frameSize.height, 1))
        var wp = r.width * W
        var hp = r.height * H
        guard ratio > 0, wp > 0, hp > 0 else { return r }
        if wp / hp > ratio { wp = hp * ratio } else { hp = wp / ratio }
        let w = wp / W
        let h = hp / H
        let out = NormalizedRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
        return Geometry.constrained(out, frameSize: frameSize, straighten: straighten)
    }

    /// `start` moved by (dx, dy) (normalized), sliding along whichever axis is blocked.
    static func moved(_ start: NormalizedRect, dx: Double, dy: Double,
                      frameSize: CGSize, straighten: Double) -> NormalizedRect {
        let cdx = min(max(dx, -start.x), 1 - (start.x + start.width))
        let cdy = min(max(dy, -start.y), 1 - (start.y + start.height))
        func rect(_ tx: Double, _ ty: Double) -> NormalizedRect {
            NormalizedRect(x: start.x + cdx * tx, y: start.y + cdy * ty, width: start.width, height: start.height)
        }
        func ok(_ r: NormalizedRect) -> Bool { isValid(r, frameSize: frameSize, straighten: straighten) }
        if ok(rect(1, 1)) { return rect(1, 1) }
        let tx = maxValid { ok(rect($0, 0)) }
        let ty = maxValid { ok(rect(tx, $0)) }
        return rect(tx, ty)
    }

    /// `start` resized by dragging the edges in `grab` by (dx, dy) (normalized). With a `ratio`
    /// (pixel width / height) the aspect is locked: corners scale about the opposite corner, edges
    /// keep the opposite edge and the perpendicular centre line.
    static func resized(_ start: NormalizedRect, grab: Grab, dx: Double, dy: Double, ratio: Double?,
                        minWidth: Double, minHeight: Double,
                        frameSize: CGSize, straighten: Double) -> NormalizedRect {
        func ok(_ r: NormalizedRect) -> Bool { isValid(r, frameSize: frameSize, straighten: straighten) }
        guard let ratio, ratio > 0, start.width > 0, start.height > 0 else {
            return resizedFree(start, grab: grab, dx: dx, dy: dy, minWidth: minWidth, minHeight: minHeight,
                               frameSize: frameSize, straighten: straighten)
        }
        let W = Double(max(frameSize.width, 1))
        let H = Double(max(frameSize.height, 1))
        let k = ratio * H / W          // normalized width per unit of normalized height

        if grab.isCorner {
            // Project the drag onto the diagonal from the fixed corner (in pixel-proportional space).
            let anchorX = grab.left ? start.x + start.width : start.x
            let anchorY = grab.top ? start.y + start.height : start.y
            let diagonalX = (grab.left ? -1.0 : 1.0) * start.width * W
            let diagonalY = (grab.top ? -1.0 : 1.0) * start.height * H
            let length2 = diagonalX * diagonalX + diagonalY * diagonalY
            guard length2 > 0 else { return start }
            var scale = 1 + (dx * W * diagonalX + dy * H * diagonalY) / length2
            scale = max(scale, max(minWidth / start.width, minHeight / start.height))
            func cornerRect(_ s: Double) -> NormalizedRect {
                let w = start.width * s
                let h = start.height * s
                return NormalizedRect(x: grab.left ? anchorX - w : anchorX,
                                      y: grab.top ? anchorY - h : anchorY,
                                      width: w, height: h)
            }
            // Shrinking towards the fixed corner always stays inside the valid start rectangle.
            if scale <= 1 || ok(cornerRect(scale)) { return cornerRect(scale) }
            let t = maxValid { ok(cornerRect(1 + (scale - 1) * $0)) }
            return cornerRect(1 + (scale - 1) * t)
        }

        if grab.left || grab.right {
            var w = start.width + (grab.left ? -dx : dx)
            w = max(w, max(minWidth, minHeight * k))
            func widthRect(_ newWidth: Double) -> NormalizedRect {
                let newHeight = newWidth / k
                return NormalizedRect(x: grab.left ? start.x + start.width - newWidth : start.x,
                                      y: start.midY - newHeight / 2, width: newWidth, height: newHeight)
            }
            if w <= start.width || ok(widthRect(w)) { return widthRect(w) }
            let t = maxValid { ok(widthRect(start.width + (w - start.width) * $0)) }
            return widthRect(start.width + (w - start.width) * t)
        }

        var h = start.height + (grab.top ? -dy : dy)
        h = max(h, max(minHeight, minWidth / k))
        func heightRect(_ newHeight: Double) -> NormalizedRect {
            let newWidth = newHeight * k
            return NormalizedRect(x: start.midX - newWidth / 2,
                                  y: grab.top ? start.y + start.height - newHeight : start.y,
                                  width: newWidth, height: newHeight)
        }
        if h <= start.height || ok(heightRect(h)) { return heightRect(h) }
        let t = maxValid { ok(heightRect(start.height + (h - start.height) * $0)) }
        return heightRect(start.height + (h - start.height) * t)
    }

    /// Free-form resize: each grabbed edge follows the finger; a blocked axis stops, the other slides.
    private static func resizedFree(_ start: NormalizedRect, grab: Grab, dx: Double, dy: Double,
                                    minWidth: Double, minHeight: Double,
                                    frameSize: CGSize, straighten: Double) -> NormalizedRect {
        let right0 = start.x + start.width
        let bottom0 = start.y + start.height
        var left = start.x
        var right = right0
        var top = start.y
        var bottom = bottom0
        if grab.left { left = min(max(start.x + dx, 0), right0 - minWidth) }
        if grab.right { right = max(min(right0 + dx, 1), start.x + minWidth) }
        if grab.top { top = min(max(start.y + dy, 0), bottom0 - minHeight) }
        if grab.bottom { bottom = max(min(bottom0 + dy, 1), start.y + minHeight) }
        func rect(_ tx: Double, _ ty: Double) -> NormalizedRect {
            let l = start.x + (left - start.x) * tx
            let r = right0 + (right - right0) * tx
            let t = start.y + (top - start.y) * ty
            let b = bottom0 + (bottom - bottom0) * ty
            return NormalizedRect(x: l, y: t, width: r - l, height: b - t)
        }
        func ok(_ r: NormalizedRect) -> Bool { isValid(r, frameSize: frameSize, straighten: straighten) }
        if ok(rect(1, 1)) { return rect(1, 1) }
        let tx = maxValid { ok(rect($0, 0)) }
        let ty = maxValid { ok(rect(tx, $0)) }
        return rect(tx, ty)
    }

    /// The same picture area in the other orientation: `ratio` (pixel width / height) with the area
    /// and centre of `r`, scaled to fit the frame, then kept valid.
    static func swappedOrientation(_ r: NormalizedRect, ratio: Double,
                                   frameSize: CGSize, straighten: Double) -> NormalizedRect {
        let W = Double(max(frameSize.width, 1))
        let H = Double(max(frameSize.height, 1))
        let area = r.width * W * r.height * H
        guard ratio > 0, area > 0 else { return r }
        var wp = (area * ratio).squareRoot()
        var hp = (area / ratio).squareRoot()
        let fit = min(1, W / wp, H / hp)
        wp *= fit
        hp *= fit
        let w = wp / W
        let h = hp / H
        let x = min(max(r.midX - w / 2, 0), 1 - w)
        let y = min(max(r.midY - h / 2, 0), 1 - h)
        return Geometry.constrained(NormalizedRect(x: x, y: y, width: w, height: h),
                                    frameSize: frameSize, straighten: straighten)
    }

    // MARK: Whole-frame transforms (the crop follows the picture)

    /// The crop after the frame turns 90° on screen (clockwise or counter-clockwise).
    static func rotatedQuarter(_ r: NormalizedRect, clockwise: Bool) -> NormalizedRect {
        if clockwise {
            // (x, y) -> (1 - y, x)
            return NormalizedRect(x: 1 - (r.y + r.height), y: r.x, width: r.height, height: r.width)
        } else {
            // (x, y) -> (y, 1 - x)
            return NormalizedRect(x: r.y, y: 1 - (r.x + r.width), width: r.height, height: r.width)
        }
    }

    static func mirroredHorizontally(_ r: NormalizedRect) -> NormalizedRect {
        NormalizedRect(x: 1 - (r.x + r.width), y: r.y, width: r.width, height: r.height)
    }

    static func mirroredVertically(_ r: NormalizedRect) -> NormalizedRect {
        NormalizedRect(x: r.x, y: 1 - (r.y + r.height), width: r.width, height: r.height)
    }

    // MARK: Layout helpers

    /// `content` aspect-fit and centred in `bounds` (zero when either is empty).
    static func fitRect(content: CGSize, in bounds: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, !bounds.isNull,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let w = content.width * scale
        let h = content.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    /// Whether a preview image has the frame's aspect (within 2 %), i.e. is not a stale orientation.
    static func aspectMatches(_ image: CGImage, frameSize: CGSize) -> Bool {
        guard image.width > 0, image.height > 0, frameSize.width > 0, frameSize.height > 0 else { return false }
        let imageAspect = Double(image.width) / Double(image.height)
        let frameAspect = Double(frameSize.width / frameSize.height)
        return abs(imageAspect - frameAspect) / frameAspect < 0.02
    }
}
