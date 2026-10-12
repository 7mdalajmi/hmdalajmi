import SwiftUI
import UIKit

// MARK: - Track style

/// How an `AdjustmentSlider` draws its track.
enum SliderTrackStyle: Equatable {
    /// 2-pt neutral track with an accent fill from the default (or the minimum) to the thumb.
    case standard
    /// 4-pt colour-axis track (temperature, tint, hue, …) with no fill. Colours run left → right.
    case gradient([Color])
}

// MARK: - Slider

/// Lightroom-style adjustment row: the label and live value on one line, the track below.
///
/// Behaviour (UX spec §2.6):
/// * **Relative drag** – the thumb never jumps to the finger and a tap on the track does nothing;
///   one track width covers the whole range.
/// * **Sticky detent** at the default value (when it lies inside the range): crossing it snaps to
///   the default and holds for 10 pt of finger travel, with an `.alignment` haptic. Starting a drag
///   *at* the default is not sticky.
/// * **Precision scrubbing** – moving the finger more than 60 pt (120 pt) away vertically halves
///   (quarters) the speed. Deltas are applied incrementally, so changing speed never jumps.
/// * **Double-tap** the label row or the track to reset to the default.
/// * One `onEditingChanged(true)` / `onEditingChanged(false)` pair per gesture (one undo step).
/// * VoiceOver: a single adjustable element with a signed, localized value and a Reset action.
///
/// The track is always laid out left-to-right: it is a position on the same tonal / colour axis as
/// the histogram, not a progress bar. The label/value row mirrors normally in Arabic.
///
/// The drag is a UIKit pan recognizer that only begins when the movement is mostly horizontal and
/// makes an enclosing scroll view wait for that decision, so vertical swipes that start on a
/// slider still scroll the panel, and precision scrubbing never scrolls it.
struct AdjustmentSlider: View {
    // MARK: Configuration

    private let title: LocalizedStringKey
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let defaultValue: Double
    private let fractionDigits: Int
    private let track: SliderTrackStyle
    private let isEnabled: Bool
    private let onEditingChanged: (Bool) -> Void

    // MARK: Environment

    @Environment(\.locale) private var locale
    /// False when an ancestor applied `.disabled(true)`. The UIKit recognizers don't see SwiftUI's
    /// `.disabled`, so it is folded into `isInteractive` explicitly.
    @Environment(\.isEnabled) private var isEnabledByAncestors
    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @Environment(\.noorEditorIsInteracting) private var editorIsInteracting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Gesture state

    @State private var isDragging = false
    /// Horizontal translation already consumed (points, relative to the gesture start).
    @State private var consumedTranslation: CGFloat = 0
    /// Unquantized value that follows the finger, so slow drags still accumulate below one step.
    @State private var dragValue: Double = 0
    @State private var isHeldAtDetent = false
    @State private var detentTravel: CGFloat = 0

    // MARK: Haptic triggers

    @State private var detentHits = 0
    @State private var edgeHits = 0
    @State private var resets = 0

    /// Fixed geometry (points).
    private enum Metrics {
        static let thumb: CGFloat = 18
        static let thumbDragging: CGFloat = 22
        static let hitBand: CGFloat = 28
        static let detentEscape: CGFloat = 10
        static let halfSpeedDrift: CGFloat = 60
        static let quarterSpeedDrift: CGFloat = 120
    }

    init(_ title: LocalizedStringKey,
         value: Binding<Double>,
         range: ClosedRange<Double>,
         defaultValue: Double = 0,
         fractionDigits: Int = 0,
         track: SliderTrackStyle = .standard,
         isEnabled: Bool = true,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.fractionDigits = min(max(fractionDigits, 0), 6)
        self.track = track
        self.isEnabled = isEnabled
        self.onEditingChanged = onEditingChanged
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            labelRow
            trackArea
        }
        .padding(.vertical, Theme.Space.xs)
        .frame(minHeight: 44)
        .opacity(rowOpacity)
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
        .disabled(!isInteractive)
        .onDisappear { finishDragIfNeeded() }
        .sensoryFeedback(.alignment, trigger: detentHits) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: edgeHits) { _, _ in hapticsEnabled }
        .sensoryFeedback(.selection, trigger: resets) { _, _ in hapticsEnabled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: formatted(value)))
        .accessibilityAdjustableAction { direction in adjust(direction) }
        .accessibilityAction(named: Text("Reset")) { reset() }
    }

    /// Label (reading-start edge) and live value (reading-end edge). Mirrors in RTL.
    private var labelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(title)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: Theme.Space.s)
            Text(verbatim: formatted(value))
                .font(.footnote.monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(isModified || isDragging ? Theme.textPrimary : Theme.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { reset() }
    }

    /// The 28-pt hit band holding the drawn track and the UIKit touch surface. Always LTR.
    private var trackArea: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            trackDrawing(width: width)
                .frame(width: width, height: proxy.size.height)
                .overlay {
                    AdjustmentSliderTouchSurface(
                        isEnabled: isInteractive,
                        onPan: { phase, translation in
                            handlePan(phase, translation: translation, width: width)
                        },
                        onDoubleTap: { reset() })
                }
        }
        .frame(height: Metrics.hitBand)
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Drawing

    @ViewBuilder
    private func trackDrawing(width: CGFloat) -> some View {
        let x = position(of: value, width: width)
        let originX = position(of: fillOrigin, width: width)
        let thumb = isDragging ? Metrics.thumbDragging : Metrics.thumb
        ZStack(alignment: .leading) {
            switch track {
            case .standard:
                Capsule()
                    .fill(Theme.trackInactive)
                    .frame(height: 2)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: abs(x - originX), height: 2)
                    .offset(x: min(x, originX))
            case .gradient(let colors):
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
            }
            if detent != nil {
                Rectangle()
                    .fill(Theme.trackTick)
                    .frame(width: 1, height: 8)
                    .offset(x: originX - 0.5)
            }
            Circle()
                .fill(Theme.thumb)
                .frame(width: thumb, height: thumb)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .offset(x: x - thumb / 2)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: isDragging)
    }

    /// Centre of the thumb for `v`, inset by half a thumb at both ends.
    private func position(of v: Double, width: CGFloat) -> CGFloat {
        let usable = max(width - Metrics.thumb, 1)
        let clamped = min(max(v.isFinite ? v : defaultValue, range.lowerBound), range.upperBound)
        let fraction = (clamped - range.lowerBound) / span
        return Metrics.thumb / 2 + CGFloat(fraction) * usable
    }

    // MARK: Derived values

    private var span: Double {
        max(range.upperBound - range.lowerBound, 1e-9)
    }

    /// Bipolar sliders (−x…+x) show an explicit "+" on positive values.
    private var isBipolar: Bool {
        range.lowerBound < 0 && range.upperBound > 0
    }

    /// The sticky value: the default, when it lies strictly inside the range.
    private var detent: Double? {
        defaultValue > range.lowerBound && defaultValue < range.upperBound ? defaultValue : nil
    }

    /// Where the accent fill starts: the detent, otherwise the minimum.
    private var fillOrigin: Double {
        detent ?? range.lowerBound
    }

    private var isModified: Bool {
        quantized(value) != quantized(defaultValue)
    }

    /// Enabled by the caller and not disabled by an ancestor.
    private var isInteractive: Bool {
        isEnabled && isEnabledByAncestors
    }

    /// Focus mode: while another control is being dragged, this row fades.
    private var isDimmed: Bool {
        editorIsInteracting && !isDragging
    }

    private var rowOpacity: Double {
        (isInteractive ? 1 : 0.4) * (isDimmed ? 0.3 : 1)
    }

    /// VoiceOver step: 0.1 for decimal parameters (Exposure, Radius), 5 for wide ranges, else 1.
    private var accessibilityStep: Double {
        if fractionDigits > 0 { return 0.1 }
        return span >= 100 ? 5 : 1
    }

    /// Clamps to the range and rounds to the displayed precision; never returns "−0".
    private func quantized(_ v: Double) -> Double {
        guard v.isFinite else { return defaultValue }
        let scale = pow(10, Double(fractionDigits))
        let clamped = min(max(v, range.lowerBound), range.upperBound)
        let rounded = min(max((clamped * scale).rounded() / scale, range.lowerBound), range.upperBound)
        return rounded == 0 ? 0 : rounded
    }

    /// Localized, signed (bipolar only) value with the slider's precision.
    private func formatted(_ v: Double) -> String {
        let style = FloatingPointFormatStyle<Double>(locale: locale)
            .precision(.fractionLength(fractionDigits))
            .sign(strategy: isBipolar ? .always(includingZero: false) : .automatic)
        return quantized(v).formatted(style)
    }

    // MARK: Interaction

    private func handlePan(_ phase: AdjustmentSliderPanPhase, translation: CGSize, width: CGFloat) {
        switch phase {
        case .began:
            guard isInteractive, !isDragging else { return }
            isDragging = true
            consumedTranslation = translation.width       // relative: ignore the recognition slop
            dragValue = value.isFinite ? value : defaultValue
            isHeldAtDetent = false
            detentTravel = 0
            onEditingChanged(true)
        case .changed:
            guard isDragging else { return }
            drag(to: translation, width: width)
        case .ended:
            finishDragIfNeeded()
        }
    }

    private func drag(to translation: CGSize, width: CGFloat) {
        let dx = translation.width - consumedTranslation
        consumedTranslation = translation.width
        guard dx != 0 else { return }

        // Precision scrubbing: the further the finger strays vertically, the finer the control.
        let drift = abs(translation.height)
        let speed: Double = drift > Metrics.quarterSpeedDrift ? 0.25 : (drift > Metrics.halfSpeedDrift ? 0.5 : 1)
        let perPoint = span / Double(max(width - Metrics.thumb, 1)) * speed

        if isHeldAtDetent, let detent {
            detentTravel += dx
            guard abs(detentTravel) > Metrics.detentEscape else { return }
            isHeldAtDetent = false
            let overshoot = detentTravel - (detentTravel > 0 ? Metrics.detentEscape : -Metrics.detentEscape)
            dragValue = min(max(detent + Double(overshoot) * perPoint, range.lowerBound), range.upperBound)
            commit(quantized(dragValue))
            return
        }

        let previous = dragValue
        var proposed = min(max(previous + Double(dx) * perPoint, range.lowerBound), range.upperBound)
        if let detent, previous != detent, (previous - detent) * (proposed - detent) <= 0 {
            proposed = detent                              // crossed the default → snap and hold
            isHeldAtDetent = true
            detentTravel = 0
            detentHits += 1
        }
        dragValue = proposed

        let newValue = quantized(proposed)
        if newValue != quantized(value), newValue == range.lowerBound || newValue == range.upperBound {
            edgeHits += 1
        }
        commit(newValue)
    }

    /// Closes the gesture's undo group. Also called on disappear so a drag cut short by a panel
    /// switch never leaves the editor stuck in "interacting".
    private func finishDragIfNeeded() {
        guard isDragging else { return }
        isDragging = false
        isHeldAtDetent = false
        detentTravel = 0
        onEditingChanged(false)
    }

    /// Writes through the binding only when the value actually changes. Never throttled: the
    /// preview renderer coalesces requests (latest wins).
    private func commit(_ newValue: Double) {
        guard newValue != value else { return }
        value = newValue
    }

    private func reset() {
        guard isInteractive, !isDragging, value != defaultValue else { return }
        onEditingChanged(true)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            value = defaultValue
        }
        onEditingChanged(false)
        resets += 1
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard isInteractive, !isDragging else { return }
        let delta: Double
        switch direction {
        case .increment: delta = accessibilityStep
        case .decrement: delta = -accessibilityStep
        @unknown default: return
        }
        let newValue = quantized(value + delta)
        guard newValue != value else { return }
        onEditingChanged(true)
        value = newValue
        onEditingChanged(false)
    }
}

// MARK: - UIKit touch surface

/// Phases reported by `AdjustmentSliderTouchSurface`.
private enum AdjustmentSliderPanPhase {
    case began, changed, ended
}

/// A transparent UIKit view over the slider track that owns the drag and the double-tap.
///
/// SwiftUI's `DragGesture` cannot decline a touch once it has started, so inside a vertical
/// `ScrollView` it either blocks scrolling or fights with it. A `UIPanGestureRecognizer` can:
/// it only begins when the movement is mostly horizontal, and it asks the enclosing scroll view's
/// pan recognizer to wait for that decision. Vertical swipes therefore scroll the panel, and once
/// a horizontal drag has begun, vertical drift (precision scrubbing) never scrolls it.
private struct AdjustmentSliderTouchSurface: UIViewRepresentable {
    var isEnabled: Bool
    var onPan: (AdjustmentSliderPanPhase, CGSize) -> Void
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        context.coordinator.pan = pan
        context.coordinator.doubleTap = doubleTap
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPan = onPan
        coordinator.onDoubleTap = onDoubleTap
        // Disabling a recognizer mid-gesture cancels it, which reports `.ended` below.
        coordinator.pan?.isEnabled = isEnabled
        coordinator.doubleTap?.isEnabled = isEnabled
    }

    /// Target and delegate of the recognizers. Main-thread only (UIKit gesture callbacks).
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPan: (AdjustmentSliderPanPhase, CGSize) -> Void = { _, _ in }
        var onDoubleTap: () -> Void = {}
        weak var pan: UIPanGestureRecognizer?
        weak var doubleTap: UITapGestureRecognizer?

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let t = recognizer.translation(in: recognizer.view)
            let translation = CGSize(width: t.x, height: t.y)
            switch recognizer.state {
            case .began:
                onPan(.began, translation)
            case .changed:
                onPan(.changed, translation)
            case .ended, .cancelled, .failed:
                onPan(.ended, translation)
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onDoubleTap()
        }

        /// Horizontal-dominance check: begin only when the finger moved more sideways than up/down.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let translation = pan.translation(in: pan.view)
            if translation.x != 0 || translation.y != 0 {
                return abs(translation.x) > abs(translation.y)
            }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        /// Makes an enclosing scroll view's pan wait until this pan has decided (and failed for a
        /// vertical swipe), so the two never race for the same touch.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan,
                  let scrollView = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scrollView.panGestureRecognizer
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        AdjustmentSlider("Exposure", value: .constant(0.35), range: -5...5, fractionDigits: 2)
        AdjustmentSlider("Contrast", value: .constant(-12), range: -100...100)
        AdjustmentSlider("Temperature", value: .constant(18), range: -100...100,
                         track: .gradient([Color(red: 0.29, green: 0.53, blue: 1), Color(red: 1, green: 0.83, blue: 0.29)]))
        AdjustmentSlider("Size", value: .constant(25), range: 0...100, defaultValue: 25, isEnabled: false)
    }
    .padding(.horizontal, Theme.Space.l)
    .background(Theme.surface1)
}
