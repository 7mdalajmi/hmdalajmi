import SwiftUI
import UIKit

/// The home page and the open game, both drawn full screen. Opening a game grows its whole page, names, numbers
/// and all, out of the middle of its card to the whole screen while the card swells and fades; going home shrinks
/// the page whole back into the card. With Reduce Motion nothing grows: the two simply cross-fade.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Phase { case home, opening, game, closing }

    // Every @State has its value here: in Xcode 27 @State is a macro, and an optional without `= nil` has none.
    @State private var phase: Phase = .home
    @State private var game: Game? = nil
    @State private var frames: [Game: CGRect] = [:]
    @State private var screen: CGSize = .zero
    @State private var insets = EdgeInsets()
    // The zoom: the page and the card move as one, each with its own fade.
    @State private var zoomed = false
    @State private var pageOpacity = 0.0
    @State private var cardOpacity = 1.0
    @State private var othersAway = false
    @State private var othersOpacity = 1.0
    @State private var flight: Task<Void, Never>? = nil

    var body: some View {
        let palette = app.settings.theme.palette(system: systemScheme)
        ZStack {
            palette.ground
            HomeView(zoom: HomeZoom(active: phase == .home ? nil : game, zoomed: zoomed, cardOpacity: cardOpacity,
                                    othersAway: othersAway, othersOpacity: othersOpacity, screen: screen, frames: frames),
                     onFrame: { g, rect in frames[g] = rect },
                     onOpen: open)
                .opacity(phase == .game ? 0 : 1)
                .allowsHitTesting(phase == .home)
                .accessibilityHidden(phase != .home)
            if let game {
                page(game, palette: palette)
            }
        }
        .coordinateSpace(.named(HomeView.space))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            screen = size
            readInsets()
        }
        .onAppear {
            readInsets()
            applyTheme()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .task {
            // The window may become key just after the first appearance.
            try? await Task.sleep(for: .milliseconds(80))
            readInsets()
            applyTheme()
            // The voice list is read once the home page has come in, not during it.
            try? await Task.sleep(for: .milliseconds(700))
            app.speaker.prepare()
        }
        .onChange(of: scenePhase) { _, now in
            // The phone lies on the table during a game: the screen stays awake while the app is open.
            UIApplication.shared.isIdleTimerDisabled = now == .active
            if now == .active {
                readInsets()
                applyTheme()
            }
        }
        .onChange(of: app.settings.theme) { _, _ in applyTheme() }
        .environment(\.palette, palette)
        .environment(\.screenInsets, insets)
        .environment(\.layoutDirection, .rightToLeft)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .tint(palette.gold)
        .animation(.easeInOut(duration: 0.3), value: palette)
    }

    // MARK: The page

    @ViewBuilder
    private func page(_ game: Game, palette: Palette) -> some View {
        let rect = frames[game] ?? fallbackFrame(game)
        let w = max(screen.width, 1), h = max(screen.height, 1)
        // The page is shrunk to fit inside its card (by height on a phone, by width on a wide iPad) and centred on it.
        let s0 = min(1, max(0.05, min(rect.height / h, rect.width / w)))
        let start = CGSize(width: rect.midX - w / 2, height: rect.midY - h / 2)
        let full = zoomed || phase == .game
        Group {
            switch game {
            case .hand: HandView(onHome: goHome)
            case .baloot: BalootView(onHome: goHome)
            }
        }
        .frame(width: w, height: h)
        .background(palette.ground)
        .clipShape(RoundedRectangle(cornerRadius: full ? 0 : 22 / s0, style: .continuous))
        .overlay {
            // 1 point on screen while the page is small, thinning away as it grows.
            RoundedRectangle(cornerRadius: full ? 0 : 22 / s0, style: .continuous)
                .strokeBorder(palette.line, lineWidth: full ? 0 : 1 / s0)
                .opacity(full ? 0 : 1)
                .allowsHitTesting(false)
        }
        .scaleEffect(full ? 1 : s0)
        .offset(full ? .zero : start)
        .opacity(pageOpacity)
        .allowsHitTesting(phase == .game)
        .accessibilityHidden(phase != .game)
        // VoiceOver's scrub (two fingers, Z) goes home from anywhere in a game, the way the chevron does.
        .accessibilityAction(.escape) { leaveGame() }
        .zIndex(5)
    }

    private func fallbackFrame(_ game: Game) -> CGRect {
        let w = max(screen.width - 40, 1), h = max((screen.height - 300) / 2, 1)
        return CGRect(x: 20, y: game == .hand ? 156 : 170 + h, width: w, height: h)
    }

    // MARK: Opening and closing

    private func open(_ g: Game) {
        guard phase == .home else { return }
        flight?.cancel()
        withTransaction(Self.still) {
            game = g
            phase = .opening
            // With Reduce Motion the page is at its full size from the start and only fades in.
            zoomed = reduceMotion
            pageOpacity = 0
            cardOpacity = 1
            othersAway = false
            othersOpacity = 1
        }
        flight = Task { @MainActor in
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pageOpacity = 1
                    cardOpacity = 0
                    othersOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(220))
            } else {
                // Let the small page be drawn on the card first, then grow it.
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
                withAnimation(.opening(0.62)) {
                    zoomed = true
                    othersAway = true
                }
                withAnimation(.easeInOut(duration: 0.15)) { pageOpacity = 1 }
                withAnimation(.easeInOut(duration: 0.2).delay(0.06)) { cardOpacity = 0 }
                withAnimation(.easeInOut(duration: 0.22)) { othersOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(650))
            }
            guard !Task.isCancelled else { return }
            phase = .game
            // The first visit to الهند starts on «مين يلعب؟».
            if g == .hand && !app.hand.started { app.hand.openSetup() }
            await announceScreen()
        }
    }

    /// Tells VoiceOver the screen changed, once SwiftUI has drawn the new one.
    private func announceScreen() async {
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func goHome() {
        guard phase == .game else { return }
        flight?.cancel()
        phase = .closing
        flight = Task { @MainActor in
            if reduceMotion {
                // The page fades out at its full size; nothing shrinks.
                withAnimation(.easeInOut(duration: 0.2)) {
                    pageOpacity = 0
                    cardOpacity = 1
                    othersOpacity = 1
                }
                try? await Task.sleep(for: .milliseconds(220))
            } else {
                withAnimation(.inOut(0.62)) {
                    zoomed = false
                    othersAway = false
                }
                withAnimation(.easeInOut(duration: 0.2).delay(0.4)) { pageOpacity = 0 }
                withAnimation(.easeInOut(duration: 0.26).delay(0.3)) { cardOpacity = 1 }
                withAnimation(.easeInOut(duration: 0.32).delay(0.26)) { othersOpacity = 1 }
                try? await Task.sleep(for: .milliseconds(680))
            }
            guard !Task.isCancelled else { return }
            withTransaction(Self.still) {
                phase = .home
                game = nil
                zoomed = false
                othersAway = false
            }
            await announceScreen()
        }
    }

    /// Leaving a game as its chevron does: the game puts away its keypad, its open questions and a win line not
    /// yet said, and the keyboard goes down before the page shrinks home.
    private func leaveGame() {
        guard phase == .game else { return }
        switch game {
        case .hand: app.hand.leave()
        case .baloot: app.baloot.leave()
        case nil: break
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        goHome()
    }

    private static var still: Transaction {
        var t = Transaction()
        t.disablesAnimations = true
        return t
    }

    /// The window's safe area (status bar, home indicator), without the keyboard.
    private func readInsets() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let i = (windows.first { $0.isKeyWindow } ?? windows.first)?.safeAreaInsets else { return }
        let side = max(i.left, i.right)
        insets = EdgeInsets(top: i.top, leading: side, bottom: i.bottom, trailing: side)
    }

    /// The theme is set on the window itself: «تلقائي» then always goes back to the phone's appearance, and the
    /// status bar, the keyboard and «مين يلعب؟» follow نوار and عاجي like the pages do.
    private func applyTheme() {
        let style: UIUserInterfaceStyle
        switch app.settings.theme {
        case .auto: style = .unspecified
        case .noir: style = .dark
        case .ivory: style = .light
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
