import SwiftUI
import Foundation

// MARK: - Straighten ruler

/// A horizontal tick ruler for the straighten angle (−45°…45°, 0.1° steps).
///
/// The ruler slides under a fixed centre mark, like a physical dial: dragging it left increases
/// the angle. The drag is relative (a touch never jumps the value), gets finer when the finger
/// strays vertically (½ speed beyond 60 pt, ¼ beyond 120 pt) and sticks at 0° with an alignment
/// haptic. Double-tap resets to 0°. It is a physical rotation direction, so it is always laid out
/// left-to-right. The value bubble shows the angle with the user's locale ("−2.3°").
///
/// The ruler does not own the value: it reports changes through `onChange` and brackets each
/// gesture with `onEditingChanged(true/false)` so the caller can record one undo step.
@MainActor
struct StraightenRuler: View {
    private let value: Double
    private let range: ClosedRange<Double>
    private let onChange: (Double) -> Void
    private let onEditingChanged: (Bool) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @State private var drag: RulerDrag?
    @State private var sessionCounter = 0
    @State private var detentTick = 0
    @State private var edgeTick = 0
    @State private var resetTick = 0
    @GestureState private var isTouching = false

    init(value: Double,
         range: ClosedRange<Double> = EditRecipe.Limits.straighten.closed,
         onChange: @escaping (Double) -> Void,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.value = value
        self.range = range
        self.onChange = onChange
        self.onEditingChanged = onEditingChanged
    }

    /// The angle on screen: the live drag value while dragging, otherwise the model's.
    private var shownValue: Double { drag?.value ?? value }

    var body: some View {
        let shown = shownValue
        let labels = RulerRenderer.labels(for: range, locale: locale)
        let currentRange = range
        VStack(spacing: 6) {
            valueBubble(shown)
            Canvas { context, size in
                RulerRenderer.draw(in: &context, size: size, value: shown, range: currentRange, labels: labels)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture(count: 2) { reset() }
        }
        .environment(\.layoutDirection, .leftToRight)
        .sensoryFeedback(.alignment, trigger: detentTick) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: edgeTick) { _, _ in hapticsEnabled }
        .sensoryFeedback(.selection, trigger: resetTick) { _, _ in hapticsEnabled }
        .onChange(of: isTouching) { _, touching in
            guard !touching, let id = drag?.id else { return }
            // The gesture was cancelled by the system (onEnded never ran): close the edit.
            Task { @MainActor in
                if drag?.id == id { dragEnded() }
            }
        }
        .onDisappear { dragEnded() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Straighten"))
        .accessibilityValue(Text(verbatim: formatted(value, width: .wide)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: RulerMetrics.accessibilityStep)
            case .decrement: step(by: -RulerMetrics.accessibilityStep)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text("Reset")) { reset() }
    }

    // MARK: Value bubble

    private func valueBubble(_ shown: Double) -> some View {
        Text(verbatim: formatted(shown, width: .narrow))
            .font(.footnote.monospacedDigit().weight(.semibold))
            .foregroundStyle(shown == 0 ? Theme.textSecondary : Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(minWidth: 56, minHeight: 24)
            .background(Capsule().fill(Theme.surface2))
    }

    /// "−2.3°" (narrow) or "minus 2.3 degrees" style (wide) in the user's locale and digits.
    private func formatted(_ degrees: Double, width: Measurement<UnitAngle>.FormatStyle.UnitWidth) -> String {
        let number = FloatingPointFormatStyle<Double>(locale: locale)
            .precision(.fractionLength(1))
            .sign(strategy: .always(includingZero: false))
        let style = Measurement<UnitAngle>.FormatStyle(width: width, locale: locale,
                                                       usage: .asProvided, numberFormatStyle: number)
        return Measurement(value: degrees, unit: UnitAngle.degrees).formatted(style)
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { gesture in dragChanged(gesture) }
            .onEnded { _ in dragEnded() }
    }

    private func dragChanged(_ gesture: DragGesture.Value) {
        guard var current = drag else {
            sessionCounter += 1
            drag = RulerDrag(id: sessionCounter, value: quantized(value), lastX: gesture.translation.width)
            onEditingChanged(true)
            return
        }
        let dx = gesture.translation.width - current.lastX
        current.lastX = gesture.translation.width

        // Precision scrubbing: the further the finger strays vertically, the finer the control.
        let dy = abs(gesture.translation.height)
        let precision: Double = dy > 120 ? 0.25 : (dy > 60 ? 0.5 : 1)
        let degreesPerPoint = precision / Double(RulerMetrics.pointsPerDegree)
        let old = current.value

        if current.heldAtDetent {
            current.detentTravel += dx
            if abs(current.detentTravel) > RulerMetrics.detentEscape {
                current.heldAtDetent = false
                let escape = RulerMetrics.detentEscape
                let overshoot = current.detentTravel - (current.detentTravel > 0 ? escape : -escape)
                current.value = quantized(-Double(overshoot) * degreesPerPoint)
            }
        } else {
            // Moving the ruler right brings smaller angles under the centre mark.
            var proposed = old - Double(dx) * degreesPerPoint
            if old != 0, old * proposed <= 0 {
                proposed = 0                      // crossed 0°: snap and hold
                current.heldAtDetent = true
                current.detentTravel = 0
                detentTick += 1
            }
            let q = quantized(proposed)
            if q != old, q == range.lowerBound || q == range.upperBound { edgeTick += 1 }
            current.value = q
        }
        drag = current
        if current.value != old { onChange(current.value) }
    }

    private func dragEnded() {
        guard drag != nil else { return }
        drag = nil
        onEditingChanged(false)
    }

    // MARK: Discrete changes

    private func step(by delta: Double) {
        let next = quantized(value + delta)
        guard next != value else { return }
        onEditingChanged(true)
        onChange(next)
        onEditingChanged(false)
    }

    private func reset() {
        guard drag == nil, value != 0 else { return }
        onEditingChanged(true)
        onChange(0)
        onEditingChanged(false)
        resetTick += 1
    }

    /// Clamped to the range and rounded to 0.1° (never "−0").
    private func quantized(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        let q = (min(max(v, range.lowerBound), range.upperBound) * 10).rounded() / 10
        return q == 0 ? 0 : q
    }
}

// MARK: - Drag state

/// One drag of the ruler.
private struct RulerDrag {
    let id: Int
    /// Working angle (the caller's value may lag one update behind).
    var value: Double
    /// Last horizontal translation seen, for incremental deltas.
    var lastX: CGFloat
    var heldAtDetent = false
    var detentTravel: CGFloat = 0
}

// MARK: - Metrics

private enum RulerMetrics {
    static let pointsPerDegree: CGFloat = 8
    /// Finger travel needed to leave the 0° detent.
    static let detentEscape: CGFloat = 10
    static let accessibilityStep = 0.5
}

// MARK: - Drawing

private enum RulerRenderer {
    /// Labelled ticks every 15°.
    static let labelEvery = 15

    /// Locale-formatted labels for the labelled ticks inside `range`.
    static func labels(for range: ClosedRange<Double>, locale: Locale) -> [Int: String] {
        let lower = Int(range.lowerBound.rounded(.up))
        let upper = Int(range.upperBound.rounded(.down))
        guard lower <= upper else { return [:] }
        var out: [Int: String] = [:]
        for degree in lower...upper where degree % labelEvery == 0 {
            out[degree] = degree.formatted(IntegerFormatStyle<Int>(locale: locale))
        }
        return out
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, value: Double,
                     range: ClosedRange<Double>, labels: [Int: String]) {
        guard size.width > 0, size.height > 0 else { return }
        let centerX = size.width / 2
        let bottom = size.height
        let lower = Int(range.lowerBound.rounded(.up))
        let upper = Int(range.upperBound.rounded(.down))
        guard lower <= upper else { return }

        for degree in lower...upper {
            let x = centerX + CGFloat(Double(degree) - value) * RulerMetrics.pointsPerDegree
            guard x >= -24, x <= size.width + 24 else { continue }
            let isLabelled = degree % labelEvery == 0
            let isMid = degree % 5 == 0
            let length: CGFloat = isLabelled ? 14 : (isMid ? 10 : 6)
            // Fade towards the ends so the centre reads first.
            let fade = 1 - min(abs(x - centerX) / max(centerX, 1), 1) * 0.75
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: bottom))
            tick.addLine(to: CGPoint(x: x, y: bottom - length))
            context.stroke(tick, with: .color(Theme.trackTick.opacity(Double(fade))),
                           lineWidth: isLabelled ? 1.5 : 1)
            if isLabelled, let label = labels[degree] {
                context.draw(Text(verbatim: label)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textTertiary.opacity(Double(fade))),
                             at: CGPoint(x: x, y: 0), anchor: .top)
            }
        }

        // The fixed centre mark (the accent marks the current value).
        let mark = Path(roundedRect: CGRect(x: centerX - 1, y: bottom - 22, width: 2, height: 22), cornerRadius: 1)
        context.fill(mark, with: .color(Theme.accent))
    }
}
