import SwiftUI

/// The chevron that goes back to the home page, top right (back points right in Arabic).
struct HomeButton: View {
    @Environment(\.palette) private var c
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(c.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("الرئيسية")
    }
}

/// «صكة جديدة», «لعبة جديدة»: a capsule outline, 40 high in a 44 target. «متأكد؟» turns it to the danger colour.
struct CapsuleButton: View {
    @Environment(\.palette) private var c
    var title: String
    var danger = false
    var padding: CGFloat = 12
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .label(15, .bold)
                .foregroundStyle(danger ? c.danger : c.ink)
                .padding(.horizontal, padding)
                .frame(minHeight: 40)
                .overlay(Capsule().strokeBorder(danger ? c.danger : c.lineStrong, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.2), value: danger)
        }
        .buttonStyle(.plain)
    }
}

/// The banner: a surface pill with a dot (gold, or the danger colour for a refusal) and Amiri text.
struct BannerPill: View {
    @Environment(\.palette) private var c
    var text: String
    var danger = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(danger ? c.danger : c.gold).frame(width: 8, height: 8)
            Text(verbatim: text)
                .font(.amiri(18))
                .foregroundStyle(c.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .lineBox(22)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(c.surface))
        .overlay(Capsule().strokeBorder(c.line, lineWidth: 1))
    }
}

/// A press that settles back: 0.96 for keys and buttons, 0.985 for the home cards.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.96
    var duration = 0.12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}

/// One part of a win screen coming in: from 0 opacity, a little below or to the side, on the settle curve.
/// With Reduce Motion every part fades in 200 ms with no offset and no delay.
struct Entrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var on: Bool
    var delay: Double
    var duration: Double
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        let still = on || reduceMotion
        content
            .opacity(on ? 1 : 0)
            .scaleEffect(still ? 1 : scale)
            .offset(x: still ? 0 : dx, y: still ? 0 : dy)
            .animation(on ? .settle(reduceMotion ? 0.2 : duration).delay(reduceMotion ? 0 : delay) : nil, value: on)
    }
}

extension View {
    func entrance(_ on: Bool, delay: Double, duration: Double, dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1) -> some View {
        modifier(Entrance(on: on, delay: delay, duration: duration, dx: dx, dy: dy, scale: scale))
    }
}

/// The seal of a win screen: an outer ring drawn from 12 o'clock going counter-clockwise, an inner ring,
/// and inside them a caption over the winner's name. Drawn left-to-right so the ring keeps its turn.
struct Seal: View {
    @Environment(\.palette) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var on: Bool
    var caption: String
    var name: String
    var nameSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: (on || reduceMotion) ? 1 : 0)
                .stroke(c.ink, style: StrokeStyle(lineWidth: 1.25, lineCap: .butt))
                .frame(width: 246, height: 246)
                .rotationEffect(.degrees(-90))
                .scaleEffect(x: -1, y: 1)
                .animation(on && !reduceMotion ? .inOut(0.9).delay(0.12) : nil, value: on)
            Circle()
                .stroke(c.line, lineWidth: 1)
                .frame(width: 224, height: 224)
                .entrance(on, delay: 0.6, duration: 0.4)
            VStack(spacing: 0) {
                Text(verbatim: caption)
                    .label(15, .semibold)
                    .foregroundStyle(c.inkMuted)
                    .entrance(on, delay: 0.38, duration: 0.4, dy: 6)
                Text(verbatim: name)
                    .font(.amiri(nameSize))
                    .foregroundStyle(c.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 212)
                    .lineBox(nameSize * 1.15)
                    .accessibilityAddTraits(.isHeader)
                    .entrance(on, delay: 0.46, duration: 0.55, dy: 14, scale: 0.96)
            }
        }
        .frame(width: 248, height: 248)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// The growing box: a copy of the winner's score box, surface with an ink border and its total in gold,
/// laid over the box, then grown to the whole screen while its radius goes to 0 and its content fades.
/// Like the board's, it takes the taps that land on it: nothing under it can be touched while it grows.
struct GrowingBox: View {
    @Environment(\.palette) private var c
    var stage: GrowStage
    var from: CGRect
    var to: CGRect
    var total: String
    var totalFont: Font
    /// Where the total sits against the box's middle, so the copy's number lands exactly on the box's own.
    var totalOffset: CGFloat = 0

    var body: some View {
        let full = stage == .full
        let r = full ? to : from
        RoundedRectangle(cornerRadius: full ? 0 : 16, style: .continuous)
            .fill(c.surface)
            .overlay {
                RoundedRectangle(cornerRadius: full ? 0 : 16, style: .continuous)
                    .strokeBorder(c.ink, lineWidth: 1)
                    .animation(.easeInOut(duration: 0.24)) { $0.opacity(full ? 0 : 1) }
            }
            .overlay {
                // Fitted like the box's own total (الهند's step down and safety net), so it lands on it.
                Text(verbatim: total)
                    .font(totalFont)
                    .foregroundStyle(c.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
                    .environment(\.layoutDirection, .leftToRight)
                    .offset(y: totalOffset)
                    .animation(.easeOut(duration: 0.22)) { $0.opacity(full ? 0 : 1) }
            }
            .frame(width: r.width, height: r.height)
            .contentShape(Rectangle())
            .position(x: r.midX, y: r.midY)
            .accessibilityHidden(true)
            // The frames are measured from the left; in right-to-left SwiftUI mirrors .position, so place it left-to-right.
            .environment(\.layoutDirection, .leftToRight)
    }
}

extension View {
    /// The frame of this view in a named coordinate space, reported as it changes.
    func reportFrame(in space: String, _ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(space))
        } action: { rect in
            action(rect)
        }
    }
}
