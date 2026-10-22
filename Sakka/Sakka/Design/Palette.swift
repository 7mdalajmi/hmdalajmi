import SwiftUI

/// نوار (dark) and عاجي (light): the hexes of صكة's Design System, shared by the home page and both games.
nonisolated struct Palette: Equatable, Sendable {
    var ground: Color
    var surface: Color
    var ink: Color
    var inkMuted: Color
    var line: Color
    var lineStrong: Color
    var gold: Color
    var danger: Color
    var isDark: Bool

    static let noir = Palette(
        ground: Color(hex: 0x0F0E0C), surface: Color(hex: 0x1B1A17), ink: Color(hex: 0xF3EEE4),
        inkMuted: Color(hex: 0xA39D92), line: Color(hex: 0x2E2C28), lineStrong: Color(hex: 0x67635A),
        gold: Color(hex: 0xD6B06A), danger: Color(hex: 0xE07A6A), isDark: true)

    static let ivory = Palette(
        ground: Color(hex: 0xF6F1E7), surface: Color(hex: 0xFFFDF8), ink: Color(hex: 0x1B1915),
        inkMuted: Color(hex: 0x6B655B), line: Color(hex: 0xE3DCCF), lineStrong: Color(hex: 0x8F877A),
        gold: Color(hex: 0x876324), danger: Color(hex: 0xB03A2A), isDark: false)
}

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The theme set on the home page: تلقائي follows the phone, نوار and عاجي are fixed.
nonisolated enum ThemeChoice: String, Codable, CaseIterable, Sendable {
    case auto, noir, ivory

    var label: String {
        switch self {
        case .auto: return "تلقائي"
        case .noir: return "نوار"
        case .ivory: return "عاجي"
        }
    }

    /// تلقائي, then نوار, then عاجي, as on the board.
    var next: ThemeChoice {
        switch self {
        case .auto: return .noir
        case .noir: return .ivory
        case .ivory: return .auto
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .noir: return .dark
        case .ivory: return .light
        }
    }

    func palette(system: ColorScheme) -> Palette {
        switch self {
        case .noir: return .noir
        case .ivory: return .ivory
        case .auto: return system == .dark ? .noir : .ivory
        }
    }
}

nonisolated struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.noir
}

/// The screen's safe-area insets, read once at the root: every layer is drawn full screen for the zoom
/// between the home cards and the games, and pads itself.
nonisolated struct ScreenInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

nonisolated extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var screenInsets: EdgeInsets {
        get { self[ScreenInsetsKey.self] }
        set { self[ScreenInsetsKey.self] = newValue }
    }
}
