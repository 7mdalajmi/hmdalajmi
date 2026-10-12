import SwiftUI
import Foundation

// MARK: - Grading wheel

/// A colour-grading wheel: the angle picks the hue, the distance from the centre the saturation.
///
/// Conventions (shared with `GradeWheel`): hue 0° = red at the right-hand edge, increasing
/// clockwise; saturation 0 at the centre, 100 at the rim. The wheel is a colour space, not reading
/// order, so it is always laid out left-to-right.
///
/// Interaction:
///   * drag the puck to move it (relative, so it never jumps under the finger);
///   * press and hold the puck for 0.3 s before dragging for quarter-speed fine control;
///   * drag anywhere else on the wheel to place the puck under the finger;
///   * double-tap to neutralise hue and saturation.
/// `onEditingChanged(true/false)` brackets every change, so each gesture is one undo step.
@MainActor
struct GradingWheel: View {
    private let title: LocalizedStringKey
    @Binding private var wheel: GradeWheel
    private let onEditingChanged: (Bool) -> Void

    @State private var session: WheelDragSession?
    @State private var sessionCounter = 0
    @State private var lastTapTime: Date?
    @State private var fineTick = 0
    @State private var resetTick = 0
    @GestureState private var isTouching = false
    @Environment(\.noorHapticsEnabled) private var hapticsEnabled

    init(_ title: LocalizedStringKey, wheel: Binding<GradeWheel>,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title
        self._wheel = wheel
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let puck = WheelMath.point(hue: wheel.hue, saturation: wheel.saturation,
                                       center: center, radius: radius)
            ZStack {
                face(side: side)
                    .position(center)
                puckView
                    .position(puck)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center, radius: radius, puck: puck))
        }
        .aspectRatio(1, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .sensoryFeedback(.selection, trigger: fineTick) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .light), trigger: resetTick) { _, _ in hapticsEnabled }
        .onChange(of: isTouching) { _, touching in
            guard !touching, let id = session?.id else { return }
            // The gesture was cancelled by the system (onEnded never ran): close the edit.
            Task { @MainActor in
                if session?.id == id { finishSession() }
            }
        }
        .onDisappear { finishSession() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("Hue \(WheelMath.whole(wheel.hue)), saturation \(WheelMath.whole(wheel.saturation))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit { $0.saturation = min($0.saturation + 5, 100) }
            case .decrement: commit { $0.saturation = max($0.saturation - 5, 0) }
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text("Increase Hue")) { shiftHue(by: 10) }
        .accessibilityAction(named: Text("Decrease Hue")) { shiftHue(by: -10) }
        .accessibilityAction(named: Text("Reset")) { neutralise() }
    }

    // MARK: Drawing

    private func face(side: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(AngularGradient(gradient: Gradient(colors: ColorToolPalette.hueCircle),
                                      center: .center,
                                      startAngle: .degrees(0),
                                      endAngle: .degrees(360)))
            // Neutral grey in the middle fading to full colour at the rim (saturation = radius).
            Circle()
                .fill(RadialGradient(gradient: Gradient(colors: [Color(white: 0.5), Color(white: 0.5, opacity: 0)]),
                                     center: .center,
                                     startRadius: 0,
                                     endRadius: max(side / 2, 1)))
            Circle()
                .strokeBorder(Theme.separator, lineWidth: 1)
            Circle()
                .fill(Theme.surface1.opacity(0.8))
                .frame(width: 4, height: 4)
        }
        .frame(width: side, height: side)
    }

    private var puckView: some View {
        let isDragging = session?.began == true
        return Circle()
            .fill(ColorToolPalette.hue(wheel.hue, saturation: wheel.saturation / 100, brightness: 1))
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Theme.thumb, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .scaleEffect(isDragging ? 1.25 : 1)
            .animation(.snappy(duration: 0.15), value: isDragging)
    }

    // MARK: Gesture

    private func dragGesture(center: CGPoint, radius: CGFloat, puck: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { value in dragChanged(value, center: center, radius: radius, puck: puck) }
            .onEnded { value in dragEnded(value) }
    }

    private func dragChanged(_ value: DragGesture.Value, center: CGPoint, radius: CGFloat, puck: CGPoint) {
        guard radius > 1 else { return }
        guard var current = session else {
            // Touch down: remember where the puck was and whether the finger is on it.
            sessionCounter += 1
            let onPuck = hypot(value.startLocation.x - puck.x, value.startLocation.y - puck.y) <= WheelMath.puckReach
            session = WheelDragSession(id: sessionCounter, startTime: value.time, startPuck: puck, onPuck: onPuck)
            return
        }
        let dx = value.location.x - value.startLocation.x
        let dy = value.location.y - value.startLocation.y
        if !current.began {
            guard hypot(dx, dy) >= 3 else { return }
            current.began = true
            // Holding the puck still for 0.3 s before moving switches to fine (¼ speed) mode.
            current.fine = current.onPuck && value.time.timeIntervalSince(current.startTime) >= 0.3
            session = current
            if current.fine { fineTick += 1 }
            onEditingChanged(true)
        }
        let target: CGPoint
        if current.onPuck {
            let speed: CGFloat = current.fine ? 0.25 : 1
            target = CGPoint(x: current.startPuck.x + dx * speed, y: current.startPuck.y + dy * speed)
        } else {
            target = value.location
        }
        let picked = WheelMath.value(at: target, center: center, radius: radius)
        var updated = wheel
        updated.saturation = picked.saturation
        // At the centre the angle is meaningless: keep the previous hue.
        if picked.saturation > 0 { updated.hue = picked.hue }
        if updated != wheel { wheel = updated }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        guard let ended = session else { return }
        session = nil
        if ended.began {
            onEditingChanged(false)
            return
        }
        // A tap: two taps within 0.35 s neutralise the wheel.
        if let last = lastTapTime, value.time.timeIntervalSince(last) < 0.35 {
            lastTapTime = nil
            neutralise()
        } else {
            lastTapTime = value.time
        }
    }

    /// Closes a drag that ended without `onEnded` (system cancellation, view removed).
    private func finishSession() {
        guard let ended = session else { return }
        session = nil
        if ended.began { onEditingChanged(false) }
    }

    // MARK: Discrete changes

    /// One self-contained edit (one undo step).
    private func commit(_ change: (inout GradeWheel) -> Void) {
        var updated = wheel
        change(&updated)
        guard updated != wheel else { return }
        onEditingChanged(true)
        wheel = updated
        onEditingChanged(false)
    }

    private func shiftHue(by degrees: Double) {
        commit { w in
            var h = (w.hue + degrees).truncatingRemainder(dividingBy: 360)
            if h < 0 { h += 360 }
            w.hue = h
        }
    }

    private func neutralise() {
        guard wheel.hue != 0 || wheel.saturation != 0 else { return }
        commit { w in
            w.hue = 0
            w.saturation = 0
        }
        resetTick += 1
    }
}

// MARK: - Drag state

/// One touch on the wheel, from touch-down to lift-off.
private struct WheelDragSession {
    let id: Int
    let startTime: Date
    let startPuck: CGPoint
    let onPuck: Bool
    var began = false
    var fine = false
}

// MARK: - Maths

/// Hue/saturation ↔ position on the wheel (screen coordinates, y down, so increasing angle is clockwise).
private enum WheelMath {
    /// Touch radius around the puck (44-pt target).
    static let puckReach: CGFloat = 22

    /// Rounded whole number for VoiceOver; `Int(_:)` would trap on NaN / infinity.
    static func whole(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return Int(min(max(v, -1_000_000), 1_000_000).rounded())
    }

    static func point(hue: Double, saturation: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = hue * .pi / 180
        let distance = CGFloat(min(max(saturation, 0), 100) / 100) * radius
        return CGPoint(x: center.x + CGFloat(cos(angle)) * distance,
                       y: center.y + CGFloat(sin(angle)) * distance)
    }

    /// Whole-number hue (0..<360) and saturation (0...100) at `p`; points beyond the rim clamp to 100.
    static func value(at p: CGPoint, center: CGPoint, radius: CGFloat) -> (hue: Double, saturation: Double) {
        let dx = Double(p.x - center.x)
        let dy = Double(p.y - center.y)
        let distance = (dx * dx + dy * dy).squareRoot()
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let hue = degrees.rounded().truncatingRemainder(dividingBy: 360)
        let saturation = (min(distance / Double(max(radius, 1)), 1) * 100).rounded()
        return (hue, saturation)
    }
}
