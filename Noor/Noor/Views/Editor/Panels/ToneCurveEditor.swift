import SwiftUI
import Foundation

// MARK: - Tone curve editor

/// Lightroom's point curve: an RGB (master) curve plus one curve per channel.
///
/// The graph is square and always left-to-right: x = input tone (shadows → highlights),
/// y = output (up = brighter). The curve is drawn with `CurveMath`, the very evaluator the engine
/// bakes into its LUT, so what is drawn is exactly what renders and exports.
///
/// Interaction:
///   * drag a point (44-pt reach); its x stays between its neighbours ± 0.01, the end points move
///     freely (black / white point);
///   * tap the graph to add a point on the curve (a straight curve stays straight; on a bent one
///     the monotone fit through the new point can reshape its neighbouring segments slightly, so
///     the tap is its own undo step);
///   * drag from empty space to add a point there and keep dragging it;
///   * drag a middle point more than 32 pt outside the graph to arm its removal (red ring,
///     "Release to delete", haptic); releasing there deletes it.
/// At most 16 points can be created. Writes go through `model.binding(\EditRecipe.toneCurve…)`
/// between `beginInteraction()` / `endInteraction("Curve")`, so each gesture is one undo step.
@MainActor
struct ToneCurveEditor: View {
    let model: EditorModel

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @State private var channel: CurveChannel = .master
    @State private var session: CurveDragSession?
    @State private var sessionCounter = 0
    @State private var selectedIndex: Int?
    @State private var pendingRemoval = false
    @State private var selectionTick = 0
    @State private var removalTick = 0
    @GestureState private var isTouching = false

    var body: some View {
        let pts = points
        let activeIndex = session?.index ?? selectedIndex
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                channelPicker
                Spacer(minLength: 8)
                resetButton(isEnabled: pts != ToneCurves.linear)
            }
            readout(points: pts, index: activeIndex)
            graph(points: pts, activeIndex: activeIndex)
        }
        .sensoryFeedback(.selection, trigger: selectionTick) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .light), trigger: removalTick) { _, _ in hapticsEnabled }
        .onChange(of: channel) { _, _ in
            selectedIndex = nil
        }
        .onChange(of: isTouching) { _, touching in
            guard !touching, let id = session?.id else { return }
            // The gesture was cancelled by the system (onEnded never ran): close the edit.
            Task { @MainActor in
                if session?.id == id { cancelSession() }
            }
        }
        .onDisappear { cancelSession() }
    }

    // MARK: Model access

    /// The selected channel's points, sanitized exactly as the engine will read them.
    private var points: [CurvePoint] {
        CurveMath.sanitize(model.recipe.toneCurve[channel])
    }

    private func write(_ pts: [CurvePoint]) {
        model.binding(\EditRecipe.toneCurve[channel]).wrappedValue = pts
    }

    private func beginEdit() {
        model.beginInteraction()
    }

    private func endEdit() {
        model.endInteraction(String(localized: "Curve"))
    }

    private var histogramBins: [Float] {
        guard let histogram = model.histogram else { return [] }
        switch channel {
        case .master: return histogram.luma
        case .red: return histogram.red
        case .green: return histogram.green
        case .blue: return histogram.blue
        }
    }

    // MARK: Header

    private var channelPicker: some View {
        HStack(spacing: 0) {
            ForEach(CurveChannel.allCases) { candidate in
                channelButton(candidate)
            }
        }
    }

    private func channelButton(_ candidate: CurveChannel) -> some View {
        let isSelected = candidate == channel
        let isEdited = !CurveMath.isLinear(model.recipe.toneCurve[candidate])
        return Button {
            channel = candidate
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(CurveStyle.color(candidate))
                        .frame(width: 20, height: 20)
                    if differentiateWithoutColor {
                        Text(verbatim: CurveStyle.letter(candidate))
                            .font(.system(size: candidate == .master ? 7 : 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.8))
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Theme.thumb : Color.clear, lineWidth: 2))
                Circle()
                    .fill(isEdited ? Theme.textSecondary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CurveStyle.title(candidate)))
        .accessibilityValue(isEdited ? Text("Edited") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func resetButton(isEnabled: Bool) -> some View {
        Button {
            resetChannel()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textTertiary)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("Reset Channel"))
    }

    // MARK: Readout ("Input 64 → Output 80" on a 0–255 scale)

    private func readout(points pts: [CurvePoint], index: Int?) -> some View {
        Group {
            if pendingRemoval {
                Text("Release to delete")
                    .foregroundStyle(Theme.danger)
            } else if let index, pts.indices.contains(index) {
                Text("Input \(CurveStyle.level(pts[index].x)) → Output \(CurveStyle.level(pts[index].y))")
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("Tap the curve to add a point")
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 16)
    }

    // MARK: Graph

    private func graph(points pts: [CurvePoint], activeIndex: Int?) -> some View {
        let samples = CurveMath.samples(pts, count: 257)
        let histogram = histogramBins
        let color = CurveStyle.color(channel)
        let removalArmed = pendingRemoval
        return GeometryReader { geo in
            let rect = CurveGraph.plotRect(in: geo.size)
            ZStack {
                Canvas { context, _ in
                    CurveGraph.draw(in: &context, rect: rect, points: pts, samples: samples,
                                    histogram: histogram, color: color,
                                    activeIndex: activeIndex, removalArmed: removalArmed)
                }
                accessibilityPoints(pts, rect: rect)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouching) { _, state, _ in state = true }
                    .onChanged { value in dragChanged(value, rect: rect) }
                    .onEnded { value in dragEnded(value, rect: rect) }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tone Curve"))
    }

    // MARK: Gestures

    private func dragChanged(_ value: DragGesture.Value, rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        var pts = points
        guard var current = session else {
            // Touch down: grab the nearest point within reach, if any.
            sessionCounter += 1
            var started = CurveDragSession(id: sessionCounter)
            if let i = CurveGraph.nearestPoint(to: value.startLocation, in: pts, rect: rect) {
                let anchor = CurveGraph.viewPoint(pts[i], in: rect)
                started.index = i
                started.grabOffset = CGSize(width: anchor.x - value.startLocation.x,
                                            height: anchor.y - value.startLocation.y)
                beginEdit()
                selectedIndex = i
                selectionTick += 1
            }
            session = started
            return
        }

        if current.index == nil {
            // Dragging from empty space inserts a point on the curve at the start x, then drags it.
            guard !current.insertionRefused,
                  CurveGraph.distance(value.location, value.startLocation) > CurveEditorMetrics.tapSlop,
                  CurveGraph.touchRect(rect).contains(value.startLocation) else { return }
            guard let i = insertPoint(atViewX: value.startLocation.x, into: &pts, rect: rect) else {
                current.insertionRefused = true
                session = current
                return
            }
            beginEdit()
            write(pts)
            let anchor = CurveGraph.viewPoint(pts[i], in: rect)
            current.index = i
            current.grabOffset = CGSize(width: anchor.x - value.startLocation.x,
                                        height: anchor.y - value.startLocation.y)
            session = current
            selectedIndex = i
            selectionTick += 1
        }

        guard let i = current.index, pts.indices.contains(i) else { return }

        // A middle point dragged far outside the graph is armed for removal.
        let isEndPoint = i == 0 || i == pts.count - 1
        let reach = CurveEditorMetrics.removalDistance
        let isOutside = !rect.insetBy(dx: -reach, dy: -reach).contains(value.location)
        let arm = !isEndPoint && isOutside
        if arm != pendingRemoval {
            pendingRemoval = arm
            removalTick += 1
        }
        if arm { return }

        let target = CGPoint(x: value.location.x + current.grabOffset.width,
                             y: value.location.y + current.grabOffset.height)
        var moved = CurveGraph.curvePoint(at: target, in: rect)
        let gap = CurveEditorMetrics.minGap
        let lower = i > 0 ? pts[i - 1].x + gap : 0
        let upper = i < pts.count - 1 ? pts[i + 1].x - gap : 1
        moved.x = lower <= upper ? min(max(moved.x, lower), upper) : pts[i].x
        guard moved != pts[i] else { return }
        pts[i] = moved
        write(pts)
    }

    private func dragEnded(_ value: DragGesture.Value, rect: CGRect) {
        guard let ended = session else { return }
        let removing = pendingRemoval
        session = nil
        pendingRemoval = false

        if let i = ended.index {
            var pts = points
            if removing, i > 0, i < pts.count - 1 {
                pts.remove(at: i)
                write(pts)
                selectedIndex = nil
            }
            endEdit()
        } else if CurveGraph.distance(value.location, value.startLocation) <= CurveEditorMetrics.tapSlop,
                  CurveGraph.touchRect(rect).contains(value.location) {
            // A tap adds a point on the curve.
            var pts = points
            if let i = insertPoint(atViewX: value.location.x, into: &pts, rect: rect) {
                beginEdit()
                write(pts)
                endEdit()
                selectedIndex = i
                selectionTick += 1
            }
        }
    }

    /// Closes a drag that ended without `onEnded` (system cancellation, view removed). Keeps the edit.
    private func cancelSession() {
        guard let ended = session else { return }
        session = nil
        pendingRemoval = false
        if ended.index != nil { endEdit() }
    }

    /// Inserts a point on the current curve at view x; nil when the curve is full or too close to a point.
    private func insertPoint(atViewX viewX: CGFloat, into pts: inout [CurvePoint], rect: CGRect) -> Int? {
        guard pts.count < CurveEditorMetrics.maxEditablePoints, rect.width > 0 else { return nil }
        let x = min(max(Double((viewX - rect.minX) / rect.width), 0), 1)
        guard pts.allSatisfy({ abs($0.x - x) >= CurveEditorMetrics.minGap }) else { return nil }
        let index = pts.firstIndex(where: { $0.x > x }) ?? pts.count
        let y = CurveMath.evaluate(pts, at: x)
        pts.insert(CurvePoint(x: x, y: y), at: index)
        return index
    }

    // MARK: Actions

    private func resetChannel() {
        let target = channel
        model.apply(String(localized: "Reset Curve")) { $0.toneCurve[target] = ToneCurves.linear }
        selectedIndex = nil
    }

    /// VoiceOver: output ± 1 %.
    private func nudgePoint(_ index: Int, _ direction: AccessibilityAdjustmentDirection) {
        var pts = points
        guard pts.indices.contains(index) else { return }
        let delta: Double
        switch direction {
        case .increment: delta = 0.01
        case .decrement: delta = -0.01
        @unknown default: return
        }
        let y = min(max(pts[index].y + delta, 0), 1)
        guard y != pts[index].y else { return }
        pts[index].y = y
        let target = channel
        model.apply(String(localized: "Curve")) { $0.toneCurve[target] = pts }
        selectedIndex = index
    }

    private func deletePoint(_ index: Int) {
        var pts = points
        guard index > 0, index < pts.count - 1 else { return }
        pts.remove(at: index)
        let target = channel
        model.apply(String(localized: "Curve")) { $0.toneCurve[target] = pts }
        selectedIndex = nil
    }

    // MARK: Accessibility (one adjustable element per point)

    private func accessibilityPoints(_ pts: [CurvePoint], rect: CGRect) -> some View {
        ForEach(Array(pts.enumerated()), id: \.offset) { index, point in
            // The element is built on the 44-pt square *before* `.position`, so VoiceOver's frame
            // is the point itself, not the whole graph that `.position` expands to.
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityElement()
                .accessibilityLabel(Text("Point \(index + 1)"))
                .accessibilityValue(Text("Input \(CurveStyle.level(point.x)), output \(CurveStyle.level(point.y))"))
                .accessibilityAdjustableAction { direction in nudgePoint(index, direction) }
                .accessibilityAction(named: Text("Delete Point")) { deletePoint(index) }
                .position(CurveGraph.viewPoint(point, in: rect))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Drag state

/// One touch on the graph, from touch-down to lift-off.
private struct CurveDragSession {
    let id: Int
    /// The point being dragged (nil until a point is grabbed or inserted).
    var index: Int?
    /// Point position minus finger position, so a grabbed point does not jump under the finger.
    var grabOffset: CGSize = .zero
    /// The drag started in empty space but no point could be inserted there.
    var insertionRefused = false
}

// MARK: - Metrics

private enum CurveEditorMetrics {
    /// Most points the editor creates (imported curves may hold more; they stay editable).
    static let maxEditablePoints = 16
    /// Closest two points may be dragged in x.
    static let minGap = 0.01
    /// Touch reach around a point (44-pt target).
    static let hitRadius: CGFloat = 22
    /// How far outside the graph a point must be dragged to arm its removal.
    static let removalDistance: CGFloat = 32
    /// Movement below which a touch counts as a tap.
    static let tapSlop: CGFloat = 6
}

// MARK: - Styling

private enum CurveStyle {
    static func color(_ channel: CurveChannel) -> Color {
        switch channel {
        case .master: return Theme.textPrimary
        case .red: return Theme.histRed
        case .green: return Theme.histGreen
        case .blue: return Theme.histBlue
        }
    }

    static func title(_ channel: CurveChannel) -> LocalizedStringKey {
        switch channel {
        case .master: return "RGB"
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        }
    }

    /// Letters shown on the channel dots when "Differentiate Without Color" is on.
    static func letter(_ channel: CurveChannel) -> String {
        switch channel {
        case .master: return "RGB"
        case .red: return "R"
        case .green: return "G"
        case .blue: return "B"
        }
    }

    /// 0…1 → 0…255 tone level for the readout.
    static func level(_ v: Double) -> Int {
        Int((min(max(v, 0), 1) * 255).rounded())
    }
}

// MARK: - Graph geometry and drawing

private enum CurveGraph {
    /// Room around the plot so end points and their rings are not clipped.
    static let inset: CGFloat = 10

    /// The square plot area, centred in `size`.
    static func plotRect(in size: CGSize) -> CGRect {
        let side = max(min(size.width, size.height) - 2 * inset, 0)
        return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    /// Where taps and new-point drags are accepted (the plot plus its margin).
    static func touchRect(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -inset, dy: -inset)
    }

    static func viewPoint(_ p: CurvePoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(p.x) * rect.width,
                y: rect.maxY - CGFloat(p.y) * rect.height)
    }

    static func curvePoint(at v: CGPoint, in rect: CGRect) -> CurvePoint {
        guard rect.width > 0, rect.height > 0 else { return CurvePoint(x: 0, y: 0) }
        return CurvePoint(x: min(max(Double((v.x - rect.minX) / rect.width), 0), 1),
                          y: min(max(Double((rect.maxY - v.y) / rect.height), 0), 1))
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Index of the point closest to `location` within the touch reach.
    static func nearestPoint(to location: CGPoint, in pts: [CurvePoint], rect: CGRect) -> Int? {
        var best: Int?
        var bestDistance = CurveEditorMetrics.hitRadius
        for (i, p) in pts.enumerated() {
            let d = distance(viewPoint(p, in: rect), location)
            if d <= bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    static func draw(in context: inout GraphicsContext, rect: CGRect, points: [CurvePoint], samples: [Float],
                     histogram: [Float], color: Color, activeIndex: Int?, removalArmed: Bool) {
        guard rect.width > 0, rect.height > 0 else { return }

        // Background and 4 × 4 grid.
        context.fill(Path(rect), with: .color(Theme.canvas))
        var grid = Path()
        for q in 1...3 {
            let f = CGFloat(q) / 4
            grid.move(to: CGPoint(x: rect.minX + f * rect.width, y: rect.minY))
            grid.addLine(to: CGPoint(x: rect.minX + f * rect.width, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + f * rect.height))
            grid.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f * rect.height))
        }
        context.stroke(grid, with: .color(Theme.separator), lineWidth: 1)
        context.stroke(Path(rect), with: .color(Theme.separator), lineWidth: 1)

        // Faint histogram of the channel behind the curve.
        if histogram.count > 1 {
            var area = Path()
            area.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            let last = CGFloat(histogram.count - 1)
            for (i, bin) in histogram.enumerated() {
                let x = rect.minX + CGFloat(i) / last * rect.width
                let h = CGFloat(min(max(bin, 0), 1)) * rect.height * 0.9
                area.addLine(to: CGPoint(x: x, y: rect.maxY - h))
            }
            area.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            area.closeSubpath()
            context.fill(area, with: .color(color.opacity(0.14)))
        }

        // Dashed identity diagonal.
        var diagonal = Path()
        diagonal.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        diagonal.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.stroke(diagonal, with: .color(Theme.textTertiary.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        // The curve, sampled with CurveMath (the engine's evaluator).
        if samples.count > 1 {
            var curve = Path()
            let last = CGFloat(samples.count - 1)
            for (i, v) in samples.enumerated() {
                let pt = CGPoint(x: rect.minX + CGFloat(i) / last * rect.width,
                                 y: rect.maxY - CGFloat(v) * rect.height)
                if i == 0 { curve.move(to: pt) } else { curve.addLine(to: pt) }
            }
            context.stroke(curve, with: .color(color),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        // Control points.
        for (i, p) in points.enumerated() {
            let v = viewPoint(p, in: rect)
            let isActive = i == activeIndex
            let d: CGFloat = isActive ? 14 : 10
            let dot = Path(ellipseIn: CGRect(x: v.x - d / 2, y: v.y - d / 2, width: d, height: d))
            if isActive && removalArmed {
                context.stroke(dot, with: .color(Theme.danger), lineWidth: 2)
            } else {
                context.fill(dot, with: .color(Theme.thumb))
                context.stroke(dot, with: .color(Theme.canvas), lineWidth: 1.5)
            }
        }
    }
}
