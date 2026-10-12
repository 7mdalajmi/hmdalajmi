import SwiftUI
import Accessibility

/// The Presets tool (UX spec §2.10, presets spec §5), following Lightroom mobile:
///
/// * **Group chips:** Favorites (when there are any), each built-in group in pack order, Imported
///   (Lightroom XMP / DNG presets, when there are any), Mine (the user's own presets) and "Manage…",
///   which opens the preset manager. The chosen group is remembered on this device.
/// * **Strip:** 72-pt thumbnails of *this* photo with each preset applied at 100 % over the baseline
///   (exactly what a tap produces), rendered off the main thread by `PresetThumbnailCache`.
///   A "≈" badge marks imported presets that could only be approximated.
/// * **Tap** previews a preset over the baseline captured when browsing started (presets never stack
///   while browsing). **Tap the selected preset again** to show or hide the full-width Amount slider
///   (0–200 %, detent at 100). ✓ keeps the preset as one undo step, ✕ restores the baseline; leaving
///   the tool also keeps it (the model commits).
/// * **Long press:** favourite, share as a `.noorpreset` file, show the import notes, delete (own and
///   imported presets only, after confirmation).
/// * The "+" cell at the end of the strip saves the current edit as a new preset.
///
/// Everything here is recipe values; previewing a preset never touches pixels.
@MainActor
struct PresetsPanel: View {
    let model: EditorModel

    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale
    @Environment(\.displayScale) private var displayScale
    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The last chosen group chip (a per-device convenience, not part of any document).
    @AppStorage(PresetsPanelStorage.selectedChipKey) private var storedChipID = ""
    @State private var isAmountVisible = false
    @State private var isManagerPresented = false
    @State private var selectionTick = 0
    @State private var deleteTarget: Preset?
    @State private var isDeletePresented = false
    @State private var notesTarget: Preset?
    @State private var isNotesPresented = false

    init(model: EditorModel) {
        self.model = model
    }

    private var thumbnails: PresetThumbnailCache { PresetThumbnailCache.shared }

    var body: some View {
        let library = app.presets
        let chips = Self.chips(for: library)
        let selected = Self.resolvedChip(storedID: storedChipID, among: chips)
        let presets = Self.presets(for: selected, in: library)
        let activePreset = model.activePresetID.flatMap { library.preset(id: $0) }
        let showsAmount = isAmountVisible && (activePreset?.supportsAmount ?? false)

        VStack(spacing: 0) {
            header(isPreviewing: model.activePresetID != nil)

            ScrollView(.vertical) {
                VStack(spacing: Theme.Space.xs) {
                    ChipPicker(chips, selection: chipSelection(selected), fillsWidth: false) { chip in
                        Self.chipTitle(chip, library: library, locale: locale)
                    }

                    if showsAmount {
                        amountSlider
                            .padding(.horizontal, Theme.Space.l)
                            .transition(.opacity)
                    }

                    strip(presets, chip: selected, library: library)
                }
                .padding(.bottom, Theme.Space.s)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: showsAmount)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .onChange(of: thumbnailContextID, initial: true) {
            thumbnails.prepare(for: model, displayScale: displayScale)
        }
        .onChange(of: model.activePresetID) { _, activeID in
            if activeID == nil { isAmountVisible = false }
        }
        .sensoryFeedback(.selection, trigger: selectionTick) { _, _ in hapticsEnabled }
        .sheet(isPresented: $isManagerPresented) {
            PresetManagerView()
                .environment(app)
        }
        .confirmationDialog("Delete Preset?", isPresented: $isDeletePresented,
                            titleVisibility: .visible, presenting: deleteTarget) { preset in
            Button("Delete", role: .destructive) {
                delete(preset)
            }
            Button("Cancel", role: .cancel) {}
        } message: { preset in
            Text("“\(preset.displayName(locale))” will be removed from Noor. This can't be undone.")
        }
        .alert("Import Notes", isPresented: $isNotesPresented, presenting: notesTarget) { _ in
            Button("OK", role: .cancel) {}
        } message: { preset in
            Text(verbatim: (preset.notes ?? []).joined(separator: "\n"))
        }
    }

    // MARK: Header

    /// Panel title, plus ✕ / ✓ while a preset is being previewed.
    private func header(isPreviewing: Bool) -> some View {
        HStack(spacing: 0) {
            PanelHeader("Presets")
            if isPreviewing {
                HStack(spacing: 0) {
                    Button {
                        cancelPreview()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Removes the preset and restores your edit."))
                    .accessibilityShowsLargeContentViewer()

                    Button {
                        commitPreview()
                    } label: {
                        Label("Apply", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Keeps the preset."))
                    .accessibilityShowsLargeContentViewer()
                }
                .padding(.trailing, Theme.Space.xs)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isPreviewing)
    }

    // MARK: Amount

    /// Full-width Amount slider, 0–200 % with a detent at 100 %.
    private var amountSlider: some View {
        let model = self.model
        return AdjustmentSlider("Amount",
                                value: Binding(get: { @MainActor in model.presetAmount },
                                               set: { @MainActor newValue in model.setPresetAmount(newValue) }),
                                range: EditRecipe.Limits.amount.closed,
                                defaultValue: 100)
    }

    // MARK: Strip

    private func strip(_ presets: [Preset], chip: PresetStripChip, library: PresetLibrary) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.Space.s) {
                ForEach(presets) { preset in
                    cell(preset, library: library)
                }
                saveCell
                if presets.isEmpty && chip == .mine {
                    Text("Save your edits as a preset to use them on other photos.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 180, height: PresetThumbnailCache.cellSide, alignment: .leading)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.xs)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .id(chip)      // each group starts at its first preset
    }

    private func cell(_ preset: Preset, library: PresetLibrary) -> some View {
        let isSelected = preset.id == model.activePresetID
        let isApproximate = !(preset.notes ?? []).isEmpty
        let name = preset.displayName(locale)
        return Button {
            tap(preset)
        } label: {
            PresetStripCell(preset: preset,
                            name: name,
                            isSelected: isSelected,
                            isApproximate: isApproximate,
                            isFavorite: library.favorites.contains(preset.id))
        }
        .buttonStyle(.plain)
        .contextMenu {
            menu(for: preset, library: library)
        }
        .onAppear {
            thumbnails.request(preset)
        }
        .onDisappear {
            thumbnails.cancel(preset.id)
        }
        .onChange(of: preset) { _, updated in
            thumbnails.request(updated)
        }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(isApproximate ? Text("Approximate") : Text(verbatim: ""))
        .accessibilityHint(isSelected && preset.supportsAmount
                           ? Text("Shows or hides the Amount slider.")
                           : Text("Previews the preset on the photo."))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The "+" cell: save the current edit as a preset.
    private var saveCell: some View {
        let model = self.model
        let side = PresetThumbnailCache.cellSide
        return Button {
            model.isSavePresetPresented = true
        } label: {
            VStack(spacing: Theme.Space.xs) {
                RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                    .strokeBorder(Theme.trackInactive, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: side, height: side)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                Text("Save Preset")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: side)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Saves the current edit as a new preset."))
    }

    // MARK: Context menu

    @ViewBuilder
    private func menu(for preset: Preset, library: PresetLibrary) -> some View {
        let isFavorite = library.favorites.contains(preset.id)
        Button {
            library.toggleFavorite(preset.id)
        } label: {
            if isFavorite {
                Label("Remove from Favorites", systemImage: "star.slash")
            } else {
                Label("Add to Favorites", systemImage: "star")
            }
        }
        ShareLink(item: PresetShareFileItem(preset: preset, library: library),
                  preview: SharePreview(preset.displayName(locale))) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        if let notes = preset.notes, !notes.isEmpty {
            Button {
                notesTarget = preset
                isNotesPresented = true
            } label: {
                Label("Import Notes", systemImage: "info.circle")
            }
        }
        if preset.source != .builtIn {
            Divider()
            Button(role: .destructive) {
                deleteTarget = preset
                isDeletePresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Actions

    private func tap(_ preset: Preset) {
        if preset.id == model.activePresetID {
            // Second tap on the previewed preset: show / hide Amount (VSCO / Lightroom pattern).
            guard preset.supportsAmount else { return }
            isAmountVisible.toggle()
        } else {
            model.previewPreset(preset)
            if !preset.supportsAmount { isAmountVisible = false }
            let name = preset.displayName(locale)
            AccessibilityNotification.Announcement(String(localized: "Previewing \(name)")).post()
        }
        selectionTick += 1
    }

    private func commitPreview() {
        let name = model.activePresetID.flatMap { app.presets.preset(id: $0)?.displayName(locale) }
        model.commitPreset()
        isAmountVisible = false
        selectionTick += 1
        if let name {
            AccessibilityNotification.Announcement(String(localized: "Preset \(name) applied")).post()
        }
    }

    private func cancelPreview() {
        model.cancelPreset()
        isAmountVisible = false
        selectionTick += 1
    }

    private func delete(_ preset: Preset) {
        if preset.id == model.activePresetID {
            model.cancelPreset()        // never keep a preview of a preset that no longer exists
        }
        app.presets.delete(preset.id)
    }

    // MARK: Groups

    private func chipSelection(_ selected: PresetStripChip) -> Binding<PresetStripChip> {
        Binding(
            get: { @MainActor in selected },
            set: { @MainActor chip in
                if chip == .manage {
                    isManagerPresented = true
                } else {
                    storedChipID = chip.id
                }
            }
        )
    }

    /// Favorites (if any), built-in groups in pack order, Imported (if any), Mine, Manage.
    private static func chips(for library: PresetLibrary) -> [PresetStripChip] {
        let presets = library.presets
        var chips: [PresetStripChip] = []
        if presets.contains(where: { library.favorites.contains($0.id) }) {
            chips.append(.favorites)
        }
        var seenGroups = Set<String>()
        for preset in presets where preset.source == .builtIn {
            if seenGroups.insert(preset.group).inserted {
                chips.append(.builtIn(preset.group))
            }
        }
        if presets.contains(where: { $0.source == .xmp || $0.source == .dng }) {
            chips.append(.imported)
        }
        chips.append(.mine)
        chips.append(.manage)
        return chips
    }

    /// The remembered chip when it still exists, else the first built-in group.
    private static func resolvedChip(storedID: String, among chips: [PresetStripChip]) -> PresetStripChip {
        if let stored = chips.first(where: { $0.id == storedID && $0 != .manage }) {
            return stored
        }
        if let firstGroup = chips.first(where: { $0.isBuiltInGroup }) {
            return firstGroup
        }
        return .mine
    }

    private static func presets(for chip: PresetStripChip, in library: PresetLibrary) -> [Preset] {
        switch chip {
        case .favorites:
            return library.presets.filter { library.favorites.contains($0.id) }
        case .builtIn(let group):
            return library.presets.filter { $0.source == .builtIn && $0.group == group }
        case .imported:
            return library.presets.filter { $0.source == .xmp || $0.source == .dng }
        case .mine:
            return library.presets.filter { $0.source == .user }
        case .manage:
            return []
        }
    }

    private static func chipTitle(_ chip: PresetStripChip, library: PresetLibrary, locale: Locale) -> Text {
        switch chip {
        case .favorites:
            return Text("Favorites")
        case .builtIn(let group):
            let first = library.presets.first(where: { $0.source == .builtIn && $0.group == group })
            return Text(verbatim: first?.displayGroup(locale) ?? group)
        case .imported:
            return Text("Imported")
        case .mine:
            return Text("Mine")
        case .manage:
            return Text("Manage…")
        }
    }

    // MARK: Thumbnails

    private var thumbnailContextID: PresetStripThumbnailContext {
        PresetStripThumbnailContext(projectID: model.project.id,
                                    baseline: model.presetBaseline,
                                    displayScale: displayScale)
    }
}

// MARK: - Chips

/// UserDefaults key and values for the Presets panel's remembered group chip (shared with
/// `SavePresetSheet`, which switches the panel to "Mine" after a save). Not localized.
enum PresetsPanelStorage {
    static let selectedChipKey = "noor.presets.selectedChip"
    static let mineChipID = "mine"
}

/// One chip above the strip. Built-in groups are identified by their (English) group name, which is
/// stable across languages; the chip shows the localized name.
private enum PresetStripChip: Hashable, Identifiable {
    case favorites
    case builtIn(String)
    case imported
    case mine
    case manage

    var id: String {
        switch self {
        case .favorites: return "favorites"
        case .builtIn(let group): return "builtin:" + group
        case .imported: return "imported"
        case .mine: return PresetsPanelStorage.mineChipID
        case .manage: return "manage"
        }
    }

    var isBuiltInGroup: Bool {
        if case .builtIn = self { return true }
        return false
    }
}

/// What the strip's thumbnails depend on (re-prepares the cache when it changes).
private struct PresetStripThumbnailContext: Equatable {
    var projectID: UUID
    var baseline: EditRecipe
    var displayScale: CGFloat
}

// MARK: - Cell

/// One preset in the strip: the thumbnail (fading in when it arrives), the selection ring, the "≈"
/// badge for approximated imports, a star for favourites, and the name on up to two lines.
/// Reads the shared thumbnail cache itself, so a new picture refreshes only the cells.
@MainActor
private struct PresetStripCell: View {
    let preset: Preset
    let name: String
    let isSelected: Bool
    let isApproximate: Bool
    let isFavorite: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = PresetThumbnailCache.cellSide
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
        let thumbnail = PresetThumbnailCache.shared.thumbnail(for: preset)

        VStack(spacing: Theme.Space.xs) {
            ZStack {
                shape.fill(Theme.surface2)
                if let thumbnail {
                    thumbnail.image
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .id(thumbnail.revision)
                        .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if isApproximate {
                    approximateBadge
                }
            }
            .overlay(alignment: .topLeading) {
                if isFavorite {
                    favoriteBadge
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: thumbnail?.revision)

            Text(verbatim: name)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: side)
        }
        .contentShape(Rectangle())
    }

    private var approximateBadge: some View {
        Text(verbatim: "≈")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.xs)
            .background {
                Capsule().fill(Theme.scrim)
            }
            .padding(3)
            .accessibilityHidden(true)
    }

    private var favoriteBadge: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.accent)
            .padding(3)
            .background {
                Circle().fill(Theme.scrim)
            }
            .padding(3)
            .accessibilityHidden(true)
    }
}
