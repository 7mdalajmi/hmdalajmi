import SwiftUI
import Accessibility
import CoreGraphics

/// "Save Preset" (UX spec §1.5, presets spec §4): turns the current edit into a user preset.
///
/// * **Name** (required) and **Group** (free text; existing groups of the user's presets are offered
///   as one-tap suggestions; default "My Presets").
/// * **Include:** one switch per setting group, all on except Detail (sharpening and noise reduction
///   depend on each photo). An included group is applied even where it is at its defaults, exactly
///   like Lightroom, so the note under the list says so.
/// * **Keep each photo's exposure & white balance** (on by default): the preset leaves Exposure,
///   Temperature and Tint alone, so it travels well between photos.
/// * **Preview:** the preset applied to this photo *unedited*, i.e. exactly what the preset carries,
///   re-rendered (off the main thread) whenever a switch changes.
///
/// The preset stores plain recipe values (`PresetValues(recipe:groups:)`), never pixels.
@MainActor
struct SavePresetSheet: View {
    let model: EditorModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    /// The Presets panel shows the user's own presets after a save.
    @AppStorage(PresetsPanelStorage.selectedChipKey) private var presetsPanelChipID = ""

    @State private var name = ""
    @State private var group = String(localized: "My Presets")
    @State private var includes: Set<SettingGroup> = Set(SettingGroup.allCases).subtracting([.detail])
    @State private var keepsPhotoExposureAndWhiteBalance = true
    @State private var preview: CGImage?
    @State private var isPreviewLoading = true
    @State private var isSaveErrorPresented = false
    @State private var saveErrorMessage = ""

    /// Longest name / group kept (matches the preset library's limit).
    private static let maxTextLength = 80
    /// Height of the preview picture in points.
    private static let previewHeight: CGFloat = 170

    /// Include rows in Lightroom's panel order.
    private static let groupOrder: [SettingGroup] = [.light, .curve, .color, .hsl, .grading, .effects, .detail, .calibration]

    init(model: EditorModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                detailsSection
                includeSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface1)
            .navigationTitle("Save Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .task(id: previewInput) {
            await renderPreview()
        }
        .alert("Couldn't Save Preset", isPresented: $isSaveErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: saveErrorMessage)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.surface1)
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            previewPicture
                .frame(maxWidth: .infinity)
                .listRowBackground(Theme.surface1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Preview of the preset on this photo"))
        } footer: {
            Text("This preset on the unedited photo.")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var previewPicture: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
        if let preview {
            Image(decorative: preview, scale: displayScale)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: Self.previewHeight)
                .clipShape(shape)
        } else {
            shape
                .fill(Theme.surface2)
                .frame(width: Self.previewHeight * 1.5, height: Self.previewHeight)
                .overlay {
                    if isPreviewLoading {
                        ProgressView()
                            .tint(Theme.textSecondary)
                    }
                }
        }
    }

    private var detailsSection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Name", text: $name, prompt: Text("Required"))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
            LabeledContent("Group") {
                TextField("Group", text: $group, prompt: Text("My Presets"))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
            let suggestions = groupSuggestions
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            suggestionChip(suggestion)
                        }
                    }
                    .padding(.vertical, Theme.Space.xxs)
                }
                .scrollIndicators(.hidden)
            }
        } header: {
            Text("Preset")
        }
        .listRowBackground(Theme.surface2)
    }

    private func suggestionChip(_ suggestion: String) -> some View {
        let isCurrent = suggestion == group.trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        return Button {
            group = suggestion
        } label: {
            Text(verbatim: suggestion)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: 32)
                .background {
                    shape.fill(isCurrent ? Theme.surface3 : Theme.surface1)
                }
                .overlay {
                    shape.strokeBorder(isCurrent ? Theme.accent : Color.clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var includeSection: some View {
        Section {
            ForEach(Self.groupOrder) { settingGroup in
                Toggle(isOn: includeBinding(settingGroup)) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(Self.title(for: settingGroup))
                            .foregroundStyle(Theme.textPrimary)
                        if model.recipe.hasEdits(in: settingGroup) {
                            Text("Edited")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Text("At defaults")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .tint(Theme.accent)

                if settingGroup == .light {
                    Toggle(isOn: $keepsPhotoExposureAndWhiteBalance) {
                        Text("Keep each photo's exposure & white balance")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .tint(Theme.accent)
                    .padding(.leading, Theme.Space.l)
                    .disabled(!includes.contains(.light) && !includes.contains(.color))
                }
            }
        } header: {
            Text("Include")
        } footer: {
            Text("Included settings replace the photo's own, even when they're at their defaults.")
        }
        .listRowBackground(Theme.surface2)
    }

    // MARK: State

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !includes.isEmpty
    }

    /// The user's existing preset groups, in library order.
    private var groupSuggestions: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for preset in app.presets.presets where preset.source == .user {
            if seen.insert(preset.group).inserted {
                result.append(preset.group)
            }
        }
        return result
    }

    private func includeBinding(_ settingGroup: SettingGroup) -> Binding<Bool> {
        Binding(
            get: { @MainActor in includes.contains(settingGroup) },
            set: { @MainActor isOn in
                if isOn {
                    includes.insert(settingGroup)
                } else {
                    includes.remove(settingGroup)
                }
            }
        )
    }

    /// The values the preset will carry.
    private var presetValues: PresetValues {
        var values = PresetValues(recipe: model.recipe, groups: includes)
        if keepsPhotoExposureAndWhiteBalance {
            values.exposure = nil
            values.temperature = nil
            values.tint = nil
        }
        return values
    }

    private func makePreset(name: String, group: String) -> Preset {
        Preset(id: UUID(),
               name: name,
               group: group,
               createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
               source: .user,
               supportsAmount: true,
               includes: includes,
               values: presetValues)
    }

    // MARK: Preview

    /// What the preview depends on.
    private var previewInput: SavePresetPreviewInput {
        SavePresetPreviewInput(values: presetValues, includes: includes, displayScale: displayScale)
    }

    /// Renders the preset over the unedited photo (keeping the photo's crop) off the main thread.
    private func renderPreview() async {
        try? await Task.sleep(for: .milliseconds(120))     // coalesce quick switch changes
        guard !Task.isCancelled else { return }

        let document = model.document
        let current = model.recipe
        let base: EditRecipe = {
            var unedited = EditRecipe()
            unedited.geometry = current.geometry        // presets never move the crop
            unedited.keepsHDR = current.keepsHDR
            return unedited
        }()
        let preset = makePreset(name: "", group: "")
        let context = PresetApplyContext(asShotKelvin: document.info.asShotKelvin,
                                         asShotTint: document.info.asShotTint)
        let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 2
        let longEdge = min((Self.previewHeight * 2 * scale).rounded(.up), 1024)

        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            var recipe = preset.target(over: base, context: context)
            recipe.geometry = base.geometry
            recipe.keepsHDR = base.keepsHDR
            return ThumbnailRenderer.render(document, recipe: recipe, longEdge: longEdge)
        }.value
        guard !Task.isCancelled else { return }
        preview = image
        isPreviewLoading = false
    }

    // MARK: Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !includes.isEmpty else { return }
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalGroup = trimmedGroup.isEmpty ? String(localized: "My Presets") : trimmedGroup
        let preset = makePreset(name: String(trimmedName.prefix(Self.maxTextLength)),
                                group: String(finalGroup.prefix(Self.maxTextLength)))
        do {
            try app.presets.add(preset)
            presetsPanelChipID = PresetsPanelStorage.mineChipID
            AccessibilityNotification.Announcement(String(localized: "Preset \(preset.name) saved")).post()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaveErrorPresented = true
        }
    }

    // MARK: Labels

    private static func title(for settingGroup: SettingGroup) -> LocalizedStringKey {
        switch settingGroup {
        case .light: return "Light"
        case .color: return "Color"
        case .effects: return "Effects"
        case .detail: return "Detail"
        case .curve: return "Curve"
        case .grading: return "Color Grading"
        case .hsl: return "Color Mix"
        case .calibration: return "Calibration"
        }
    }
}

// MARK: - Preview input

/// Everything the preview picture depends on.
private struct SavePresetPreviewInput: Equatable {
    var values: PresetValues
    var includes: Set<SettingGroup>
    var displayScale: CGFloat
}
