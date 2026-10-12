import SwiftUI

/// An `AdjustmentSlider` bound to one numeric field of the editor's live recipe.
///
/// It wires the gesture to the model's history automatically: `beginInteraction()` when a drag,
/// double-tap reset or VoiceOver adjustment starts, and `endInteraction(_:)` with the slider's
/// localized title when it ends, so every gesture becomes exactly one undo step.
struct RecipeSlider: View {
    private let title: LocalizedStringKey
    private let keyPath: WritableKeyPath<EditRecipe, Double>
    private let range: ParamRange
    private let defaultValue: Double
    private let fractionDigits: Int
    private let track: SliderTrackStyle
    private let isEnabled: Bool
    private let model: EditorModel

    init(_ title: LocalizedStringKey,
         _ keyPath: WritableKeyPath<EditRecipe, Double>,
         range: ParamRange,
         defaultValue: Double = 0,
         fractionDigits: Int = 0,
         track: SliderTrackStyle = .standard,
         isEnabled: Bool = true,
         model: EditorModel) {
        self.title = title
        self.keyPath = keyPath
        self.range = range
        self.defaultValue = defaultValue
        self.fractionDigits = fractionDigits
        self.track = track
        self.isEnabled = isEnabled
        self.model = model
    }

    var body: some View {
        AdjustmentSlider(title,
                         value: model.binding(keyPath),
                         range: range.closed,
                         defaultValue: defaultValue,
                         fractionDigits: fractionDigits,
                         track: track,
                         isEnabled: isEnabled,
                         onEditingChanged: { isEditing in editingChanged(isEditing) })
    }

    private func editingChanged(_ isEditing: Bool) {
        if isEditing {
            model.beginInteraction()
        } else {
            model.endInteraction(title.recipeSliderUndoLabel)
        }
    }
}

// MARK: - Undo label

private extension LocalizedStringKey {
    /// The localized text of a key created from a string literal (e.g. "Exposure" → "التعريض"),
    /// used as the undo-history label. `LocalizedStringKey` has no public accessor for its key, so
    /// it is read by reflection; if that ever fails the generic "Edit" label (the model's label for
    /// a non-gesture change) is used instead of an empty one.
    var recipeSliderUndoLabel: String {
        let child = Mirror(reflecting: self).children.first { $0.label == "key" }
        let key = (child?.value as? String) ?? ""
        guard !key.isEmpty else { return String(localized: "Edit") }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
