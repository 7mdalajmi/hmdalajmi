import SwiftUI

/// The editor shell. Lays out the top bar, the canvas (or the crop workspace), the selected tool's
/// panel and the tool rail, and presents the export and save-preset sheets.
///
/// * iPhone portrait: top bar / canvas / panel (about a third of the height, hidden when the
///   selected tool is tapped again) / horizontal rail.
/// * iPhone landscape and iPad (regular width): top bar over canvas | panel (340 pt) | vertical
///   rail. The panel and rail sit on the trailing side, which is the left in Arabic.
///
/// The editor is always dark and opaque: the photo sits on the user's neutral surround
/// (`Theme.surround`), the chrome on `surface1`, and no material or blur ever touches the photo.
/// Focus mode: while a control is dragged the top bar fades out, the rail dims and the other
/// slider rows fade; the histogram stays visible.
@MainActor
struct EditorView: View {
    @Bindable var model: EditorModel

    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Set by a panel that needs more room (the tone curve) through `noorPanelPrefersTall`.
    @State private var panelPrefersTall = false

    /// Canvas | panel | rail when there is room for it side by side.
    private var usesSideLayout: Bool {
        horizontalSizeClass == .regular || verticalSizeClass == .compact
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if usesSideLayout {
                    sideBySideLayout
                } else {
                    stackedLayout(availableHeight: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.surface1)
        .environment(\.colorScheme, .dark)
        .environment(\.noorHapticsEnabled, app.settings.haptics)
        .environment(\.noorEditorIsInteracting, model.isInteracting)
        .environment(\.noorPanelPrefersTall, $panelPrefersTall)
        .toolbar(.hidden, for: .navigationBar)
        .persistentSystemOverlays(model.isInteracting ? .hidden : .automatic)
        // Sheet content is not inside the `.environment` modifiers above, so each sheet gets the
        // app model and the haptics setting explicitly.
        .sheet(isPresented: $model.isExportPresented) {
            ExportSheet(model: model)
                .environment(app)
                .environment(\.noorHapticsEnabled, app.settings.haptics)
        }
        .sheet(isPresented: $model.isSavePresetPresented) {
            SavePresetSheet(model: model)
                .environment(app)
                .environment(\.noorHapticsEnabled, app.settings.haptics)
        }
    }

    // MARK: Layouts

    /// iPhone portrait.
    private func stackedLayout(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            EditorTopBar(model: model)
            EditorWorkspace(model: model)
            if model.isPanelVisible {
                EditorPanelHost(model: model)
                    .frame(height: Self.panelHeight(for: availableHeight, tall: panelPrefersTall))
                    .transition(.opacity)
            }
            ToolRail(model: model, axis: .horizontal)
                .frame(height: 64)
        }
    }

    /// iPhone landscape and iPad.
    private var sideBySideLayout: some View {
        VStack(spacing: 0) {
            EditorTopBar(model: model)
            HStack(spacing: 0) {
                EditorWorkspace(model: model)
                if model.isPanelVisible {
                    EditorPanelHost(model: model)
                        .frame(width: 340)
                        .transition(.opacity)
                }
                ToolRail(model: model, axis: .vertical)
                    .frame(width: 72)
            }
        }
    }

    /// About a third of the safe height, so the photo keeps well over half the screen. A panel
    /// with a large graph (the tone curve) gets about half the height while it is shown.
    private static func panelHeight(for availableHeight: CGFloat, tall: Bool) -> CGFloat {
        if tall {
            return min(max(availableHeight * 0.5, 300), 440)
        }
        return min(max(availableHeight * 0.36, 230), 300)
    }
}

// MARK: - Workspace (canvas or crop)

/// The photo area: the neutral surround, then the live canvas with its overlays, or the crop
/// workspace while the Crop tool is selected. Kept as its own view so that histogram updates
/// (about 10 Hz) re-render only the overlay, not the whole editor.
@MainActor
private struct EditorWorkspace: View {
    let model: EditorModel

    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Theme.surround(app.settings.surround)
            if model.selectedTool == .crop {
                CropWorkspace(model: model)
            } else {
                PhotoCanvas(model: model)
                EditorCanvasOverlay(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// Badges drawn over the live photo: the histogram (top-left, always LTR) and the "Before"
/// capsule while the original is shown. Never intercepts touches meant for the canvas.
@MainActor
private struct EditorCanvasOverlay: View {
    let model: EditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.isHistogramVisible {
                HistogramView(histogram: model.histogram)
                    .padding(Theme.Space.s)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if showsBefore {
                beforeBadge
                    .padding(.top, Theme.Space.s)
                    .transition(.opacity)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsBefore)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isHistogramVisible)
    }

    /// The sticky compare toggle, or press-and-hold on the photo.
    private var showsBefore: Bool {
        model.showOriginal || model.isPressingOriginal
    }

    private var beforeBadge: some View {
        Text("Before")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xs)
            .background {
                Capsule().fill(Theme.scrim)
            }
    }
}

// MARK: - Panel host

/// The selected tool's panel on `surface1`. Each panel brings its own header and scrolling.
@MainActor
private struct EditorPanelHost: View {
    let model: EditorModel

    var body: some View {
        Group {
            switch model.selectedTool {
            case .presets:
                PresetsPanel(model: model)
            case .crop:
                CropPanel(model: model)
            case .light:
                LightPanel(model: model)
            case .color:
                ColorPanel(model: model)
            case .effects:
                EffectsPanel(model: model)
            case .detail:
                DetailPanel(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface1)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

// MARK: - Panel height request

/// Backing key for `EnvironmentValues.noorPanelPrefersTall`.
private struct NoorPanelPrefersTallKey: EnvironmentKey {
    static var defaultValue: Binding<Bool> { .constant(false) }
}

extension EnvironmentValues {
    /// Provided by `EditorView`. A panel that shows a large graph (the Light panel's tone curve)
    /// sets it to `true` to get a taller panel in iPhone portrait, and back to `false` when it
    /// leaves. Outside the editor it is a constant `false`.
    var noorPanelPrefersTall: Binding<Bool> {
        get { self[NoorPanelPrefersTallKey.self] }
        set { self[NoorPanelPrefersTallKey.self] = newValue }
    }
}
