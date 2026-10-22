import SwiftUI

/// The end of a صكة, design «الإعلان»: the seal with the winner's name, the score, the hands, and two buttons
/// by the thumb. Its parts come in one after another; the voice says «الصكة لنا» as the name lands.
struct BalootPoster: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.screenInsets) private var insets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onHome: () -> Void

    private var store: BalootStore { app.baloot }

    var body: some View {
        let on = store.intro
        let t = store.totals
        let winner = store.outcome.winner ?? .us
        // The surface (and the chevron on it) is solid at once after the growing box; otherwise it fades in.
        // With Reduce Motion the whole screen fades in as one, in 200 ms.
        let solid = on || store.fromExpand
        ZStack(alignment: .top) {
            c.surface
                .opacity(solid ? 1 : 0)
                .animation(on && !store.fromExpand && !reduceMotion ? .settle(0.32) : nil, value: on)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 22) {
                    Seal(on: on, caption: "الصكة", name: winner.name, nameSize: 88)
                    // Screen geometry: the winner's total on the right, slid in from the right; the loser's from the left.
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: "\(t[winner.other])")
                            .font(.numerals(56, tabular: false))
                            .foregroundStyle(c.inkMuted)
                            .entrance(on, delay: 0.8, duration: 0.45, dx: -14)
                        Text("مقابل")
                            .label(16, .medium)
                            .foregroundStyle(c.inkMuted)
                            .entrance(on, delay: 0.86, duration: 0.3)
                        Text(verbatim: "\(t[winner])")
                            .font(.numerals(56, tabular: false))
                            .foregroundStyle(c.gold)
                            .entrance(on, delay: 0.8, duration: 0.45, dx: 14)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(t[winner]) مقابل \(t[winner.other])"))
                    Text(verbatim: ArabicCount.hands(store.hands.count))
                        .label(15, .medium)
                        .foregroundStyle(c.inkMuted)
                        .entrance(on, delay: 1.05, duration: 0.3)
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Button { store.newGame() } label: {
                        Text("صكة جديدة")
                            .label(17, .bold)
                            .foregroundStyle(c.ground)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.ink))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .entrance(on, delay: 1.12, duration: 0.45, dy: 18)
                    Button { store.reviewLast() } label: {
                        Text("تعديل")
                            .label(17, .bold)
                            .foregroundStyle(c.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.lineStrong, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .entrance(on, delay: 1.19, duration: 0.45, dy: 18)
                }
            }
            .padding(.top, insets.top + 16)
            .padding(.bottom, insets.bottom + 16)
            .padding(.horizontal, 20)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The chevron stays where the board's top bar had it, inside the same column (on iPad too).
            HStack {
                HomeButton(action: onHome).padding(.leading, -10)
                Spacer(minLength: 0)
            }
            .padding(.top, insets.top + 8)
            .padding(.horizontal, 20)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .opacity(solid ? 1 : 0)
            .animation(on && !store.fromExpand && !reduceMotion ? .settle(0.32) : nil, value: on)
        }
        .opacity(reduceMotion && !on ? 0 : 1)
        .animation(reduceMotion && on ? .easeOut(duration: 0.2) : nil, value: on)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("نهاية الصكة")
    }
}
