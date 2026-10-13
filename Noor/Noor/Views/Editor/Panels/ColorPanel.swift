import SwiftUI

// MARK: - Color panel

/// The Color tool. Four modes, chosen with chips:
///   * Adjust      – white balance (Temp / Tint), Vibrance, Saturation and the B&W treatment.
///   * Mix         – Lightroom's eight-band colour mixer (the B&W mix for monochrome photos).
///   * Grading     – three-way colour grading wheels.
///   * Calibration – camera-calibration primaries.
/// Every control writes the recipe through `EditorModel`, so each gesture is one undo step and the
/// photo itself is never touched. Like every panel, it fills the height the host gives it and
/// scrolls its own content below the header and the mode chips.
@MainActor
struct ColorPanel: View {
    let model: EditorModel

    @State private var mode: ColorPanelMode = .adjust
    @State private var mixBand: ColorBand = .red
    @State private var gradingTarget: ColorGradingTarget = .threeWay

    var body: some View {
        let group = mode.settingGroup
        VStack(spacing: 0) {
            // Reset restores the visible mode only (Adjust → colour, Mix → HSL, …).
            PanelHeader("Color") { model.reset(group) }
                .disabled(!model.recipe.hasEdits(in: group))

            ChipPicker(selection: $mode) { Text($0.title) }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ScrollView(.vertical) {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .adjust:
            adjust
        case .mix:
            ColorMixView(model: model, band: $mixBand)
        case .grading:
            ColorGradingView(model: model, target: $gradingTarget)
        case .calibration:
            CalibrationView(model: model)
        }
    }

    /// White balance, vibrance, saturation and the B&W treatment chip.
    private var adjust: some View {
        let isMonochrome = model.recipe.isMonochrome
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                MonochromeChip(isOn: isMonochrome) { toggleMonochrome() }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)

            RecipeSlider("Temp", \EditRecipe.temperature,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient(ColorToolPalette.temperatureTrack),
                         model: model)
            RecipeSlider("Tint", \EditRecipe.tint,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient(ColorToolPalette.tintTrack),
                         model: model)
            // Vibrance and saturation have no effect on a black & white rendition.
            RecipeSlider("Vibrance", \EditRecipe.vibrance,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient(ColorToolPalette.vibranceTrack),
                         isEnabled: !isMonochrome,
                         model: model)
            RecipeSlider("Saturation", \EditRecipe.saturation,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient(ColorToolPalette.saturationTrack),
                         isEnabled: !isMonochrome,
                         model: model)
        }
    }

    // MARK: Actions

    private func toggleMonochrome() {
        model.apply(String(localized: "Black & White")) { $0.isMonochrome.toggle() }
    }
}

// MARK: - Modes

/// The four sub-views of the Color panel.
enum ColorPanelMode: String, CaseIterable, Identifiable {
    case adjust, mix, grading, calibration

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .adjust: return "Adjust"
        case .mix: return "Mix"
        case .grading: return "Grading"
        case .calibration: return "Calibration"
        }
    }

    /// The recipe group the panel's Reset button restores.
    var settingGroup: SettingGroup {
        switch self {
        case .adjust: return .color
        case .mix: return .hsl
        case .grading: return .grading
        case .calibration: return .calibration
        }
    }
}

// MARK: - B&W chip

/// The black & white treatment toggle, styled like a `ChipPicker` chip (accent ring when on).
@MainActor
private struct MonochromeChip: View {
    let isOn: Bool
    let action: () -> Void

    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    /// Counts taps: the haptic follows these, not `isOn`, so undo / redo / Reset stay silent
    /// (as in `ChipPicker`).
    @State private var tapCount = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button {
            action()
            tapCount += 1
        } label: {
            Label("B&W", systemImage: "circle.lefthalf.filled")
                .font(.footnote.weight(isOn ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(isOn ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background { shape.fill(isOn ? Theme.surface3 : Theme.surface2) }
                .overlay { shape.strokeBorder(isOn ? Theme.accent : Color.clear, lineWidth: 1) }
                .padding(.vertical, 6)                 // 44-pt hit target around the 32-pt chip
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: tapCount) { _, _ in hapticsEnabled }
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}

// MARK: - Palette

/// Colours for slider tracks, band swatches and the grading wheel. These are UI hints in sRGB,
/// not colour-accurate references (the photo itself is always rendered by the engine).
enum ColorToolPalette {
    /// 0xRRGGBB in sRGB.
    static func srgb(_ hex: UInt32) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: 1)
    }

    /// A colour of the given hue (degrees, any range).
    static func hue(_ degrees: Double, saturation: Double = 0.85, brightness: Double = 0.95) -> Color {
        var h = degrees.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return Color(hue: h / 360,
                     saturation: min(max(saturation, 0), 1),
                     brightness: min(max(brightness, 0), 1))
    }

    static let neutral = ColorToolPalette.srgb(0x808080)
    static let temperatureTrack: [Color] = [ColorToolPalette.srgb(0x4A86FF), ColorToolPalette.srgb(0xFFD34A)]
    static let tintTrack: [Color] = [ColorToolPalette.srgb(0x3DDC6A), ColorToolPalette.srgb(0xE04AE0)]
    static let vibranceTrack: [Color] = [ColorToolPalette.srgb(0x808080), ColorToolPalette.srgb(0x3FA9F5)]
    static let saturationTrack: [Color] = [ColorToolPalette.srgb(0x808080), ColorToolPalette.srgb(0xF0573A)]
    /// Dark → light (luminance, balance).
    static let greyRamp: [Color] = [ColorToolPalette.srgb(0x1A1A1A), ColorToolPalette.srgb(0xF2F2F2)]
    /// A full hue circle, 0° (red) → 360° (red), evenly spaced every 30°.
    static let hueCircle: [Color] = (0...12).map {
        ColorToolPalette.hue(Double($0) * 30, saturation: 0.8, brightness: 0.9)
    }

    // MARK: Colour bands

    static func swatch(_ band: ColorBand) -> Color {
        hue(band.displayHue)
    }

    /// Previous band hue → band → next band hue.
    static func hueTrack(_ band: ColorBand) -> [Color] {
        let all = ColorBand.allCases
        guard let i = all.firstIndex(of: band) else { return [swatch(band), swatch(band)] }
        let previous = all[(i + all.count - 1) % all.count]
        let next = all[(i + 1) % all.count]
        return [swatch(previous), swatch(band), swatch(next)]
    }

    /// Grey → band colour.
    static func saturationTrack(_ band: ColorBand) -> [Color] {
        [neutral, swatch(band)]
    }

    /// Dark band colour → light band colour.
    static func luminanceTrack(_ band: ColorBand) -> [Color] {
        [hue(band.displayHue, saturation: 0.9, brightness: 0.25),
         hue(band.displayHue, saturation: 0.35, brightness: 1)]
    }

    static func bandName(_ band: ColorBand) -> LocalizedStringKey {
        switch band {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .aqua: return "Aqua"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .magenta: return "Magenta"
        }
    }
}
