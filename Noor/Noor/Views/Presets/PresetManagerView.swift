import SwiftUI
import Accessibility
import UniformTypeIdentifiers
import CoreTransferable

/// The preset manager (UX spec §1.4), presented as a sheet from the Presets panel's "Manage" chip
/// (and from the library).
///
/// * One list section per preset group: the built-in pack first (pack order), then the user's own
///   and imported groups. Each row shows the name, where the preset came from, a "≈" mark when the
///   import approximated something, and a star for favourites.
/// * Swipe right to favourite. Swipe left to rename or delete (own and imported presets only;
///   built-ins are read-only). Deleting asks first, because a deleted preset file can't come back.
/// * Toolbar "Import" opens the Files picker for Lightroom `.xmp` presets, DNG presets, `.noorpreset`
///   files and whole folders; a summary sheet then lists what was imported (with the approximation
///   notes) and what failed, and why.
@MainActor
struct PresetManagerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    // Import
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var importSummary: PresetImportSummary?
    @State private var isImportErrorPresented = false
    @State private var importErrorMessage = ""

    // Row actions (the `presenting:` value is captured when the dialog opens)
    @State private var renameTarget: Preset?
    @State private var isRenamePresented = false
    @State private var renameText = ""
    @State private var deleteTarget: Preset?
    @State private var isDeletePresented = false
    @State private var notesTarget: Preset?
    @State private var isNotesPresented = false

    init() {}

    var body: some View {
        let library = app.presets
        NavigationStack {
            Group {
                if library.presets.isEmpty {
                    ContentUnavailableView("No Presets",
                                           systemImage: "camera.filters",
                                           description: Text("Import Lightroom or Noor presets to see them here."))
                } else {
                    presetList(library)
                }
            }
            .background(Theme.surface1)
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay {
                if isImporting {
                    importingOverlay
                }
            }
        }
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: UTType.noorPresetImportTypes,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                runImport(urls)
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                isImportErrorPresented = true
            }
        }
        .sheet(item: $importSummary) { summary in
            PresetImportReportView(report: summary.report)
                .environment(app)
        }
        .alert("Rename Preset", isPresented: $isRenamePresented, presenting: renameTarget) { preset in
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                library.rename(preset.id, to: renameText)
            }
        }
        .confirmationDialog("Delete Preset?", isPresented: $isDeletePresented,
                            titleVisibility: .visible, presenting: deleteTarget) { preset in
            Button("Delete", role: .destructive) {
                library.delete(preset.id)
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
        .alert("Import Failed", isPresented: $isImportErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: importErrorMessage)
        }
        .presentationBackground(Theme.surface1)
        .presentationDragIndicator(.visible)
    }

    // MARK: List

    private func presetList(_ library: PresetLibrary) -> some View {
        List {
            ForEach(Self.sections(of: library.presets, locale: locale)) { section in
                Section {
                    ForEach(section.presets) { preset in
                        row(preset, library: library)
                            .listRowBackground(Theme.surface2)
                    }
                } header: {
                    Text(verbatim: section.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ preset: Preset, library: PresetLibrary) -> some View {
        let isFavorite = library.favorites.contains(preset.id)
        let hasNotes = !(preset.notes ?? []).isEmpty
        let isEditable = preset.source != .builtIn
        return HStack(spacing: Theme.Space.m) {
            Image(systemName: Self.sourceSymbol(preset.source))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.xs) {
                    Text(verbatim: preset.displayName(locale))
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if hasNotes {
                        Text(verbatim: "≈")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel(Text("Approximate"))
                    }
                }
                Self.sourceLabel(preset.source)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text("Favorite"))
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                library.toggleFavorite(preset.id)
            } label: {
                if isFavorite {
                    Label("Remove from Favorites", systemImage: "star.slash")
                } else {
                    Label("Add to Favorites", systemImage: "star")
                }
            }
            .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isEditable {
                // Not `role: .destructive`: the row must stay until the deletion is confirmed.
                Button {
                    beginDelete(preset)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Theme.danger)
                Button {
                    beginRename(preset)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(Theme.surface3)
            }
        }
        .contextMenu {
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
            if hasNotes {
                Button {
                    notesTarget = preset
                    isNotesPresented = true
                } label: {
                    Label("Import Notes", systemImage: "info.circle")
                }
            }
            if isEditable {
                Button {
                    beginRename(preset)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    beginDelete(preset)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                dismiss()
            }
        }
    }

    private var importingOverlay: some View {
        ProgressView {
            Text("Importing…")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .tint(Theme.textSecondary)
        .padding(Theme.Space.xl)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.surface2)
        }
    }

    // MARK: Actions

    private func beginRename(_ preset: Preset) {
        renameText = preset.displayName(locale)
        renameTarget = preset
        isRenamePresented = true
    }

    private func beginDelete(_ preset: Preset) {
        deleteTarget = preset
        isDeletePresented = true
    }

    /// Imports the picked files / folders, then shows the summary.
    private func runImport(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        let library = app.presets
        Task { @MainActor in
            let report = await library.importFiles(urls)
            isImporting = false
            if !report.imported.isEmpty || !report.failures.isEmpty {
                importSummary = PresetImportSummary(report: report)
            }
            let count = report.imported.count
            AccessibilityNotification.Announcement(String(localized: "\(count) presets imported")).post()
        }
    }

    // MARK: Helpers

    /// Built-in groups first (pack order), then user / imported groups by first appearance.
    /// Built-in and user groups never merge, even when their names match.
    private static func sections(of presets: [Preset], locale: Locale) -> [PresetManagerSection] {
        var result: [PresetManagerSection] = []
        var indexByID: [String: Int] = [:]
        for preset in presets {
            let id = (preset.source == .builtIn ? "builtin:" : "user:") + preset.group
            if let index = indexByID[id] {
                result[index].presets.append(preset)
            } else {
                indexByID[id] = result.count
                result.append(PresetManagerSection(id: id, title: preset.displayGroup(locale), presets: [preset]))
            }
        }
        return result
    }

    private static func sourceSymbol(_ source: Preset.Source) -> String {
        switch source {
        case .builtIn: return "sparkles"
        case .user: return "person.crop.circle"
        case .xmp, .dng: return "square.and.arrow.down"
        }
    }

    private static func sourceLabel(_ source: Preset.Source) -> Text {
        switch source {
        case .builtIn: return Text("Built-in")
        case .user: return Text("Mine")
        case .xmp: return Text("Imported from Lightroom")
        case .dng: return Text("Imported from DNG")
        }
    }
}

// MARK: - Sections

/// One list section of the preset manager.
private struct PresetManagerSection: Identifiable {
    let id: String
    let title: String
    var presets: [Preset]
}

// MARK: - Import report

/// An import report, identifiable for `sheet(item:)`.
private struct PresetImportSummary: Identifiable {
    let id = UUID()
    let report: PresetImportReport
}

/// The summary after an import: imported presets (with the importer's notes for "≈" presets)
/// and the files that could not be imported, each with its reason.
@MainActor
private struct PresetImportReportView: View {
    let report: PresetImportReport

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {
                if !report.imported.isEmpty {
                    Section {
                        ForEach(report.imported) { preset in
                            importedRow(preset)
                                .listRowBackground(Theme.surface2)
                        }
                    } header: {
                        Text("Imported")
                    } footer: {
                        if !report.warnings.isEmpty {
                            Text("≈ Some settings have no exact match in Noor. They were approximated or left out.")
                        }
                    }
                }
                if !report.failures.isEmpty {
                    Section {
                        ForEach(Array(report.failures.enumerated()), id: \.offset) { item in
                            Label {
                                Text(verbatim: item.element)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textPrimary)
                            } icon: {
                                Image(systemName: "xmark.octagon")
                                    .foregroundStyle(Theme.danger)
                            }
                            .listRowBackground(Theme.surface2)
                        }
                    } header: {
                        Text("Not Imported")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.surface1)
            .navigationTitle("Import Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationBackground(Theme.surface1)
        .presentationDragIndicator(.visible)
    }

    private func importedRow(_ preset: Preset) -> some View {
        let warnings = report.warnings[preset.id] ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: warnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(warnings.isEmpty ? Theme.textSecondary : Theme.accent)
                    .accessibilityHidden(true)
                Text(verbatim: preset.displayName(locale))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if !warnings.isEmpty {
                    Text(verbatim: "≈")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel(Text("Approximate"))
                }
            }
            ForEach(Array(warnings.enumerated()), id: \.offset) { item in
                Text(verbatim: item.element)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, Theme.Space.xl)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sharing

/// Shares a preset as a `.noorpreset` file. The file is written by `PresetLibrary.shareURL(for:)`
/// only when the user actually shares (never while a menu is merely being built).
struct PresetShareFileItem: Transferable, Sendable {
    let preset: Preset
    let library: PresetLibrary

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .noorPreset) { item in
            let url = try await MainActor.run {
                try item.library.shareURL(for: item.preset)
            }
            return SentTransferredFile(url)
        }
    }
}
