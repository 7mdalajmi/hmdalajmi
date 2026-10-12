import SwiftUI

/// The editor's 44-pt top bar:
/// back · (space) · undo · redo · compare · ••• · export.
///
/// Custom and opaque (`surface1`): no system toolbar or Liquid Glass material ever sits next to
/// the photo. It mirrors normally in Arabic (the back chevron flips with it). While a slider,
/// curve or wheel is being dragged it fades out without changing the layout (focus mode).
///
/// iPad keyboard: ⌘Z undo, ⇧⌘Z redo, `\` compare, ⌘E export.
@MainActor
struct EditorTopBar: View {
    @Bindable var model: EditorModel

    @Environment(\.dismiss) private var dismiss
    @State private var isResetAllConfirmationPresented = false

    var body: some View {
        HStack(spacing: 0) {
            EditorTopBarButton("Back", systemImage: "chevron.backward") {
                dismiss()
            }

            Spacer(minLength: Theme.Space.s)

            EditorTopBarButton("Undo", systemImage: "arrow.uturn.backward",
                               shortcut: KeyboardShortcut("z", modifiers: .command)) {
                model.undo()
            }
            .disabled(!model.canUndo)

            EditorTopBarButton("Redo", systemImage: "arrow.uturn.forward",
                               shortcut: KeyboardShortcut("z", modifiers: [.command, .shift])) {
                model.redo()
            }
            .disabled(!model.canRedo)

            EditorTopBarButton("Compare", systemImage: "square.split.2x1",
                               isOn: model.showOriginal,
                               shortcut: KeyboardShortcut("\\", modifiers: [])) {
                model.showOriginal.toggle()
            }

            moreMenu

            EditorTopBarButton("Export", systemImage: "square.and.arrow.up",
                               tint: Theme.accent,
                               shortcut: KeyboardShortcut("e", modifiers: .command)) {
                model.isExportPresented = true
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(Theme.surface1)
        .opacity(model.isInteracting ? 0 : 1)
        .allowsHitTesting(!model.isInteracting)
        .animation(.easeInOut(duration: 0.2), value: model.isInteracting)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .confirmationDialog("Reset all edits?",
                            isPresented: $isResetAllConfirmationPresented,
                            titleVisibility: .visible) {
            Button("Reset All", role: .destructive) {
                model.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: More menu

    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $model.isHistogramVisible) {
                Label("Histogram", systemImage: "chart.bar.xaxis")
            }

            Section {
                Button {
                    model.copySettings()
                } label: {
                    Label("Copy Settings", systemImage: "doc.on.doc")
                }
                Button {
                    model.pasteSettings()
                } label: {
                    Label("Paste Settings", systemImage: "doc.on.clipboard")
                }
                .disabled(!model.canPaste)
            }

            Section {
                Button {
                    model.isSavePresetPresented = true
                } label: {
                    Label("Save as Preset…", systemImage: "camera.filters")
                }
            }

            Section {
                Button(role: .destructive) {
                    isResetAllConfirmationPresented = true
                } label: {
                    Label("Reset All", systemImage: "arrow.counterclockwise")
                }
                .disabled(model.recipe.isIdentity)
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - Bar button

/// A 44 × 44-pt icon button for the top bar. The title is the VoiceOver label and the
/// Large Content Viewer text; `isOn` shows the filled symbol in accent (compare).
private struct EditorTopBarButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let isOn: Bool
    private let tint: Color
    private let shortcut: KeyboardShortcut?
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey,
         systemImage: String,
         isOn: Bool = false,
         tint: Color = Theme.textPrimary,
         shortcut: KeyboardShortcut? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.tint = tint
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        if let shortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .symbolVariant(isOn ? .fill : .none)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.textTertiary.opacity(0.5) }
        return isOn ? Theme.accent : tint
    }
}
