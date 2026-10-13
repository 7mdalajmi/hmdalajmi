import SwiftUI

/// The Detail panel: Sharpening (0…150) with Radius (0.5…3 px, one decimal) and Masking, then
/// luminance and colour Noise Reduction (0…100).
///
/// Radius and Masking only shape the sharpening, so they are disabled while Sharpening is 0
/// (the renderer skips the stage entirely then). Fine detail can only be judged on true pixels,
/// so the panel reminds the user to look at 100 %; the canvas renders the full-resolution
/// original at that zoom.
@MainActor
struct DetailPanel: View {
    let model: EditorModel

    @Environment(\.locale) private var locale

    var body: some View {
        let isSharpening = model.recipe.sharpening != 0

        VStack(spacing: 0) {
            PanelHeader("Detail") { model.reset(.detail) }
                .disabled(!model.recipe.hasEdits(in: .detail))

            ScrollView(.vertical) {
                VStack(spacing: Theme.Space.xxs) {
                    zoomHint
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, Theme.Space.xs)

                    RecipeSlider("Sharpening", \.sharpening, range: EditRecipe.Limits.sharpening, model: model)
                    RecipeSlider("Radius", \.sharpenRadius, range: EditRecipe.Limits.sharpenRadius,
                                 defaultValue: EditRecipe.identity.sharpenRadius, fractionDigits: 1,
                                 isEnabled: isSharpening, model: model)
                    RecipeSlider("Masking", \.sharpenMasking, range: EditRecipe.Limits.unit100,
                                 isEnabled: isSharpening, model: model)

                    PanelHeader.GroupSeparator()

                    RecipeSlider("Noise Reduction", \.noiseReduction, range: EditRecipe.Limits.unit100, model: model)
                    RecipeSlider("Color Noise Reduction", \.colorNoiseReduction,
                                 range: EditRecipe.Limits.unit100, model: model)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Informational chip (not a button): sharpening, noise and grain must be judged at 1:1.
    private var zoomHint: some View {
        let oneToOne = (1.0).formatted(.percent.locale(locale))
        return HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .accessibilityHidden(true)
            Text("View at \(oneToOne) to judge")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs + 2)
        .background {
            Capsule().fill(Theme.surface2)
        }
        .accessibilityElement(children: .combine)
    }
}
