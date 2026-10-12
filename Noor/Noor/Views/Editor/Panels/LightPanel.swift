import SwiftUI

/// The Light panel: Exposure, Contrast, Highlights, Shadows, Whites, Blacks, plus a "Curve" row
/// that pushes the tone curve editor inside the panel (with a back button), so the photo stays
/// visible while the curve is edited.
///
/// While the curve is open the panel asks the editor for extra height (iPhone portrait).
///
/// Ranges follow Lightroom (Process 2012): Exposure −5…+5 EV with two decimals, the rest
/// −100…+100. Resetting the panel resets Light; resetting inside the curve resets the curve.
struct LightPanel: View {
    let model: EditorModel

    @State private var showsCurve = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.noorPanelPrefersTall) private var prefersTallPanel

    var body: some View {
        ZStack(alignment: .top) {
            if showsCurve {
                curvePage
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing))
            } else {
                sliderPage
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .onDisappear {
            prefersTallPanel.wrappedValue = false
        }
    }

    // MARK: Sliders

    private var sliderPage: some View {
        VStack(spacing: 0) {
            PanelHeader("Light") { model.reset(.light) }
                .disabled(!model.recipe.hasEdits(in: .light))

            ScrollView(.vertical) {
                VStack(spacing: Theme.Space.xxs) {
                    RecipeSlider("Exposure", \.exposure, range: EditRecipe.Limits.exposure,
                                 fractionDigits: 2, model: model)
                    RecipeSlider("Contrast", \.contrast, range: EditRecipe.Limits.bipolar, model: model)

                    PanelHeader.GroupSeparator()

                    RecipeSlider("Highlights", \.highlights, range: EditRecipe.Limits.bipolar, model: model)
                    RecipeSlider("Shadows", \.shadows, range: EditRecipe.Limits.bipolar, model: model)
                    RecipeSlider("Whites", \.whites, range: EditRecipe.Limits.bipolar, model: model)
                    RecipeSlider("Blacks", \.blacks, range: EditRecipe.Limits.bipolar, model: model)

                    PanelHeader.GroupSeparator()

                    curveRow
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Opens the curve sub-view. Shows a dot when the curve has edits.
    private var curveRow: some View {
        Button {
            setShowsCurve(true)
        } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text("Curve")
                    .font(.footnote.weight(.medium))
                if model.recipe.hasEdits(in: .curve) {
                    Circle()
                        .fill(Theme.textSecondary)
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.surface2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(model.recipe.hasEdits(in: .curve) ? Text("Edited") : Text(verbatim: ""))
        .accessibilityHint(Text("Opens the tone curve"))
    }

    // MARK: Curve

    private var curvePage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    setShowsCurve(false)
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, Theme.Space.xs)
                .accessibilityShowsLargeContentViewer()

                PanelHeader("Curve") { model.reset(.curve) }
                    .padding(.leading, -Theme.Space.s)
                    .disabled(!model.recipe.hasEdits(in: .curve))
            }

            ToneCurveEditor(model: model)
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func setShowsCurve(_ shows: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)) {
            showsCurve = shows
            prefersTallPanel.wrappedValue = shows     // more room for the graph in portrait
        }
    }
}
