import SwiftUI

// MARK: - Color grading

/// Lightroom-style colour grading. "3-Way" shows the Shadows, Midtones and Highlights wheels
/// together; each other choice shows one large wheel with precise Hue / Saturation / Luminance
/// sliders. Blending and Balance shape all wheels and appear in every mode.
/// Wheels write `EditRecipe.grading` through the model's binding, bracketed by
/// `beginInteraction()` / `endInteraction(_:)` so every drag is a single undo step.
@MainActor
struct ColorGradingView: View {
    let model: EditorModel
    @Binding var target: ColorGradingTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A scrolling chip row with its own 16-pt inset: cancel the panel's side padding so
            // the chips scroll edge to edge.
            ChipPicker(selection: $target, fillsWidth: false) { Text($0.title) }
                .padding(.horizontal, -16)
                .padding(.bottom, 8)

            if let range = target.range {
                singleRange(range)
            } else {
                threeWay
            }

            RecipeSlider("Blending", \EditRecipe.grading.blending,
                         range: EditRecipe.Limits.unit100,
                         defaultValue: 50,
                         model: model)
            RecipeSlider("Balance", \EditRecipe.grading.balance,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient(ColorToolPalette.greyRamp),
                         model: model)
        }
    }

    // MARK: 3-way

    /// Midtones on top, Shadows and Highlights below (tonal order, always left-to-right).
    private var threeWay: some View {
        VStack(spacing: 12) {
            wheelCell(.midtones)
            HStack(spacing: 32) {
                wheelCell(.shadows)
                wheelCell(.highlights)
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
        .padding(.bottom, 8)
    }

    private func wheelCell(_ range: GradeRange) -> some View {
        let isEdited = !model.recipe.grading[range].isIdentity
        return VStack(spacing: 6) {
            wheel(for: range)
                .frame(width: 96, height: 96)
            Text(ColorGradingTarget.title(of: range))
                .font(.caption)
                .foregroundStyle(isEdited ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    // MARK: Single range

    private func singleRange(_ range: GradeRange) -> some View {
        let current = model.recipe.grading[range]
        return VStack(alignment: .leading, spacing: 2) {
            wheel(for: range)
                .frame(maxWidth: 200)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

            RecipeSlider("Hue", \EditRecipe.grading[range].hue,
                         range: ColorGradingTarget.hueRange,
                         track: .gradient(ColorToolPalette.hueCircle),
                         model: model)
            RecipeSlider("Saturation", \EditRecipe.grading[range].saturation,
                         range: EditRecipe.Limits.unit100,
                         track: .gradient([ColorToolPalette.neutral, ColorToolPalette.hue(current.hue)]),
                         model: model)
            RecipeSlider("Luminance", \EditRecipe.grading[range].luminance,
                         range: EditRecipe.Limits.bipolar,
                         track: .gradient(ColorToolPalette.greyRamp),
                         model: model)
        }
        .id(range)
    }

    // MARK: Wheel

    private func wheel(for range: GradeRange) -> some View {
        GradingWheel(ColorGradingTarget.title(of: range),
                     wheel: model.binding(\EditRecipe.grading[range]),
                     onEditingChanged: { editing in
                         if editing {
                             model.beginInteraction()
                         } else {
                             model.endInteraction(String(localized: "Color Grading"))
                         }
                     })
    }
}

// MARK: - Targets

/// What the grading view shows: all three tonal wheels, or one range in detail.
enum ColorGradingTarget: String, CaseIterable, Identifiable {
    case threeWay, shadows, midtones, highlights, global

    var id: String { rawValue }

    /// Lightroom wheel hue, degrees.
    static let hueRange = ParamRange(0, 360)

    var range: GradeRange? {
        switch self {
        case .threeWay: return nil
        case .shadows: return .shadows
        case .midtones: return .midtones
        case .highlights: return .highlights
        case .global: return .global
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .threeWay: return "3-Way"
        case .shadows: return "Shadows"
        case .midtones: return "Midtones"
        case .highlights: return "Highlights"
        case .global: return "Global"
        }
    }

    static func title(of range: GradeRange) -> LocalizedStringKey {
        switch range {
        case .shadows: return "Shadows"
        case .midtones: return "Midtones"
        case .highlights: return "Highlights"
        case .global: return "Global"
        }
    }
}
