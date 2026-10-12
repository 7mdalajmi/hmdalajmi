import SwiftUI
import UniformTypeIdentifiers

/// Noor (نور): a lossless, Lightroom-style photo editor. Originals are copied into the app byte for
/// byte and never modified; every edit is a recipe rendered from the original.
@main
struct NoorApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

// MARK: - Root

/// The navigation root: the library, with the editor pushed on top (by project id).
///
/// Files opened from other apps (Files, AirDrop, Mail, "Open in Noor") arrive through `onOpenURL`:
/// `.noorpreset` / `.xmp` go to the preset library; photos are imported and opened in the editor.
/// A `.dng` can be either (Lightroom "DNG presets" are real DNG photos), so the user chooses.
@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var app

    @State private var path: [PhotoProject.ID] = []
    @State private var pendingDNG: URL?
    @State private var presetImportSummary: OpenedPresetsSummary?

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(path: $path)
                .navigationDestination(for: PhotoProject.ID.self) { id in
                    EditorScreen(projectID: id)
                }
        }
        .onOpenURL { url in
            handleOpenedFile(url)
        }
        .confirmationDialog("Open DNG File", isPresented: isDNGChoicePresented, titleVisibility: .visible,
                            presenting: pendingDNG) { url in
            Button("Import as Photo") {
                importPhoto(url)
            }
            Button("Import as Preset") {
                importPresets(url)
            }
            Button("Cancel", role: .cancel) {
                RootView.discardInboxCopy(url)
            }
        } message: { _ in
            Text("This DNG can be edited as a photo, or its settings can be added as a preset.")
        }
        .alert(presetAlertTitle, isPresented: isPresetSummaryPresented, presenting: presetImportSummary) { _ in
            Button("OK") {}
        } message: { summary in
            Text(verbatim: summary.message)
        }
    }

    // MARK: Opened files

    /// What an opened file is, judged by its extension.
    private enum OpenedFileKind {
        case preset, photo, dng
    }

    private func handleOpenedFile(_ url: URL) {
        switch RootView.kind(of: url) {
        case .preset:
            importPresets(url)
        case .photo:
            importPhoto(url)
        case .dng:
            pendingDNG = url
        }
    }

    private static func kind(of url: URL) -> OpenedFileKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "noorpreset", "xmp":
            return .preset
        case "dng":
            return .dng
        default:
            if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
                return .photo
            }
            // Folders, JSON and anything else: the preset importer reports what it cannot use.
            return .preset
        }
    }

    /// Imports the photo, then opens it in the editor (replacing whatever was open).
    private func importPhoto(_ url: URL) {
        let library = app.library
        Task { @MainActor in
            let added = await library.importFileURLs([url])
            RootView.discardInboxCopy(url)
            // On failure, back to the library, where the import alert explains why.
            path = added.first.map { [$0.id] } ?? []
        }
    }

    private func importPresets(_ url: URL) {
        let presets = app.presets
        Task { @MainActor in
            let report = await presets.importFiles([url])
            RootView.discardInboxCopy(url)
            presetImportSummary = OpenedPresetsSummary(importedCount: report.imported.count,
                                                      failures: report.failures)
        }
    }

    /// Files sent by AirDrop or Mail are copied into `Documents/Inbox`; Noor owns those copies.
    /// Files opened in place elsewhere are never touched.
    private static func discardInboxCopy(_ url: URL) {
        let inbox = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
        let inboxPath = inbox.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        guard url.isFileURL, filePath.hasPrefix(inboxPath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Presentation state

    private var isDNGChoicePresented: Binding<Bool> {
        Binding(get: { pendingDNG != nil }, set: { if !$0 { pendingDNG = nil } })
    }

    private var isPresetSummaryPresented: Binding<Bool> {
        Binding(get: { presetImportSummary != nil }, set: { if !$0 { presetImportSummary = nil } })
    }

    private var presetAlertTitle: Text {
        if let summary = presetImportSummary, summary.importedCount == 0 {
            return Text("Couldn't Import Presets")
        }
        return Text("Presets Imported")
    }
}

// MARK: - Preset import summary

/// What the alert after opening a preset file says.
private struct OpenedPresetsSummary {
    let importedCount: Int
    let failures: [String]

    /// Localized lines: the count, then one line per failure ("file: reason").
    var message: String {
        var lines: [String] = []
        if importedCount > 0 {
            lines.append(String(localized: "\(importedCount) presets added."))
        }
        lines.append(contentsOf: failures)
        if lines.isEmpty {
            lines.append(String(localized: "No presets were found in this file."))
        }
        return lines.joined(separator: "\n")
    }
}
