import SwiftUI

// MARK: - Color mix

/// Lightroom's Color Mixer: eight hue bands (Red … Magenta), each with Hue, Saturation and
/// Luminance. A row of colour dots picks the band; the band name is always written out so the
/// control never relies on colour alone.
///
/// When the photo is black & white the same per-band luminance values are the B&W mix weights,
/// so the view becomes "B&W Mix": one luminance slider per band, labelled with the band name.
/// Values are written through `EditRecipe.subscript(band:)`, which drops neutral bands.
@MainActor
struct ColorMixView: View {
    let model: EditorModel
    @Binding var band: ColorBand

    @Environment(\.noorHapticsEnabled) private var hapticsEnabled

    var body: some View {
        if model.recipe.isMonochrome {
            blackAndWhiteMix
        } else {
            colorMix
        }
    }

    // MARK: Colour

    private var colorMix: some View {
        VStack(alignment: .leading, spacing: 2) {
            bandPicker

            HStack(spacing: 8) {
                Text(ColorToolPalette.bandName(band))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                resetBandButton
            }
            .padding(.bottom, 4)

            Group {
                RecipeSlider("Hue", \EditRecipe.[band: band].hue,
                             range: EditRecipe.Limits.bipolar,
                             track: .gradient(ColorToolPalette.hueTrack(band)),
                             model: model)
                RecipeSlider("Saturation", \EditRecipe.[band: band].saturation,
                             range: EditRecipe.Limits.bipolar,
                             track: .gradient(ColorToolPalette.saturationTrack(band)),
                             model: model)
                RecipeSlider("Luminance", \EditRecipe.[band: band].luminance,
                             range: EditRecipe.Limits.bipolar,
                             track: .gradient(ColorToolPalette.luminanceTrack(band)),
                             model: model)
            }
            .id(band)
        }
        .sensoryFeedback(.selection, trigger: band) { _, _ in hapticsEnabled }
    }

    /// Eight 26-pt dots; each column is a full-height (44 pt) hit target.
    private var bandPicker: some View {
        HStack(spacing: 0) {
            ForEach(ColorBand.allCases) { candidate in
                bandDot(candidate)
            }
        }
    }

    private func bandDot(_ candidate: ColorBand) -> some View {
        let isSelected = candidate == band
        let isEdited = !model.recipe[band: candidate].isIdentity
        return Button {
            band = candidate
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(ColorToolPalette.swatch(candidate))
                    .frame(width: 26, height: 26)
                    .padding(3)
                    .overlay(
                        Circle().strokeBorder(isSelected ? Theme.thumb : Color.clear, lineWidth: 2)
                    )
                Circle()
                    .fill(isEdited ? Theme.textSecondary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ColorToolPalette.bandName(candidate)))
        .accessibilityValue(isEdited ? Text("Edited") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var resetBandButton: some View {
        let isNeutral = model.recipe[band: band].isIdentity
        return Button {
            resetBand(band)
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.footnote.weight(.medium))
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isNeutral ? Theme.textTertiary : Theme.textPrimary)
        .disabled(isNeutral)
        .accessibilityLabel(Text("Reset Color"))
    }

    // MARK: Black & white

    private var blackAndWhiteMix: some View {
        // The band names are `LocalizedStringKey`s, so the sliders name their undo step explicitly.
        let undoLabel = String(localized: "B&W Mix")
        return VStack(alignment: .leading, spacing: 2) {
            Text("B&W Mix")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 4)

            ForEach(ColorBand.allCases) { candidate in
                RecipeSlider(ColorToolPalette.bandName(candidate), \EditRecipe.[band: candidate].luminance,
                             range: EditRecipe.Limits.bipolar,
                             track: .gradient(ColorToolPalette.luminanceTrack(candidate)),
                             undoLabel: undoLabel,
                             model: model)
            }
        }
    }

    // MARK: Actions

    private func resetBand(_ target: ColorBand) {
        model.apply(String(localized: "Color Mix")) { $0[band: target] = HSLAdjustment() }
    }
}
