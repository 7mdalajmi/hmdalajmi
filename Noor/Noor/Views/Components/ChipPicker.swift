import SwiftUI

/// A row of segmented "chips" for picking one of a few values, styled for the editor
/// (neutral `surface2` chips; the selected one is `surface3` with a thin accent ring).
///
/// Two layouts:
/// * `fillsWidth: true` (default) – chips share the row equally, like a segmented control
///   (e.g. Adjust · Mix · Grading, or the curve channels).
/// * `fillsWidth: false` – chips keep their natural width in a horizontally scrolling row
///   (e.g. crop aspect ratios, preset groups).
///
/// The caller supplies each chip's `Text`, so labels can be localized (`Text("Original")`) or
/// verbatim (`Text(verbatim: "4:5")`). Chips mirror in RTL; selection plays a `.selection` haptic.
///
/// ```swift
/// ChipPicker(selection: $mode) { mode in Text(mode.title) }
/// ChipPicker(CropAspect.allCases, selection: $aspect, fillsWidth: false) { Text(verbatim: $0.rawValue) }
/// ```
struct ChipPicker<Item: Identifiable & Hashable>: View {
    private let items: [Item]
    @Binding private var selection: Item
    private let fillsWidth: Bool
    private let chipLabel: (Item) -> Text

    @Environment(\.noorHapticsEnabled) private var hapticsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts taps that changed the selection. The haptic follows this, not `selection`, so a
    /// selection that changes programmatically (undo, a value derived from the recipe) is silent.
    @State private var selectionTaps = 0

    init(_ items: [Item],
         selection: Binding<Item>,
         fillsWidth: Bool = true,
         label: @escaping (Item) -> Text) {
        self.items = items
        self._selection = selection
        self.fillsWidth = fillsWidth
        self.chipLabel = label
    }

    var body: some View {
        Group {
            if fillsWidth {
                HStack(spacing: Theme.Space.xs) {
                    chips
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        chips
                    }
                    .padding(.horizontal, Theme.Space.l)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sensoryFeedback(.selection, trigger: selectionTaps) { _, _ in hapticsEnabled }
    }

    private var chips: some View {
        ForEach(items) { item in
            chip(for: item)
        }
    }

    private func chip(for item: Item) -> some View {
        let isSelected = item == selection
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        return Button {
            guard item != selection else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                selection = item
            }
            selectionTaps += 1
        } label: {
            chipLabel(item)
                .font(.footnote.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil, minHeight: 32)
                .background {
                    shape.fill(isSelected ? Theme.surface3 : Theme.surface2)
                }
                .overlay {
                    shape.strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
                }
                .padding(.vertical, 6)                 // 44-pt hit target around the 32-pt chip
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - CaseIterable convenience

extension ChipPicker where Item: CaseIterable {
    /// One chip per case, in declaration order.
    init(selection: Binding<Item>,
         fillsWidth: Bool = true,
         label: @escaping (Item) -> Text) {
        self.init(Array(Item.allCases), selection: selection, fillsWidth: fillsWidth, label: label)
    }
}
