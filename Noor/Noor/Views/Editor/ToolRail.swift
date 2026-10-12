import SwiftUI

/// The editor's tool rail: Presets · Crop · Light · Color · Effects · Detail.
///
/// Horizontal along the bottom on iPhone portrait, vertical on the trailing side in landscape and
/// on iPad (both mirror normally in Arabic). Tapping a tool selects it and opens its panel;
/// tapping the selected tool again hides the panel for a full-size canvas. A small dot under a
/// tool means it has edits. Leaving Presets commits the previewed preset.
@MainActor
struct ToolRail: View {
    let model: EditorModel
    let axis: Axis

    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 0) {
                    items
                }
                .padding(.horizontal, Theme.Space.xs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: Theme.Space.xs) {
                        items
                    }
                    .padding(.vertical, Theme.Space.s)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(Theme.surface1)
        .opacity(model.isInteracting ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.2), value: model.isInteracting)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .sensoryFeedback(.selection, trigger: model.selectedTool) { _, _ in hapticsEnabled }
    }

    private var items: some View {
        ForEach(EditorTool.allCases) { tool in
            item(for: tool)
        }
    }

    // MARK: Item

    private func item(for tool: EditorTool) -> some View {
        let isSelected = model.selectedTool == tool
        let isEdited = hasEdits(tool)
        return Button {
            select(tool)
        } label: {
            VStack(spacing: Theme.Space.xxs) {
                Image(systemName: tool.railSymbolName)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(tool.railTitleKey)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Circle()
                    .fill(isEdited ? (isSelected ? Theme.accent : Theme.textSecondary) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.iconInactive)
            .frame(minWidth: 52, maxWidth: axis == .horizontal ? CGFloat.infinity : 64)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(Text(tool.railTitleKey))
        .accessibilityValue(isEdited ? Text("Edited") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    // MARK: Behaviour

    private func select(_ tool: EditorTool) {
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.25)
        guard tool != model.selectedTool else {
            withAnimation(animation) {
                model.isPanelVisible.toggle()
            }
            return
        }
        if model.selectedTool == .presets {
            model.commitPreset()        // leaving Presets keeps the previewed preset (Lightroom flow)
        }
        withAnimation(animation) {
            model.selectedTool = tool
            model.isPanelVisible = true
        }
    }

    /// Whether the tool's settings differ from the defaults (drives the dot).
    private func hasEdits(_ tool: EditorTool) -> Bool {
        let recipe = model.recipe
        switch tool {
        case .presets:
            return false
        case .crop:
            return !recipe.geometry.isIdentity
        case .light:
            return recipe.hasEdits(in: .light) || recipe.hasEdits(in: .curve)
        case .color:
            return recipe.hasEdits(in: .color) || recipe.hasEdits(in: .hsl)
                || recipe.hasEdits(in: .grading) || recipe.hasEdits(in: .calibration)
        case .effects:
            return recipe.hasEdits(in: .effects)
        case .detail:
            return recipe.hasEdits(in: .detail)
        }
    }
}

// MARK: - Tool presentation

private extension EditorTool {
    /// Rail label (also the VoiceOver label).
    var railTitleKey: LocalizedStringKey {
        switch self {
        case .presets: return "Presets"
        case .crop: return "Crop"
        case .light: return "Light"
        case .color: return "Color"
        case .effects: return "Effects"
        case .detail: return "Detail"
        }
    }

    /// SF Symbol, all available on iOS 17.
    var railSymbolName: String {
        switch self {
        case .presets: return "camera.filters"
        case .crop: return "crop.rotate"
        case .light: return "sun.max"
        case .color: return "drop.halffull"
        case .effects: return "sparkles"
        case .detail: return "triangle"
        }
    }
}
