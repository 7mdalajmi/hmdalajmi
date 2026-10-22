//
//  FirstRunParts.swift
//  Laqta
//
//  The pieces the first-run chapters are built from. Everything here is made up:
//  the covers are gradients, the shots hold invented text. Nothing touches the library,
//  so the sequence runs before a single item exists.
//

import Foundation
import SwiftUI

// MARK: - Timing

/// Chapters play themselves: a list of gaps, a beat number that climbs through them.
/// Reduce Motion jumps straight to the last beat, so nothing moves and nothing is missed.
@MainActor
struct BeatPlayer {
    let gaps: [Double]

    func play(_ beat: Binding<Int>, reduceMotion: Bool, animation: Animation = .smooth(duration: 0.62)) async {
        guard !reduceMotion else {
            beat.wrappedValue = gaps.count
            return
        }
        for (index, gap) in gaps.enumerated() {
            try? await Task.sleep(for: .seconds(gap))
            guard !Task.isCancelled else { return }
            withAnimation(animation) { beat.wrappedValue = index + 1 }
        }
    }
}

extension View {
    /// The one entrance every chapter uses: up a little, and in.
    func rise(_ shown: Bool, by offset: CGFloat = 16) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : offset)
    }
}

// MARK: - Made-up media

/// Stand-in covers. They read as photographs at a glance and cost nothing to draw.
nonisolated enum DemoCover: CaseIterable {
    case sand, bronze, stone, teal, plum, amber

    var colors: [Color] {
        switch self {
        case .sand:   [Color(hex: 0x5E5348), Color(hex: 0x2A2520), Color(hex: 0x161311)]
        case .bronze: [Color(hex: 0x6D5A4A), Color(hex: 0x2E2620), Color(hex: 0x151210)]
        case .stone:  [Color(hex: 0x8A8378), Color(hex: 0x3A352E), Color(hex: 0x17150F)]
        case .teal:   [Color(hex: 0x1E5A63), Color(hex: 0x123038), Color(hex: 0x0E1618)]
        case .plum:   [Color(hex: 0x4A2F52), Color(hex: 0x26182B), Color(hex: 0x130E15)]
        case .amber:  [Color(hex: 0x6A4A2A), Color(hex: 0x31241A), Color(hex: 0x15110D)]
        }
    }

    var center: UnitPoint {
        switch self {
        case .sand:   UnitPoint(x: 0.12, y: 0.20)
        case .bronze: UnitPoint(x: 0.80, y: 0.10)
        case .stone:  UnitPoint(x: 0.30, y: 0.80)
        case .teal:   UnitPoint(x: 0.85, y: 0.25)
        case .plum:   UnitPoint(x: 0.20, y: 0.30)
        case .amber:  UnitPoint(x: 0.70, y: 0.80)
        }
    }
}

struct DemoCoverView: View {
    let cover: DemoCover

    var body: some View {
        GeometryReader { proxy in
            let colors = cover.colors
            RadialGradient(
                stops: [
                    .init(color: colors[0], location: 0),
                    .init(color: colors[1], location: 0.55),
                    .init(color: colors[2], location: 1)
                ],
                center: cover.center,
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 1.15
            )
        }
        .accessibilityHidden(true)
    }
}

/// A screenshot as the sequence pretends one looks.
struct DemoShot<Content: View>: View {
    let cover: DemoCover
    var corner: CGFloat = 16
    @ViewBuilder var content: Content

    @Environment(\.laqta) private var palette

    var body: some View {
        ZStack {
            DemoCoverView(cover: cover)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 1)
        )
    }
}

extension DemoShot where Content == EmptyView {
    init(cover: DemoCover, corner: CGFloat = 16) {
        self.init(cover: cover, corner: corner) { EmptyView() }
    }
}

/// The label along the bottom of a shot ("Screenshot · 9:41").
struct DemoShotFooter: View {
    let text: String
    @Environment(\.laqta) private var palette

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(verbatim: text)
                .laqtaFont(11.5)
                .foregroundStyle(palette.meta)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(colors: [.clear, Color(hex: 0x0A0908, alpha: 0.92)], startPoint: .top, endPoint: .bottom)
                )
        }
    }
}

/// A folder card the way Home draws one, with an invented cover.
struct DemoFolderCard: View {
    let name: String
    let detail: String
    let cover: DemoCover
    let symbol: String
    var blurCover: CGFloat = 0
    var minHeight: CGFloat = 86

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                    .laqtaDisplayFont(24)
                    .foregroundStyle(palette.ink)
                Text(verbatim: detail)
                    .laqtaFont(11.5)
                    .foregroundStyle(palette.meta)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .laqtaIconFont(15, weight: .medium)
                .foregroundStyle(palette.goldHi)
                .frame(width: 38, height: 38)
                .background(palette.badgeFill, in: Circle())
                .overlay(Circle().strokeBorder(palette.badgeBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background {
            ZStack {
                DemoCoverView(cover: cover)
                    .saturation(0.62)
                    .brightness(-0.12)
                    .blur(radius: blurCover)
                LinearGradient(
                    colors: [Color(hex: 0x121010, alpha: 0.94), Color(hex: 0x121010, alpha: 0.35)],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Small type

struct FirstRunChip: View {
    let text: String
    var systemImage: String?

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).laqtaIconFont(11, weight: .semibold)
            }
            Text(verbatim: text).laqtaFont(11.5, weight: .semibold)
        }
        .foregroundStyle(palette.meta)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.field, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
        .fixedSize()
    }
}

struct ChapterEyebrow: View {
    let text: LocalizedStringKey
    @Environment(\.laqta) private var palette

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .laqtaFont(10.5, weight: .semibold)
            .tracking(1.5)
            .foregroundStyle(palette.gold)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// The headline and line of explanation every feature chapter ends on.
struct ChapterCaption: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(spacing: 9) {
            Text(title)
                .laqtaDisplayFont(27)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .laqtaFont(13)
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26)
        .accessibilityElement(children: .combine)
    }
}

/// The badge over a video or a PDF in the "everything" chapter.
struct DemoBadge: View {
    let text: String
    let systemImage: String

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).laqtaIconFont(9.5, weight: .bold)
            Text(verbatim: text).laqtaFont(10, weight: .bold)
        }
        .foregroundStyle(palette.goldHi)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.badgeBorder, lineWidth: 1))
    }
}
