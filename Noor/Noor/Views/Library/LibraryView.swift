import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers

/// The library: a grid of every photo in Noor, newest first, each shown through its current recipe.
///
/// Import (toolbar "+" menu or the empty state) brings originals in byte for byte: from Photos with
/// `preferredItemEncoding: .current` (no HEIC → JPEG transcode, ProRAW stays DNG, HDR survives), and
/// from Files with a security-scoped copy. Tapping a photo opens the editor; the context menu edits,
/// duplicates, resets or removes it. Removing only deletes Noor's copy, never the Photos original.
@MainActor
struct LibraryView: View {
    @Binding var path: [PhotoProject.ID]

    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isPhotosPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isPresetsPresented = false
    @State private var isSettingsPresented = false
    @State private var pendingAction: PendingAction?

    /// Most photos one picker session may add.
    private static let maxPickerSelection = 100
    private static let gridSpacing: CGFloat = 2

    /// A destructive library action waiting for confirmation.
    private enum PendingAction {
        case reset(PhotoProject)
        case remove(PhotoProject)
    }

    // The modifier chain is split into three stages to keep each expression quick to type-check.
    var body: some View {
        chrome
            .sheet(isPresented: $isPresetsPresented) {
                PresetManagerView()
                    .environment(app)
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
                    .environment(app)
            }
            .confirmationDialog(confirmationTitle, isPresented: isConfirmationPresented,
                                titleVisibility: .visible, presenting: pendingAction) { action in
                switch action {
                case .reset(let project):
                    Button("Reset Edits", role: .destructive) {
                        app.library.resetEdits(project)
                    }
                case .remove(let project):
                    Button("Remove from Noor", role: .destructive) {
                        app.library.remove(project)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                switch action {
                case .reset:
                    Text("All edits are removed. The original is unchanged.")
                case .remove:
                    Text("Noor's copy and its edits are deleted. The photo in Photos or Files is not affected.")
                }
            }
            .alert("Some Photos Couldn't Be Added", isPresented: isImportAlertPresented) {
                Button("OK") {
                    app.library.clearImportErrors()
                }
            } message: {
                Text(verbatim: app.library.importErrors.joined(separator: "\n"))
            }
            .sensoryFeedback(.success, trigger: app.library.isImporting) { wasImporting, isImporting in
                importSucceeded(wasImporting: wasImporting, isImporting: isImporting)
            }
    }

    /// Background, title, toolbar and the import progress capsule.
    private var chrome: some View {
        importers
            .background(Theme.canvas)
            .navigationTitle("Library")
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if app.library.isImporting {
                    importProgress
                }
            }
            .animation(.easeInOut(duration: 0.2), value: app.library.isImporting)
    }

    /// The content with the Photos and Files pickers attached.
    private var importers: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .photosPicker(isPresented: $isPhotosPickerPresented,
                          selection: $pickerItems,
                          maxSelectionCount: LibraryView.maxPickerSelection,
                          selectionBehavior: .ordered,
                          matching: .images,
                          preferredItemEncoding: .current,
                          photoLibrary: .shared())
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                pickerItems = []
                let library = app.library
                Task { await library.importPhotos(items) }
            }
            .fileImporter(isPresented: $isFileImporterPresented,
                          allowedContentTypes: [.rawImage, .image],
                          allowsMultipleSelection: true) { result in
                handleFileImport(result)
            }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !app.library.isLoaded {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.textSecondary)
        } else if app.library.projects.isEmpty && !app.library.isImporting {
            emptyState
        } else {
            grid
        }
    }

    private var columns: [GridItem] {
        let minimum: CGFloat = horizontalSizeClass == .regular ? 160 : 110
        return [GridItem(.adaptive(minimum: minimum), spacing: LibraryView.gridSpacing)]
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: LibraryView.gridSpacing) {
                ForEach(app.library.projects) { project in
                    NavigationLink(value: project.id) {
                        LibraryCell(project: project)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the photo in the editor."))
                    .contextMenu {
                        contextMenuItems(for: project)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for project: PhotoProject) -> some View {
        Button {
            path.append(project.id)
        } label: {
            Label("Edit", systemImage: "slider.horizontal.3")
        }
        Button {
            app.library.duplicate(project)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            pendingAction = .reset(project)
        } label: {
            Label("Reset Edits", systemImage: "arrow.counterclockwise")
        }
        .disabled(!project.isEdited)
        Divider()
        Button(role: .destructive) {
            pendingAction = .remove(project)
        } label: {
            Label("Remove from Noor", systemImage: "trash")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Photos Yet", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Import photos to start editing. Noor edits a copy and never changes your originals.")
        } actions: {
            Button {
                isPhotosPickerPresented = true
            } label: {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Import from Files", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
    }

    /// "Importing 3 of 10…" while a batch runs.
    private var importProgress: some View {
        let library = app.library
        let total = max(library.importTotal, 1)
        let current = min(library.importCompleted + 1, total)
        return HStack(spacing: Theme.Space.m) {
            ProgressView()
                .tint(Theme.textSecondary)
            Text("Importing \(current) of \(total)…")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.surface2, in: Capsule())
        .padding(.bottom, Theme.Space.s)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isSettingsPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresetsPresented = true
            } label: {
                Label("Presets", systemImage: "camera.filters")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            // The pickers are presented by modifiers: a PhotosPicker inside a Menu is unreliable.
            Menu {
                Button {
                    isPhotosPickerPresented = true
                } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
            } label: {
                Label("Import", systemImage: "plus")
            }
        }
    }

    // MARK: Actions

    /// A success tap when an import batch finishes cleanly (and haptics are on).
    private func importSucceeded(wasImporting: Bool, isImporting: Bool) -> Bool {
        wasImporting && !isImporting && app.settings.haptics && app.library.importErrors.isEmpty
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let library = app.library
            Task { await library.importFiles(urls) }
        case .failure(let error):
            if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return }
            app.library.reportImportError(error.localizedDescription)
        }
    }

    // MARK: Presentation state

    private var isConfirmationPresented: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }

    private var confirmationTitle: Text {
        switch pendingAction {
        case .reset(let project)?:
            return Text("Reset edits to “\(project.displayName)”?")
        case .remove(let project)?:
            return Text("Remove “\(project.displayName)” from Noor?")
        case nil:
            return Text(verbatim: "")
        }
    }

    private var isImportAlertPresented: Binding<Bool> {
        Binding(get: { !app.library.importErrors.isEmpty && !app.library.isImporting },
                set: { if !$0 { app.library.clearImportErrors() } })
    }
}
