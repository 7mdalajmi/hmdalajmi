import SwiftUI

/// The navigation destination for one photo: opens the original, builds the `EditorModel` and
/// shows `EditorView`.
///
/// `PhotoDocument` creation only inspects metadata; it runs on a detached task, off the main
/// thread (`LibraryStore.document(for:)` is nonisolated). A spinner
/// appears only if opening takes longer than 300 ms; a failure shows a friendly explanation with a
/// way back. Leaving the screen closes the model (save, stop rendering, purge caches); the model
/// itself saves when the app goes to the background.
struct EditorScreen: View {
    let projectID: PhotoProject.ID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var model: EditorModel? = nil
    @State private var failure: LoadFailure? = nil
    @State private var showsSpinner = false

    /// Why a photo could not be opened.
    private enum LoadFailure {
        case missing, unsupported, unreadable

        var message: LocalizedStringKey {
            switch self {
            case .missing:
                return "This photo is no longer in your library."
            case .unsupported:
                return "Noor can't read this file format."
            case .unreadable:
                return "The original file couldn't be read. It may be damaged or still downloading."
            }
        }
    }

    var body: some View {
        Group {
            if let model {
                EditorView(model: model)
            } else if let failure {
                failureView(failure)
            } else {
                loadingView
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: projectID) {
            await loadIfNeeded()
        }
        .onDisappear {
            // Save, stop rendering and purge. Dropping the closed model means that if this screen
            // ever reappears (e.g. a cancelled back swipe), `.task` reopens the photo instead of
            // leaving a closed, inert editor on screen.
            model?.close()
            model = nil
        }
    }

    // MARK: Loading

    @MainActor
    private func loadIfNeeded() async {
        guard model == nil, failure == nil else { return }
        guard let project = app.library.projects.first(where: { $0.id == projectID }) else {
            failure = .missing
            return
        }
        let library = app.library
        do {
            // Read-only metadata inspection (file IO); never modifies the original. `document(for:)`
            // is nonisolated and synchronous, so it runs entirely on this background task.
            let document = try await Task.detached(priority: .userInitiated) {
                try library.document(for: project)
            }.value
            guard !Task.isCancelled else { return }
            model = EditorModel(project: project, document: document, library: library, presets: app.presets)
        } catch {
            guard !Task.isCancelled else { return }
            if let documentError = error as? PhotoDocumentError, documentError == .unsupported {
                failure = .unsupported
            } else {
                failure = .unreadable
            }
        }
    }

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: 0) {
            backBar
            ZStack {
                Theme.surround(app.settings.surround)
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.textSecondary)
                    .opacity(showsSpinner ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface1)
        .environment(\.colorScheme, .dark)
        .task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeIn(duration: 0.2)) { showsSpinner = true }
            } catch {
                // Cancelled: the photo opened (or the user left) before the spinner was needed.
            }
        }
    }

    private func failureView(_ failure: LoadFailure) -> some View {
        VStack(spacing: 0) {
            backBar
            ContentUnavailableView {
                Label("Can't Open Photo", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.message)
            } actions: {
                Button {
                    dismiss()
                } label: {
                    Text("Back to Library")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface1)
        .environment(\.colorScheme, .dark)
    }

    /// Minimal top bar with a back button while the editor itself is not on screen
    /// (the navigation bar stays hidden so the transition into the editor never jumps).
    private var backBar: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityShowsLargeContentViewer()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: 44)
    }
}
