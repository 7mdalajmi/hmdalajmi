import SwiftUI

/// An `AdjustmentSlider` bound to one numeric field of the editor's live recipe.
///
/// It wires the gesture to the model's history automatically: `beginInteraction()` when a drag,
/// double-tap reset or VoiceOver adjustment starts, and `endInteraction(_:)` with the slider's
/// localized title when it ends, so every gesture becomes exactly one undo step.
///
/// The title is normally a string literal (`RecipeSlider("Exposure", \.exposure, …)`), which
/// becomes a `LocalizedStringResource`: it is shown as the label and also resolved with
/// `String(localized:)` for the undo-history label, so both always read the same. A title that is
/// already a `LocalizedStringKey` value (e.g. a colour band name) uses the second initializer and
/// can name its undo step with `undoLabel:`.
@MainActor
struct RecipeSlider: View {
    private let label: Text
    private let undoLabel: UndoLabel
    private let keyPath: WritableKeyPath<EditRecipe, Double>
    private let range: ParamRange
    private let defaultValue: Double
    private let fractionDigits: Int
    private let track: SliderTrackStyle
    private let isEnabled: Bool
    private let model: EditorModel

    /// Where the undo-history label comes from. Resolved only when a gesture ends, so building
    /// the slider (on every recipe change) never performs a localization lookup.
    private enum UndoLabel {
        case resource(LocalizedStringResource)
        case explicit(String?)

        var resolved: String {
            switch self {
            case .resource(let resource):
                let text = String(localized: resource)
                return text.isEmpty ? String(localized: "Edit") : text
            case .explicit(let text):
                guard let text, !text.isEmpty else { return String(localized: "Edit") }
                return text
            }
        }
    }

    /// Title from a string literal (the usual case): label and undo step share the same text.
    init(_ title: LocalizedStringResource,
         _ keyPath: WritableKeyPath<EditRecipe, Double>,
         range: ParamRange,
         defaultValue: Double = 0,
         fractionDigits: Int = 0,
         track: SliderTrackStyle = .standard,
         isEnabled: Bool = true,
         model: EditorModel) {
        self.label = Text(title)
        self.undoLabel = .resource(title)
        self.keyPath = keyPath
        self.range = range
        self.defaultValue = defaultValue
        self.fractionDigits = fractionDigits
        self.track = track
        self.isEnabled = isEnabled
        self.model = model
    }

    /// Title from an existing `LocalizedStringKey` value. `LocalizedStringKey` has no public
    /// accessor for its text, so the undo step is named by `undoLabel` (already localized), or
    /// the model's generic "Edit" when it is omitted. Disfavoured so that string literals always
    /// pick the initializer above.
    @_disfavoredOverload
    init(_ title: LocalizedStringKey,
         _ keyPath: WritableKeyPath<EditRecipe, Double>,
         range: ParamRange,
         defaultValue: Double = 0,
         fractionDigits: Int = 0,
         track: SliderTrackStyle = .standard,
         isEnabled: Bool = true,
         undoLabel: String? = nil,
         model: EditorModel) {
        self.label = Text(title)
        self.undoLabel = .explicit(undoLabel)
        self.keyPath = keyPath
        self.range = range
        self.defaultValue = defaultValue
        self.fractionDigits = fractionDigits
        self.track = track
        self.isEnabled = isEnabled
        self.model = model
    }

    var body: some View {
        AdjustmentSlider(label: label,
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
            model.endInteraction(undoLabel.resolved)
        }
    }
}
