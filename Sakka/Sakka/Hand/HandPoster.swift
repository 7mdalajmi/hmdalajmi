import SwiftUI

/// The end of a game of الهند: the seal with the winner's name, their total in gold (or «زات» when it ended
/// with one), the others in order, how many rounds, and «لعبة جديدة» and «تعديل» by the thumb.
struct HandPoster: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.screenInsets) private var insets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onHome: () -> Void

    private var store: HandStore { app.hand }

    /// The name shrinks with its length to stay inside the seal.
    static func sealSize(_ name: String) -> CGFloat {
        switch name.count {
        case ...3: return 88
        case 4: return 76
        case 5: return 66
        case 6: return 58
        case 7: return 52
        default: return 46
        }
    }

    var body: some View {
        let on = store.intro
        let t = store.totals
        let winner = store.outcome.winner ?? store.players[0].id
        let others = store.players.filter { $0.id != winner }.sorted { (t[$0.id] ?? 0) < (t[$1.id] ?? 0) }
        // The surface (and the chevron on it) is solid at once after the growing box; otherwise it fades in.
        // With Reduce Motion the whole screen fades in as one, in 200 ms.
        let solid = on || store.fromExpand
        ZStack(alignment: .top) {
            c.surface
                .opacity(solid ? 1 : 0)
                .animation(on && !store.fromExpand && !reduceMotion ? .settle(0.32) : nil, value: on)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // Five or six players on a short screen: a smaller seal and closer rows, so nothing is pushed off.
                ViewThatFits(in: .vertical) {
                    group(compact: false, on: on, winner: winner, others: others)
                    group(compact: true, on: on, winner: winner, others: others)
                }
                // Offered all the height left after the buttons, not a share with the spacers.
                .layoutPriority(1)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Button { store.openSetup() } label: {
                        Text("لعبة جديدة")
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
        .accessibilityLabel("نهاية الهند")
    }

    private func group(compact: Bool, on: Bool, winner: String, others: [HandPlayer]) -> some View {
        let t = store.totals
        let winName = store.name(winner)
        let sealScale: CGFloat = compact ? 0.8 : 1
        return VStack(spacing: compact ? 14 : 22) {
            Seal(on: on, caption: "الفوز", name: winName, nameSize: Self.sealSize(winName))
                .scaleEffect(sealScale)
                .frame(width: 248 * sealScale, height: 248 * sealScale)
            VStack(spacing: compact ? 10 : 14) {
                Group {
                    if store.wonByZat {
                        Text("زات")
                            .font(.system(size: compact ? 34 : 40, weight: .bold))
                            .foregroundStyle(c.gold)
                            .frame(height: compact ? 48 : 56)
                    } else {
                        Text(verbatim: Digits.signed(t[winner] ?? 0))
                            .font(.numerals(compact ? 48 : 56, tabular: false))
                            .foregroundStyle(c.gold)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .entrance(on, delay: 0.8, duration: 0.45, dy: 10)
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { i, p in
                        HStack {
                            Text(verbatim: store.name(p.id))
                                .font(.amiri(compact ? 18 : 20))
                                .foregroundStyle(c.ink)
                                .lineLimit(1)
                                .lineBox(26)
                            Spacer(minLength: 8)
                            Text(verbatim: Digits.signed(t[p.id] ?? 0))
                                .font(.numerals(compact ? 22 : 26))
                                .foregroundStyle(c.inkMuted)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .frame(height: compact ? 32 : 40)
                        .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: 1) }
                        .entrance(on, delay: 0.88 + Double(i) * 0.07, duration: 0.4, dy: 8)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: store.name(p.id) + " " + Digits.signed(t[p.id] ?? 0)))
                    }
                }
                .frame(width: 232)
                .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) }
            }
            Text(verbatim: ArabicCount.rounds(store.rounds.count))
                .label(14, .medium)
                .foregroundStyle(c.inkMuted)
                .entrance(on, delay: 1.05, duration: 0.3)
        }
    }
}
