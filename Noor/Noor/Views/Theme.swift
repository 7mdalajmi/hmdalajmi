import SwiftUI

/// Noor's visual language for the editor: strictly neutral greys (R = G = B) around the photo so
/// nothing tints the user's perception of colour, and a single warm "Noor" amber accent that is
/// only ever used for state (active tool, slider fill, selection ring, primary button).
///
/// Every grey is defined in sRGB with equal channels, which is neutral in sRGB *and* Display P3
/// (both share the D65 white point), so the tokens stay neutral whatever space they are
/// composited in. The editor is always dark and opaque: no materials, blurs or system greys
/// next to the canvas (they pick up colour from the photo or carry a slight blue bias).
enum Theme {
    // MARK: Canvas surround (behind the photo)

    /// Default "Dark" surround, #121212.
    static let canvas = Theme.hex(0x121212)
    /// "Black" surround (OLED, highest perceived contrast), #000000.
    static let canvasBlack = Theme.hex(0x000000)
    /// "Assessment" mid-grey surround, #777777 (about L* 50, ISO 12646-style viewing).
    static let canvasGrey = Theme.hex(0x777777)

    // MARK: Surfaces

    /// Top bar, tool rail, panels and sheets.
    static let surface1 = Theme.hex(0x1C1C1C)
    /// Chips, segmented backgrounds, rows.
    static let surface2 = Theme.hex(0x262626)
    /// Pressed / selected chip.
    static let surface3 = Theme.hex(0x333333)
    /// Hairlines and the curve grid.
    static let separator = Theme.hex(0x2E2E2E)

    // MARK: Content

    /// Values and active labels (15.2 : 1 on surface1).
    static let textPrimary = Theme.hex(0xF2F2F2)
    /// Idle labels (7.4 : 1 on surface1).
    static let textSecondary = Theme.hex(0xABABAB)
    /// Hints and ticks (5.2 : 1 on surface1).
    static let textTertiary = Theme.hex(0x8E8E8E)
    /// Unselected tool rail icons.
    static let iconInactive = Theme.hex(0xA0A0A0)

    // MARK: Controls

    /// Slider track (3.2 : 1, meets the WCAG 1.4.11 non-text minimum).
    static let trackInactive = Theme.hex(0x6B6B6B)
    /// Detent tick on slider tracks.
    static let trackTick = Theme.hex(0x8E8E8E)
    /// Slider thumb and curve points.
    static let thumb = Theme.hex(0xF2F2F2)
    /// The one accent colour ("Noor" amber).
    static let accent = Theme.hex(0xFFB23F)
    /// Text and icons drawn on top of `accent`.
    static let onAccent = Theme.hex(0x121212)
    /// Destructive actions and curve-point removal.
    static let danger = Theme.hex(0xFF6159)

    // MARK: Data visualisation (histogram, curve channels, clipping)

    static let histRed = Theme.hex(0xFF4D4D)
    static let histGreen = Theme.hex(0x3DDC6A)
    static let histBlue = Theme.hex(0x4A90FF)
    static let histLuma = Theme.hex(0xBFBFBF)
    static let clipShadow = Theme.hex(0x2F7BFF)
    static let clipHighlight = Theme.hex(0xFF3B30)
    /// Badges drawn over the photo (black at 55 %).
    static let scrim = Theme.hex(0x000000, opacity: 0.55)

    // MARK: Surround

    /// The canvas background for the user's surround preference (Settings → Canvas surround).
    static func surround(_ surround: CanvasSurround) -> Color {
        switch surround {
        case .dark: return canvas
        case .black: return canvasBlack
        case .grey: return canvasGrey
        }
    }

    // MARK: Helpers

    /// 0xRRGGBB interpreted in sRGB. Kept private (and not a `Color.init(hex:)` extension) so it can
    /// never collide with a helper of the same name elsewhere in the target.
    private static func hex(_ rgb: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((rgb >> 16) & 0xFF) / 255,
              green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255,
              opacity: opacity)
    }
}

// MARK: - Metrics

extension Theme {
    /// The 4-pt spacing grid. Panel side padding is `l`, between sliders `xxs`…`xs`, between groups `l`.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Corner radii: thumbnails and badges 6, chips 8, panels and HUDs 14.
    enum Radius {
        static let thumb: CGFloat = 6
        static let chip: CGFloat = 8
        static let panel: CGFloat = 14
    }
}

// MARK: - Editor environment

/// Backing key for `EnvironmentValues.noorHapticsEnabled`.
private struct NoorHapticsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

/// Backing key for `EnvironmentValues.noorEditorIsInteracting`.
private struct NoorEditorIsInteractingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Mirrors `AppSettings.haptics`. `EditorView` sets it; sliders, chips, the rail and panel
    /// headers gate their `.sensoryFeedback` on it, so components never need the app model.
    var noorHapticsEnabled: Bool {
        get { self[NoorHapticsEnabledKey.self] }
        set { self[NoorHapticsEnabledKey.self] = newValue }
    }

    /// Mirrors `EditorModel.isInteracting` (a slider, curve or wheel drag is in progress).
    /// `AdjustmentSlider` uses it for focus mode: every row except the one being dragged fades.
    var noorEditorIsInteracting: Bool {
        get { self[NoorEditorIsInteractingKey.self] }
        set { self[NoorEditorIsInteractingKey.self] = newValue }
    }
}
