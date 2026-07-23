import SwiftUI

/// SnapStitch's visual language: a "contact sheet" — screenshots treated
/// like film frames being reviewed and stitched together. Warm paper/dark
/// grain neutrals, a single safelight-amber accent, and monospaced type
/// for anything that reads as metadata (counts, indices, formats).
enum Theme {
    static let background = Color("BackgroundPrimary")
    static let panel = Color("PanelBackground")
    static let panelLine = Color("PanelLine")
    static let ink = Color("InkPrimary")
    static let inkSoft = Color("InkSecondary")
    static let inkFaint = Color("InkTertiary")
    static let screenLine = Color("ScreenLine")
    static let statusGood = Color("StatusGood")
    static let statusWarn = Color("StatusWarn")
    static let accent = Color("AccentColor")
    static let accentInk = Color("AccentInk")

    /// Uppercase, letter-spaced monospaced label — used for frame indices,
    /// section eyebrows, and format tags, echoing camera/film metadata.
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A small "NN" frame index badge, e.g. the 01–05 markers from the
/// contact-sheet design review, reused wherever a screenshot is listed.
struct FrameIndexLabel: View {
    let index: Int
    let total: Int

    var body: some View {
        Text(String(format: "%02d/%02d", index, total))
            .font(Theme.mono(10))
            .foregroundStyle(Theme.accent)
    }
}

/// Small uppercase, letter-spaced section eyebrow used above groups of
/// controls, matching the "kicker" typography from the design review.
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.inkFaint)
    }
}

extension View {
    /// Applies SnapStitch's default screen background.
    func stitchBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
