//
//  Theme.swift
//  Laqta — Shared
//
//  Noir and Ivory: the two faces of Laqta 2.0 (tokens from the approved design canvas).
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Appearance

nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case noir
    case ivory
    case system

    var id: String { rawValue }

    static var stored: AppearanceMode {
        AppearanceMode(rawValue: AppGroup.defaults.string(forKey: SettingsKey.appearance) ?? "") ?? .noir
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .noir: .dark
        case .ivory: .light
        case .system: nil
        }
    }

    #if canImport(UIKit)
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .noir: .dark
        case .ivory: .light
        case .system: .unspecified
        }
    }
    #endif
}

// MARK: - Colors

extension Color {
    nonisolated init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

nonisolated struct LaqtaPalette: Sendable, Equatable {
    var isNoir: Bool
    var bg: Color
    var bgGlow: Color
    var bgMid: Color
    var bgEnd: Color
    var ink: Color
    var ink2: Color
    var ink3: Color
    var meta: Color
    var gold: Color
    var goldHi: Color
    var goldInk: Color
    var accentFill: Color
    var hair: Color
    var line: Color
    var cardBorder: Color
    var buttonFill: Color
    var buttonBorder: Color
    var glass: Color
    var glassBorder: Color
    var sheet: Color
    var sheet2: Color
    var grabber: Color
    var field: Color
    var veil1: Color
    var veil2: Color
    var veil3: Color
    var bandTop: Color
    var badgeFill: Color
    var badgeBorder: Color
    var scrim: Color
    var viewer: Color
    var viewerTop: Color
    var viewerBottom: Color
    var switchOff: Color
    var shimmer: Color
    var ok: Color
    var hit: Color
    var bubbleMe: Color
    var bubbleMeInk: Color
    var shadow: Color
    var coverSaturation: Double
    var coverBrightness: Double

    static let noir = LaqtaPalette(
        isNoir: true,
        bg: Color(hex: 0x121010),
        bgGlow: Color(hex: 0x2B2319),
        bgMid: Color(hex: 0x171412),
        bgEnd: Color(hex: 0x121010),
        ink: Color(hex: 0xF2ECE1),
        ink2: Color(hex: 0xA39A8B),
        ink3: Color(hex: 0x857C6F),
        meta: Color(hex: 0xCFC6B6),
        gold: Color(hex: 0xD6B676),
        goldHi: Color(hex: 0xE9D3A4),
        goldInk: Color(hex: 0x16120D),
        accentFill: Color(hex: 0xE4C98F),
        hair: Color(hex: 0xD6B676, alpha: 0.22),
        line: Color(hex: 0xD6B676, alpha: 0.12),
        cardBorder: Color(hex: 0xD6B676, alpha: 0.2),
        buttonFill: Color(hex: 0xFFFFFF, alpha: 0.06),
        buttonBorder: Color(hex: 0xD6B676, alpha: 0.3),
        glass: Color(hex: 0x211D18, alpha: 0.78),
        glassBorder: Color(hex: 0xE9D3A4, alpha: 0.32),
        sheet: Color(hex: 0x1B1815),
        sheet2: Color(hex: 0x231F1B),
        grabber: Color(hex: 0xF2ECE1, alpha: 0.22),
        field: Color(hex: 0xFFFFFF, alpha: 0.05),
        veil1: Color(hex: 0x121010, alpha: 0.94),
        veil2: Color(hex: 0x121010, alpha: 0.62),
        veil3: Color(hex: 0x121010, alpha: 0.06),
        bandTop: Color(hex: 0x121010, alpha: 0.35),
        badgeFill: Color(hex: 0x121010, alpha: 0.45),
        badgeBorder: Color(hex: 0xE9D3A4, alpha: 0.4),
        scrim: Color(hex: 0x000000, alpha: 0.55),
        viewer: Color(hex: 0x000000),
        viewerTop: Color(hex: 0x000000, alpha: 0.78),
        viewerBottom: Color(hex: 0x000000, alpha: 0.82),
        switchOff: Color(hex: 0x787064, alpha: 0.38),
        shimmer: Color(hex: 0xE9D3A4, alpha: 0.16),
        ok: Color(hex: 0x8FD19E),
        hit: Color(hex: 0xE9D3A4, alpha: 0.26),
        bubbleMe: Color(hex: 0xE4C98F),
        bubbleMeInk: Color(hex: 0x16120D),
        shadow: Color(hex: 0x000000, alpha: 0.45),
        coverSaturation: 0.92,
        coverBrightness: -0.07
    )

    static let ivory = LaqtaPalette(
        isNoir: false,
        bg: Color(hex: 0xF6F1E8),
        bgGlow: Color(hex: 0xFFF4DF),
        bgMid: Color(hex: 0xF8F3EA),
        bgEnd: Color(hex: 0xF4EEE4),
        ink: Color(hex: 0x1E1A15),
        ink2: Color(hex: 0x6F665A),
        ink3: Color(hex: 0x7F766A),
        meta: Color(hex: 0x4A4238),
        gold: Color(hex: 0x7D5F2A),
        goldHi: Color(hex: 0x85652F),
        goldInk: Color(hex: 0xFFFDF8),
        accentFill: Color(hex: 0x85652F),
        hair: Color(hex: 0x8A6A32, alpha: 0.24),
        line: Color(hex: 0x8A6A32, alpha: 0.12),
        cardBorder: Color(hex: 0x8A6A32, alpha: 0.16),
        buttonFill: Color(hex: 0xFFFDF8, alpha: 0.72),
        buttonBorder: Color(hex: 0x8A6A32, alpha: 0.24),
        glass: Color(hex: 0xFFFCF6, alpha: 0.8),
        glassBorder: Color(hex: 0x8A6A32, alpha: 0.2),
        sheet: Color(hex: 0xFBF8F2),
        sheet2: Color(hex: 0xFFFFFF),
        grabber: Color(hex: 0x1E1A15, alpha: 0.18),
        field: Color(hex: 0x8A6A32, alpha: 0.06),
        veil1: Color(hex: 0xFAF6EE, alpha: 0.95),
        veil2: Color(hex: 0xFAF6EE, alpha: 0.66),
        veil3: Color(hex: 0xFAF6EE, alpha: 0.04),
        bandTop: Color(hex: 0xFAF6EE, alpha: 0.25),
        badgeFill: Color(hex: 0xFFFDF8, alpha: 0.66),
        badgeBorder: Color(hex: 0x8A6A32, alpha: 0.28),
        scrim: Color(hex: 0x281E0F, alpha: 0.26),
        viewer: Color(hex: 0xF6F1E8),
        viewerTop: Color(hex: 0xF6F1E8, alpha: 0.94),
        viewerBottom: Color(hex: 0xF6F1E8, alpha: 0.96),
        switchOff: Color(hex: 0x786850, alpha: 0.22),
        shimmer: Color(hex: 0x8A6A32, alpha: 0.13),
        ok: Color(hex: 0x2F8A4A),
        hit: Color(hex: 0x8A6A32, alpha: 0.18),
        bubbleMe: Color(hex: 0x8A6A32),
        bubbleMeInk: Color(hex: 0xFFFDF8),
        shadow: Color(hex: 0x4A381A, alpha: 0.16),
        coverSaturation: 0.92,
        coverBrightness: 0.04
    )

    static let noirIncreasedContrast = noir.increasingContrast()
    static let ivoryIncreasedContrast = ivory.increasingContrast()

    static func resolve(_ scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> LaqtaPalette {
        switch (scheme == .dark, contrast == .increased) {
        case (true, false): .noir
        case (true, true): .noirIncreasedContrast
        case (false, false): .ivory
        case (false, true): .ivoryIncreasedContrast
        }
    }

    /// Increase Contrast: stronger secondary text, edges and veils (every text color reaches 4.5:1 or more).
    func increasingContrast() -> LaqtaPalette {
        var palette = self
        if isNoir {
            palette.ink2 = Color(hex: 0xCFC6B6)
            palette.ink3 = Color(hex: 0xA39A8B)
            palette.meta = Color(hex: 0xE6DFD2)
            palette.hair = Color(hex: 0xD6B676, alpha: 0.5)
            palette.line = Color(hex: 0xD6B676, alpha: 0.36)
            palette.cardBorder = Color(hex: 0xD6B676, alpha: 0.5)
            palette.buttonFill = Color(hex: 0xFFFFFF, alpha: 0.1)
            palette.buttonBorder = Color(hex: 0xE9D3A4, alpha: 0.62)
            palette.glass = Color(hex: 0x1B1815, alpha: 0.95)
            palette.glassBorder = Color(hex: 0xE9D3A4, alpha: 0.62)
            palette.field = Color(hex: 0xFFFFFF, alpha: 0.1)
            palette.veil1 = Color(hex: 0x121010, alpha: 0.98)
            palette.veil2 = Color(hex: 0x121010, alpha: 0.86)
            palette.veil3 = Color(hex: 0x121010, alpha: 0.4)
            palette.badgeFill = Color(hex: 0x121010, alpha: 0.8)
            palette.badgeBorder = Color(hex: 0xE9D3A4, alpha: 0.7)
            palette.switchOff = Color(hex: 0x9A9184, alpha: 0.6)
            palette.viewerTop = Color(hex: 0x000000, alpha: 0.9)
            palette.viewerBottom = Color(hex: 0x000000, alpha: 0.92)
        } else {
            palette.ink2 = Color(hex: 0x4A4238)
            palette.ink3 = Color(hex: 0x6F665A)
            palette.meta = Color(hex: 0x2E2822)
            palette.gold = Color(hex: 0x5E4618)
            palette.goldHi = Color(hex: 0x6A4F1E)
            palette.accentFill = Color(hex: 0x6A4F1E)
            palette.bubbleMe = Color(hex: 0x6A4F1E)
            palette.hair = Color(hex: 0x6A4F1E, alpha: 0.5)
            palette.line = Color(hex: 0x6A4F1E, alpha: 0.32)
            palette.cardBorder = Color(hex: 0x6A4F1E, alpha: 0.42)
            palette.buttonBorder = Color(hex: 0x6A4F1E, alpha: 0.55)
            palette.glass = Color(hex: 0xFFFCF6, alpha: 0.96)
            palette.glassBorder = Color(hex: 0x6A4F1E, alpha: 0.5)
            palette.field = Color(hex: 0x6A4F1E, alpha: 0.1)
            palette.veil1 = Color(hex: 0xFAF6EE, alpha: 0.99)
            palette.veil2 = Color(hex: 0xFAF6EE, alpha: 0.9)
            palette.veil3 = Color(hex: 0xFAF6EE, alpha: 0.45)
            palette.badgeFill = Color(hex: 0xFFFDF8, alpha: 0.92)
            palette.badgeBorder = Color(hex: 0x6A4F1E, alpha: 0.55)
            palette.switchOff = Color(hex: 0x786850, alpha: 0.42)
            palette.viewerTop = Color(hex: 0xF6F1E8, alpha: 0.98)
            palette.viewerBottom = Color(hex: 0xF6F1E8, alpha: 0.99)
        }
        return palette
    }

    /// The gold gradient used by the Intelligence badge and AI icons.
    static let aiGradient = LinearGradient(
        colors: [Color(hex: 0xF1DDB0), Color(hex: 0xC9A45E)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let aiInk = Color(hex: 0x1B1610)
}

extension EnvironmentValues {
    @Entry var laqta: LaqtaPalette = .noir
}

/// Applies the chosen appearance and resolves the palette from the effective color scheme.
private struct LaqtaThemeModifier: ViewModifier {
    @AppStorage(SettingsKey.appearance, store: AppGroup.defaults) private var appearanceRaw = AppearanceMode.noir.rawValue

    func body(content: Content) -> some View {
        PaletteResolver(content: content)
            .preferredColorScheme((AppearanceMode(rawValue: appearanceRaw) ?? .noir).colorScheme)
            // Text grows through the first three accessibility sizes; beyond that the photo
            // layouts would have no room left, so bars rely on the Large Content Viewer.
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

private struct PaletteResolver<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = LaqtaPalette.resolve(scheme, contrast: contrast)
        content
            .environment(\.laqta, palette)
            .tint(palette.accentFill)
    }
}

extension View {
    /// Apply at the root of every window and sheet.
    func laqtaThemed() -> some View {
        modifier(LaqtaThemeModifier())
    }
}

// MARK: - Type

nonisolated enum LaqtaFont {
    /// Cormorant Garamond — wordmark and screen titles.
    static func display(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(bold ? "CormorantGaramond-Bold" : "CormorantGaramond-SemiBold", size: size, relativeTo: style)
    }

    /// Cormorant Garamond at an exact size (already scaled by the caller).
    static func display(fixedSize size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "CormorantGaramond-Bold" : "CormorantGaramond-SemiBold", fixedSize: size)
    }

    /// Amiri — folder names (Arabic).
    static func arabic(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Amiri-Bold", size: size, relativeTo: style)
    }

    /// Amiri at an exact size (already scaled by the caller).
    static func arabic(fixedSize size: CGFloat) -> Font {
        .custom("Amiri-Bold", fixedSize: size)
    }
}

extension LayoutDirection {
    /// `1` left-to-right, `-1` right-to-left. Raw horizontal offsets — a badge nudged
    /// in from an edge, a light sweeping across a card — are multiplied by this, so
    /// they mirror along with everything SwiftUI flips by itself.
    var sign: CGFloat { self == .rightToLeft ? -1 : 1 }
}

/// The reader's own locale, with one change: numbers and dates always use Western
/// digits (١٢٣ reads as a different number to half the people who use this app).
///
/// It used to answer `en_<region>`, which did more than pick digits: SwiftUI resolves
/// a `Text` through this locale, so the whole app was pinned to English no matter what
/// language the phone was set to, and no translation could ever show.
nonisolated enum LaqtaLocale {
    static let current: Locale = {
        var components = Locale.Components(locale: .current)
        components.numberingSystem = Locale.NumberingSystem("latn")
        return Locale(components: components)
    }()
}

// MARK: - Background

struct LaqtaBackground: View {
    @Environment(\.laqta) private var palette

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let radius = width * 1.3
            ZStack {
                palette.bgEnd
                RadialGradient(
                    stops: [
                        .init(color: palette.bgGlow, location: 0),
                        .init(color: palette.bgMid, location: 0.48),
                        .init(color: palette.bgEnd, location: 1)
                    ],
                    center: UnitPoint(x: 0.12, y: -0.08),
                    startRadius: 0,
                    endRadius: radius
                )
                .scaleEffect(x: 1, y: min(1.6, (height * 0.55) / radius), anchor: UnitPoint(x: 0.12, y: -0.08))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Folder tones (cover moods)

// FolderTone and its fifty-six moods live in FolderMoods.swift.

// MARK: - Folder symbols

nonisolated enum FolderSymbols {
    static let all: [String] = [
        "folder", "airplane", "suitcase", "building.2", "map", "mappin.and.ellipse",
        "drop", "sparkles", "bag", "cart", "tshirt", "gift",
        "fork.knife", "cup.and.saucer", "house", "car", "briefcase", "creditcard",
        "doc.text", "book", "graduationcap", "lightbulb", "heart", "star",
        "camera", "photo", "play.rectangle", "music.note", "gamecontroller", "dumbbell",
        "leaf", "moon.stars", "chart.line.uptrend.xyaxis", "wrench.and.screwdriver", "person.2", "lock"
    ]

    /// SF Symbols from v1 used the `.fill` variants; the new badges use outlines.
    static func outline(_ symbol: String) -> String {
        symbol.hasSuffix(".fill") ? String(symbol.dropLast(5)) : symbol
    }
}
