import SwiftUI

// MARK: - Calibration

/// Lightroom's Calibration panel: a shadow tint plus the hue and saturation of the red, green and
/// blue primaries (all −100…100). Each slider writes `EditRecipe.calibration` through
/// `RecipeSlider`, so every drag is one undo step.
@MainActor
struct CalibrationView: View {
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("Shadows")
            RecipeSlider("Tint", \EditRecipe.calibration.shadowTint,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient(ColorToolPalette.tintTrack),
                         model: model)

            sectionTitle("Red Primary")
            RecipeSlider("Hue", \EditRecipe.calibration.redHue,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient([ColorToolPalette.hue(340), ColorToolPalette.hue(25)]),
                         model: model)
            RecipeSlider("Saturation", \EditRecipe.calibration.redSaturation,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient([ColorToolPalette.neutral, ColorToolPalette.hue(0)]),
                         model: model)

            sectionTitle("Green Primary")
            RecipeSlider("Hue", \EditRecipe.calibration.greenHue,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient([ColorToolPalette.hue(80), ColorToolPalette.hue(160)]),
                         model: model)
            RecipeSlider("Saturation", \EditRecipe.calibration.greenSaturation,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient([ColorToolPalette.neutral, ColorToolPalette.hue(120)]),
                         model: model)

            sectionTitle("Blue Primary")
            RecipeSlider("Hue", \EditRecipe.calibration.blueHue,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient([ColorToolPalette.hue(195), ColorToolPalette.hue(275)]),
                         model: model)
            RecipeSlider("Saturation", \EditRecipe.calibration.blueSaturation,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient([ColorToolPalette.neutral, ColorToolPalette.hue(235)]),
                         model: model)
        }
    }

    // MARK: Layout

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }
}
