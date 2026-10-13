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
///   * drag the puck to move it (relative, so it never jumps under the finger), in any direction;
///   * press and hold the puck for 0.3 s before dragging for quarter-speed fine control;
///   * drag anywhere else on the wheel to place the puck under the finger. While the panel can
///     scroll, a mostly vertical swipe that starts off the puck is left to the panel, so the
///     wheels never trap the scroll (`PanelDragSurface`);
///   * double-tap to neutralise hue and saturation.
/// `onEditingChanged(true/false)` brackets every change, so each gesture is one undo step.
@MainActor
struct GradingWheel: View {
    private let title: LocalizedStringKey
    @Binding private var wheel: GradeWheel
    private let onEditingChanged: (Bool) -> Void

    @State private var session: WheelDragSession?
    @State private var fineTick = 0
    @State private var resetTick = 0
    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @Environment(\.isEnabled) private var isEnabled

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
            .overlay {
                PanelDragSurface(isEnabled: isEnabled,
                                 shouldBegin: { start in GradingWheel.acceptsDrag(start, puck: puck) },
                                 onDrag: { drag in handleDrag(drag, center: center, radius: radius, puck: puck) },
                                 onDoubleTap: { neutralise() })
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .sensoryFeedback(.selection, trigger: fineTick) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .light), trigger: resetTick) { _, _ in hapticsEnabled }
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
        let isDragging = session != nil
        return Circle()
            .fill(ColorToolPalette.hue(wheel.hue, saturation: wheel.saturation / 100, brightness: 1))
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Theme.thumb, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .scaleEffect(isDragging ? 1.25 : 1)
            .animation(.snappy(duration: 0.15), value: isDragging)
    }

    // MARK: Gesture

    /// The puck can be dragged in any direction. Elsewhere a drag places the puck under the
    /// finger, except a mostly vertical swipe while the panel can scroll: that one scrolls.
    private static func acceptsDrag(_ start: PanelDragStart, puck: CGPoint) -> Bool {
        WheelMath.isOnPuck(start.location, puck: puck) || !start.panelCanScroll || start.isMostlyHorizontal
    }

    private func handleDrag(_ drag: PanelDrag, center: CGPoint, radius: CGFloat, puck: CGPoint) {
        switch drag.phase {
        case .began:
            guard session == nil, radius > 1 else { return }
            let onPuck = WheelMath.isOnPuck(drag.startLocation, puck: puck)
            // Holding the puck still for 0.3 s before moving switches to fine (¼ speed) mode.
            let started = WheelDragSession(startPuck: puck, onPuck: onPuck,
                                           fine: onPuck && drag.heldFor >= WheelMath.fineHold)
            session = started
            if started.fine { fineTick += 1 }
            onEditingChanged(true)
            move(drag, session: started, center: center, radius: radius)
        case .changed:
            guard let current = session else { return }
            move(drag, session: current, center: center, radius: radius)
        case .ended:
            finishSession()
        }
    }

    private func move(_ drag: PanelDrag, session current: WheelDragSession, center: CGPoint, radius: CGFloat) {
        guard radius > 1 else { return }
        let target: CGPoint
        if current.onPuck {
            let speed: CGFloat = current.fine ? 0.25 : 1
            target = CGPoint(x: current.startPuck.x + drag.translation.width * speed,
                             y: current.startPuck.y + drag.translation.height * speed)
        } else {
            target = drag.location
        }
        let picked = WheelMath.value(at: target, center: center, radius: radius)
        var updated = wheel
        updated.saturation = picked.saturation
        // At the centre the angle is meaningless: keep the previous hue.
        if picked.saturation > 0 { updated.hue = picked.hue }
        if updated != wheel { wheel = updated }
    }

    /// Ends the drag (lift-off, system cancellation or the view going away).
    private func finishSession() {
        guard session != nil else { return }
        session = nil
        onEditingChanged(false)
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

/// One drag on the wheel, from the start of the movement to lift-off.
private struct WheelDragSession {
    /// Puck position when the drag began.
    let startPuck: CGPoint
    /// The drag began on the puck (relative move) rather than elsewhere (puck follows the finger).
    let onPuck: Bool
    /// Quarter-speed fine control (the puck was held before moving).
    let fine: Bool
}

// MARK: - Maths

/// Hue/saturation ↔ position on the wheel (screen coordinates, y down, so increasing angle is clockwise).
private enum WheelMath {
    /// Touch radius around the puck (44-pt target).
    static let puckReach: CGFloat = 22
    /// Press-and-hold time on the puck that switches to fine control.
    static let fineHold: TimeInterval = 0.3

    static func isOnPuck(_ location: CGPoint, puck: CGPoint) -> Bool {
        hypot(location.x - puck.x, location.y - puck.y) <= puckReach
    }

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
