import SwiftUI
import UIKit
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
/// The drag only starts when the finger moves mostly sideways (`PanelDragSurface`), so a vertical
/// swipe that starts on the ruler scrolls the panel instead of turning the photo.
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
    @Environment(\.isEnabled) private var isEnabled
    @State private var drag: RulerDrag?
    @State private var detentTick = 0
    @State private var edgeTick = 0
    @State private var resetTick = 0

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
        }
        // The whole ruler (bubble included) is the touch target.
        .overlay {
            PanelDragSurface(isEnabled: isEnabled,
                             shouldBegin: { $0.isMostlyHorizontal },
                             onDrag: { handleDrag($0) },
                             onDoubleTap: { reset() })
        }
        .environment(\.layoutDirection, .leftToRight)
        .sensoryFeedback(.alignment, trigger: detentTick) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: edgeTick) { _, _ in hapticsEnabled }
        .sensoryFeedback(.selection, trigger: resetTick) { _, _ in hapticsEnabled }
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

    private func handleDrag(_ gesture: PanelDrag) {
        switch gesture.phase {
        case .began:
            guard drag == nil else { return }
            // Relative: the movement that started the drag does not change the angle.
            drag = RulerDrag(value: quantized(value), lastX: gesture.translation.width)
            onEditingChanged(true)
        case .changed:
            dragChanged(gesture.translation)
        case .ended:
            dragEnded()
        }
    }

    private func dragChanged(_ translation: CGSize) {
        guard var current = drag else { return }
        let dx = translation.width - current.lastX
        current.lastX = translation.width

        // Precision scrubbing: the further the finger strays vertically, the finer the control.
        let dy = abs(translation.height)
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

// MARK: - UIKit drag surface (shared by the straighten ruler and the grading wheels)

/// One update from a `PanelDragSurface`, in the surface's own coordinates (top-left origin).
struct PanelDrag {
    enum Phase {
        case began, changed, ended
    }

    var phase: Phase
    /// Where the finger went down.
    var startLocation: CGPoint
    /// Where the finger is now.
    var location: CGPoint
    /// Seconds between touch-down and the start of the drag (press-and-hold detection).
    var heldFor: TimeInterval

    /// Finger movement since touch-down.
    var translation: CGSize {
        CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y)
    }
}

/// What a `PanelDragSurface` knows when the finger starts to move, to decide whether the drag
/// belongs to the control or to the enclosing panel.
struct PanelDragStart {
    /// Where the finger went down.
    var location: CGPoint
    /// Movement so far.
    var translation: CGSize
    /// Whether the enclosing vertical scroll view (the panel) has anything to scroll.
    var panelCanScroll: Bool

    /// More sideways than up/down.
    var isMostlyHorizontal: Bool {
        abs(translation.width) > abs(translation.height)
    }
}

/// A transparent UIKit view that owns a one-finger drag (and an optional double-tap) for a control
/// that lives inside a vertical panel `ScrollView`.
///
/// SwiftUI's `DragGesture` cannot decline a touch once it has started, so inside a scroll view it
/// either blocks scrolling or fights with it. A `UIPanGestureRecognizer` can: it begins only when
/// `shouldBegin` accepts the movement, and the enclosing scroll view's pan waits for that decision.
/// Swipes the control declines therefore scroll the panel, and once a drag has begun the panel
/// never moves under the finger. Accessibility is left to the SwiftUI control underneath.
struct PanelDragSurface: UIViewRepresentable {
    var isEnabled: Bool
    /// Called when the finger starts to move; `false` leaves the touch to the panel.
    var shouldBegin: (PanelDragStart) -> Bool
    var onDrag: (PanelDrag) -> Void
    var onDoubleTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true

        let coordinator = context.coordinator
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
        coordinator.pan = pan

        let doubleTap = UITapGestureRecognizer(target: coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        coordinator.doubleTap = doubleTap

        configure(coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        configure(context.coordinator)
    }

    private func configure(_ coordinator: Coordinator) {
        coordinator.shouldBegin = shouldBegin
        coordinator.onDrag = onDrag
        coordinator.onDoubleTap = onDoubleTap
        // Disabling a recognizer mid-gesture cancels it, which reports `.ended`.
        coordinator.pan?.isEnabled = isEnabled
        coordinator.doubleTap?.isEnabled = isEnabled && onDoubleTap != nil
    }

    /// Target and delegate of the recognizers. Main-thread only (UIKit gesture callbacks).
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldBegin: (PanelDragStart) -> Bool = { _ in false }
        var onDrag: (PanelDrag) -> Void = { _ in }
        var onDoubleTap: (() -> Void)?
        weak var pan: UIPanGestureRecognizer?
        weak var doubleTap: UITapGestureRecognizer?

        /// Touch-down of the current pan (UIKit reports the translation only from recognition).
        private var touchDownLocation = CGPoint.zero
        /// `UITouch.timestamp` of the touch-down (seconds of system uptime).
        private var touchDownTime: TimeInterval = 0
        private var heldFor: TimeInterval = 0

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                heldFor = max(ProcessInfo.processInfo.systemUptime - touchDownTime, 0)
                onDrag(event(.began, at: location))
            case .changed:
                onDrag(event(.changed, at: location))
            case .ended, .cancelled, .failed:
                onDrag(event(.ended, at: location))
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onDoubleTap?()
        }

        private func event(_ phase: PanelDrag.Phase, at location: CGPoint) -> PanelDrag {
            PanelDrag(phase: phase, startLocation: touchDownLocation, location: location, heldFor: heldFor)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer === pan, gestureRecognizer.state == .possible, gestureRecognizer.numberOfTouches == 0 {
                touchDownLocation = touch.location(in: gestureRecognizer.view)
                touchDownTime = touch.timestamp
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan === self.pan else { return true }
            let location = pan.location(in: pan.view)
            var translation = CGSize(width: location.x - touchDownLocation.x,
                                     height: location.y - touchDownLocation.y)
            if translation == .zero {
                let velocity = pan.velocity(in: pan.view)
                translation = CGSize(width: velocity.x, height: velocity.y)
            }
            return shouldBegin(PanelDragStart(location: touchDownLocation,
                                              translation: translation,
                                              panelCanScroll: Coordinator.panelCanScroll(from: pan.view)))
        }

        /// Makes an enclosing scroll view's pan wait until this pan has decided (and failed for a
        /// declined swipe), so the two never race for the same touch.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan,
                  let scrollView = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scrollView.panGestureRecognizer
        }

        /// Whether the nearest vertically scrollable ancestor has content taller than itself.
        private static func panelCanScroll(from view: UIView?) -> Bool {
            var next = view?.superview
            while let current = next {
                if let scrollView = current as? UIScrollView, scrollView.isScrollEnabled {
                    let insets = scrollView.adjustedContentInset
                    let visible = scrollView.bounds.height - insets.top - insets.bottom
                    if scrollView.contentSize.height > visible + 1 { return true }
                }
                next = current.superview
            }
            return false
        }
    }
}
