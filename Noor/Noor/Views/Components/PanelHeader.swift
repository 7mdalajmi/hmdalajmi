import SwiftUI

/// The header row at the top of every editor panel: the panel title at the reading-start edge and
/// an optional reset button at the reading-end edge.
///
/// Apply `.disabled(_:)` to grey out the reset button when the panel has nothing to reset
/// (the title is unaffected). Resets are undoable in the model, so there is no confirmation.
struct PanelHeader: View {
    private let title: LocalizedStringKey
    private let onReset: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @State private var resetCount = 0

    init(_ title: LocalizedStringKey, onReset: (() -> Void)? = nil) {
        self.title = title
        self.onReset = onReset
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.s)
            if let onReset {
                Button {
                    onReset()
                    resetCount += 1
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isEnabled ? Theme.textSecondary : Theme.textTertiary.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, onReset == nil ? Theme.Space.l : Theme.Space.xs)
        .frame(minHeight: 44)
        .sensoryFeedback(.selection, trigger: resetCount) { _, _ in hapticsEnabled }
    }
}

// MARK: - Group separator

extension PanelHeader {
    /// A quiet hairline that separates groups of sliders inside a panel
    /// (for example Texture/Clarity/Dehaze from the vignette sliders).
    struct GroupSeparator: View {
        init() {}

        var body: some View {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.vertical, Theme.Space.s)
                .accessibilityHidden(true)
        }
    }
}
