import SwiftUI

/// The Effects panel, laid out like Lightroom mobile:
/// * Texture, Clarity, Dehaze (−100…+100);
/// * Vignette (post-crop) with Midpoint, Feather, Roundness and Highlights, which only shape the
///   vignette and are disabled while its amount is 0;
/// * Grain with Size and Roughness, disabled while its amount is 0.
///
/// Every value is relative to the picture, so the preview matches the full-resolution export.
struct EffectsPanel: View {
    let model: EditorModel

    var body: some View {
        let hasVignette = model.recipe.vignette.amount != 0
        let hasGrain = model.recipe.grain.amount != 0

        VStack(spacing: 0) {
            PanelHeader("Effects") { model.reset(.effects) }
                .disabled(!model.recipe.hasEdits(in: .effects))

            ScrollView(.vertical) {
                VStack(spacing: Theme.Space.xxs) {
                    RecipeSlider("Texture", \.texture, range: EditRecipe.Limits.bipolar, model: model)
                    RecipeSlider("Clarity", \.clarity, range: EditRecipe.Limits.bipolar, model: model)
                    RecipeSlider("Dehaze", \.dehaze, range: EditRecipe.Limits.bipolar, model: model)

                    PanelHeader.GroupSeparator()

                    RecipeSlider("Vignette", \.vignette.amount, range: EditRecipe.Limits.bipolar, model: model)
                    RecipeSlider("Midpoint", \.vignette.midpoint, range: EditRecipe.Limits.unit100,
                                 defaultValue: Vignette().midpoint, isEnabled: hasVignette, model: model)
                    RecipeSlider("Feather", \.vignette.feather, range: EditRecipe.Limits.unit100,
                                 defaultValue: Vignette().feather, isEnabled: hasVignette, model: model)
                    RecipeSlider("Roundness", \.vignette.roundness, range: EditRecipe.Limits.bipolar,
                                 defaultValue: Vignette().roundness, isEnabled: hasVignette, model: model)
                    RecipeSlider("Highlights", \.vignette.highlights, range: EditRecipe.Limits.unit100,
                                 defaultValue: Vignette().highlights, isEnabled: hasVignette, model: model)

                    PanelHeader.GroupSeparator()

                    RecipeSlider("Grain", \.grain.amount, range: EditRecipe.Limits.unit100, model: model)
                    RecipeSlider("Size", \.grain.size, range: EditRecipe.Limits.unit100,
                                 defaultValue: Grain().size, isEnabled: hasGrain, model: model)
                    RecipeSlider("Roughness", \.grain.roughness, range: EditRecipe.Limits.unit100,
                                 defaultValue: Grain().roughness, isEnabled: hasGrain, model: model)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
