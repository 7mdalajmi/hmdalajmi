import SwiftUI

/// The two games on the home page.
enum Game: Hashable {
    case hand, baloot
}

/// How the home page looks while a game opens or closes: the tapped card swells toward the viewer and fades,
/// and the rest steps back (the title up, the other card smaller, the settings down).
struct HomeZoom {
    var active: Game?
    var zoomed = false
    var cardOpacity = 1.0
    var othersAway = false
    var othersOpacity = 1.0
    var screen: CGSize = .zero
    var frames: [Game: CGRect] = [:]
}

/// «وش نلعب؟»: الهند and البلوت as cards that show where each game stands, the shared settings, and the version.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c
    @Environment(\.screenInsets) private var insets
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var zoom: HomeZoom
    var onFrame: (Game, CGRect) -> Void
    var onOpen: (Game) -> Void

    @State private var introOn = false

    static let space = "root"
    static let cardGap: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            Text("وش نلعب؟")
                .font(.amiri(34))
                .foregroundStyle(c.gold)
                .lineBox(42)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
                .homeIntro(introOn, delay: 0)
                .stepBack(zoom, dy: -12)
            VStack(spacing: Self.cardGap) {
                card(.hand) { HandCard() }
                card(.baloot) { BalootCard() }
            }
            .padding(.top, 20)
            .frame(maxHeight: .infinity)
            .zIndex(2)
            SettingsRow()
                .padding(.top, 16)
                .homeIntro(introOn, delay: 0.25)
                .stepBack(zoom, dy: 12)
            Text(verbatim: Self.versionLine)
                .label(12, .medium)
                .foregroundStyle(c.inkMuted)
                .padding(.top, 12)
                .homeIntro(introOn, delay: 0.3)
                .stepBack(zoom, dy: 12)
        }
        .padding(.top, insets.top + 8)
        .padding(.bottom, max(insets.bottom, 16) + 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // The question, then the two games, then the settings come in one after another, once.
            if !introOn {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 60))
                introOn = true
            }
        }
    }

    /// «الإصدار 1.0 · البناء 3», from the app bundle. Only the home page shows it.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "الإصدار \(version) · البناء \(build)"
    }

    private func card<Content: View>(_ game: Game, @ViewBuilder content: () -> Content) -> some View {
        let active = zoom.active == game
        let frame = zoom.frames[game] ?? .zero
        let center = CGPoint(x: zoom.screen.width / 2, y: zoom.screen.height / 2)
        // The card grows by the same factor the page shrinks to (1 / s0, the page fitting inside the card),
        // around the same centre: the two move as one. With Reduce Motion nothing grows; the two cross-fade.
        let k = frame.height > 0 && frame.width > 0
            ? max(zoom.screen.height / frame.height, zoom.screen.width / frame.width) : 1
        let blown = active && zoom.zoomed && !reduceMotion
        return Button { onOpen(game) } label: {
            content()
                .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(c.surface))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(c.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.985, duration: 0.16))
        .frame(maxHeight: .infinity)
        .scaleEffect(blown ? k : 1)
        .offset(blown ? CGSize(width: center.x - frame.midX, height: center.y - frame.midY) : .zero)
        .opacity(active ? zoom.cardOpacity : (zoom.active == nil ? 1 : zoom.othersOpacity))
        .scaleEffect(!active && zoom.active != nil && zoom.othersAway ? 0.94 : 1)
        .zIndex(active ? 3 : 1)
        .homeIntro(introOn, delay: game == .hand ? 0.09 : 0.17)
        // Measured outside the zoom's scale and offsets, which move the drawing but never the layout frame:
        // each card's own frame, true in every phase and after a rotation during a game.
        .reportFrame(in: Self.space) { onFrame(game, $0) }
    }
}

private extension View {
    /// The home page's first entrance: up 14 points and in, one part after another.
    func homeIntro(_ on: Bool, delay: Double) -> some View {
        modifier(HomeIntro(on: on, delay: delay))
    }

    /// Steps back while a game opens: fades with the others and moves a little away.
    func stepBack(_ zoom: HomeZoom, dy: CGFloat) -> some View {
        opacity(zoom.active == nil ? 1 : zoom.othersOpacity)
            .offset(y: zoom.active != nil && zoom.othersAway ? dy : 0)
    }
}

private struct HomeIntro: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var on: Bool
    var delay: Double

    func body(content: Content) -> some View {
        content
            .animation(on && !reduceMotion ? .easeInOut(duration: 0.52).delay(delay) : nil) { $0.opacity(on ? 1 : 0) }
            .animation(on && !reduceMotion ? .settle(0.62).delay(delay) : nil) { $0.offset(y: on || reduceMotion ? 0 : 14) }
    }
}

/// الهند on the home page: every player's total, the lowest in gold, and where the game is.
struct HandCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c

    var body: some View {
        let store = app.hand
        let t = store.totals
        // On a short screen with five or six players the two-row grid does not fit: one row, smaller, instead.
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "الهند، " + store.homeStatus + "، "
            + store.players.map { store.name($0.id) + " " + Digits.signed(t[$0.id] ?? 0) }.joined(separator: "، ")))
    }

    private func content(compact: Bool) -> some View {
        let store = app.hand
        let n = store.players.count
        let t = store.totals
        let started = !store.rounds.isEmpty
        let winner = store.outcome.winner
        let low = store.players.map { t[$0.id] ?? 0 }.min()
        let columns = Array(repeating: GridItem(.flexible(), spacing: compact ? 4 : 8), count: compact ? n : (n <= 4 ? n : 3))
        let nameSize: CGFloat = compact ? 15 : (n <= 4 ? 20 : 17)
        let totalSize: CGFloat = compact ? 24 : (n <= 4 ? 40 : 30)
        return VStack(spacing: 0) {
            CardTitle(title: "الهند", subtitle: compact ? nil : "7 جولات، والأقل يفوز")
            Spacer(minLength: compact ? 4 : 10)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.players) { p in
                    let v = t[p.id] ?? 0
                    let lead = started && (winner.map { $0 == p.id } ?? (v == low))
                    VStack(spacing: 2) {
                        Text(verbatim: store.name(p.id))
                            .font(.amiri(nameSize))
                            .foregroundStyle(c.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .lineBox(nameSize * 1.3)
                        Text(verbatim: Digits.signed(v))
                            .font(.numerals(totalSize))
                            .foregroundStyle(!started ? c.inkMuted : (lead ? c.gold : c.ink))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: store.homeStatus)
                .label(13, .semibold)
                .foregroundStyle(c.inkMuted)
                .padding(.top, compact ? 6 : 12)
        }
    }
}

/// البلوت on the home page: لنا and لهم, gold past the hundred as in صكة, and the line toward 152.
struct BalootCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c

    var body: some View {
        let store = app.baloot
        let t = store.totals
        // On a short screen with large text the full card does not fit its half: smaller, without the line under the title.
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "البلوت، " + store.homeStatus + "، لنا \(t.us)، لهم \(t.them)"))
    }

    private func content(compact: Bool) -> some View {
        let store = app.baloot
        let t = store.totals
        let winner = store.outcome.winner
        return VStack(spacing: 0) {
            CardTitle(title: "البلوت", subtitle: compact ? nil : "لنا ولهم، والصكة 152")
            Spacer(minLength: compact ? 4 : 6)
            HStack(spacing: 12) {
                ForEach(Team.allCases, id: \.self) { team in
                    let v = t[team]
                    VStack(spacing: 0) {
                        Text(verbatim: team.name)
                            .font(.amiri(compact ? 17 : 20))
                            .foregroundStyle(c.gold)
                            .lineBox(compact ? 22 : 26)
                        Text(verbatim: "\(v)")
                            .font(.numerals(compact ? 40 : 54))
                            .foregroundStyle(winner != nil && winner != team ? c.inkMuted : (v > BalootRules.hundred ? c.gold : c.ink))
                            .lineBox(compact ? 38 : 51)
                            .environment(\.layoutDirection, .leftToRight)
                        Track(fill: BalootRules.trackFill(v), fillColor: v > BalootRules.hundred ? c.gold : c.inkMuted,
                              base: c.line, tick: nil, widthFraction: 0.64)
                            .padding(.top, compact ? 6 : 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: store.homeStatus)
                .label(13, .semibold)
                .foregroundStyle(c.inkMuted)
                .padding(.top, compact ? 6 : 12)
        }
    }
}

/// A card's title row: the game in Amiri gold, a chevron pointing on, and a one-line description.
struct CardTitle: View {
    @Environment(\.palette) private var c
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: title)
                    .font(.amiri(34))
                    .foregroundStyle(c.gold)
                    .lineBox(41)
                Spacer(minLength: 0)
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(c.inkMuted)
            }
            if let subtitle {
                Text(verbatim: subtitle)
                    .label(13, .medium)
                    .foregroundStyle(c.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The settings shared by both games: the theme (تلقائي, نوار, عاجي), the voice, and haptics.
struct SettingsRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var c

    var body: some View {
        let s = app.settings
        HStack(spacing: 8) {
            chip(icon: "circle.lefthalf.filled", label: s.theme.label, on: true) { s.cycleTheme() }
                .accessibilityLabel(Text(verbatim: "المظهر: " + s.theme.label))
            chip(icon: s.voice ? "speaker.wave.2" : "speaker.slash", label: s.voice ? "الصوت" : "بدون صوت", on: s.voice) {
                s.toggleVoice()
                // Off means silent now, including a line already being said.
                if !s.voice { app.speaker.stop() }
            }
            .accessibilityLabel("الإعلان بالصوت")
            .accessibilityValue(s.voice ? "شغّال" : "مطفي")
            chip(icon: s.haptics ? "iphone.radiowaves.left.and.right" : "iphone.slash", label: s.haptics ? "الاهتزاز" : "بدون اهتزاز", on: s.haptics) {
                s.toggleHaptics()
            }
            .accessibilityLabel("الاهتزاز مع التسجيل")
            .accessibilityValue(s.haptics ? "شغّال" : "مطفي")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("إعدادات التطبيق")
    }

    private func chip(icon: String, label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                Text(verbatim: label)
                    .label(13, .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? c.ink : c.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? c.lineStrong : c.line, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.2), value: on)
        }
        .buttonStyle(PressScale())
    }
}
