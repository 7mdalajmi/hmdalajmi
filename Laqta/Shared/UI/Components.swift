//
//  Components.swift
//  Laqta — Shared
//
//  Buttons, chips, cards and small pieces of the Noir/Ivory language.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Press feedback

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Buttons

/// 44 pt round button with a gold outline (header, viewer chrome).
struct CircleIcon: View {
    let systemImage: String
    var size: CGFloat = 44
    var showsDot: Bool = false
    var glass: Bool = false

    @Environment(\.laqta) private var palette

    var body: some View {
        Image(systemName: systemImage)
            .laqtaIconFont(size * 0.4, weight: .medium)
            .foregroundStyle(palette.goldHi)
            .frame(width: size, height: size)
            .background {
                if glass {
                    Circle().fill(.clear).laqtaGlass(in: Circle())
                } else {
                    Circle().fill(palette.buttonFill)
                    Circle().strokeBorder(palette.buttonBorder, lineWidth: 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsDot {
                    Circle()
                        .fill(palette.goldHi)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(palette.bg, lineWidth: 2))
                        .offset(x: -9, y: 9)
                }
            }
            .contentShape(Circle())
    }
}

struct LaqtaButtonLabel: View {
    enum Kind {
        case gold
        case line
        case soft
    }

    let text: Text
    var systemImage: String?
    var kind: Kind = .gold
    var small: Bool = false
    var fullWidth: Bool = false

    @Environment(\.laqta) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.laqtaButtonsFillWidth) private var fillsWidth

    init(_ title: LocalizedStringKey, systemImage: String? = nil, kind: Kind = .gold, small: Bool = false, fullWidth: Bool = false) {
        self.text = Text(title)
        self.systemImage = systemImage
        self.kind = kind
        self.small = small
        self.fullWidth = fullWidth
    }

    init(verbatim title: String, systemImage: String? = nil, kind: Kind = .gold, small: Bool = false, fullWidth: Bool = false) {
        self.text = Text(verbatim: title)
        self.systemImage = systemImage
        self.kind = kind
        self.small = small
        self.fullWidth = fullWidth
    }

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .laqtaIconFont(small ? 13 : 14, weight: .semibold)
            }
            text
                .laqtaFont(small ? 14 : 15, weight: .semibold)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, small ? 14 : 18)
        .padding(.vertical, 6)
        .frame(minHeight: small ? 36 : 44)
        .frame(maxWidth: fullWidth || fillsWidth ? .infinity : nil)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .overlay {
            switch kind {
            case .gold: EmptyView()
            case .line: Capsule().strokeBorder(palette.buttonBorder, lineWidth: 1)
            case .soft: Capsule().strokeBorder(palette.line, lineWidth: 1)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .gold: palette.goldInk
        case .line: palette.goldHi
        case .soft: palette.ink
        }
    }

    private var background: Color {
        switch kind {
        case .gold: palette.accentFill
        case .line: .clear
        case .soft: palette.field
        }
    }
}

extension EnvironmentValues {
    /// Set by `AdaptiveButtonRow` when its buttons are stacked.
    @Entry var laqtaButtonsFillWidth: Bool = false
}

/// Buttons side by side, or one above the other when the text is too large to fit.
struct AdaptiveButtonRow<Content: View>: View {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: alignment, spacing: spacing) {
                content
            }
            .environment(\.laqtaButtonsFillWidth, true)
        }
    }
}

/// 44 pt circle with an outline, used next to text buttons ("Move", "Delete", "Copy").
struct OutlineIconButtonLabel: View {
    let systemImage: String
    var size: CGFloat = 44

    @Environment(\.laqta) private var palette

    var body: some View {
        Image(systemName: systemImage)
            .laqtaIconFont(16, weight: .medium)
            .foregroundStyle(palette.goldHi)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(palette.buttonBorder, lineWidth: 1))
            .contentShape(Circle())
    }
}

// MARK: - Labels

struct SectionLabel<Trailing: View>: View {
    let title: Text
    var trailing: Trailing

    @Environment(\.laqta) private var palette

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.trailing = trailing()
    }

    init(verbatim title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            title
                .textCase(.uppercase)
                .laqtaFont(12, weight: .semibold)
                .tracking(0.96)
                .foregroundStyle(palette.gold)
                .adaptiveLineLimit(1, accessibility: 2)
                // Keeps its full width next to the hairline, but never pushes the row off screen.
                .layoutPriority(1)
            Rectangle()
                .fill(palette.hair)
                .frame(height: 1)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }

    init(verbatim title: String) {
        self.init(verbatim: title) { EmptyView() }
    }
}

struct CardHeader<Trailing: View>: View {
    let title: Text
    let systemImage: String
    var trailing: Trailing

    @Environment(\.laqta) private var palette

    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    init(verbatim title: String, systemImage: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .laqtaIconFont(13, weight: .semibold)
                .foregroundStyle(palette.goldHi)
            title
                .textCase(.uppercase)
                .laqtaFont(12, weight: .semibold)
                .tracking(0.96)
                .foregroundStyle(palette.gold)
                .adaptiveLineLimit(1, accessibility: 2)
                .layoutPriority(1)
            Rectangle()
                .fill(palette.hair)
                .frame(height: 1)
            trailing
        }
        .padding(.bottom, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }

    init(verbatim title: String, systemImage: String) {
        self.init(verbatim: title, systemImage: systemImage) { EmptyView() }
    }
}


/// Arabic folder name, left aligned, in Amiri.
struct FolderNameText: View {
    let name: String
    var size: CGFloat = 28
    var color: Color?
    /// Caps how far the name grows with the text size, for names inside bars that keep their height.
    var maxScale: CGFloat?

    @Environment(\.laqta) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(verbatim: name)
            .font(font)
            .foregroundStyle(color ?? palette.ink)
            .lineLimit(maxScale == nil && dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .truncationMode(.tail)
    }

    private var font: Font {
        guard let maxScale else { return LaqtaFont.arabic(size) }
        let scaled = LaqtaType.scaled(size, style: .title, dynamicTypeSize: dynamicTypeSize, maxScale: maxScale)
        return LaqtaFont.arabic(fixedSize: scaled)
    }
}

// MARK: - Cards

struct LaqtaCard<Content: View>: View {
    var padding: CGFloat = 16
    var content: Content

    @Environment(\.laqta) private var palette

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }
}

/// Grouped settings-style container.
struct LaqtaGroup<Content: View>: View {
    var content: Content

    @Environment(\.laqta) private var palette

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.sheet2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }
}

struct RowIcon: View {
    let systemImage: String
    @Environment(\.laqta) private var palette

    var body: some View {
        Image(systemName: systemImage)
            .laqtaIconFont(14, weight: .medium)
            .foregroundStyle(palette.goldHi)
            .frame(width: 32, height: 32)
            .background(palette.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct RowText: View {
    let title: Text
    var subtitle: Text?

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .laqtaFont(15, weight: .medium)
                .foregroundStyle(palette.ink)
            if let subtitle {
                subtitle
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SwitchRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                RowIcon(systemImage: systemImage)
                RowText(title: Text(title), subtitle: subtitle.map { Text($0) })
            }
        }
        .frame(minHeight: 56)
    }
}

struct RowSeparator: View {
    var inset: CGFloat = 44
    @Environment(\.laqta) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.line)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Chips

struct FilterChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    let count: Int
    let isOn: Bool

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .laqtaIconFont(12, weight: .semibold)
            Text(title)
            Text(count, format: .number)
                .opacity(0.6)
        }
        .laqtaFont(13, weight: .medium)
        .padding(.horizontal, 13)
        .frame(minHeight: 34)
        .foregroundStyle(isOn ? palette.goldInk : palette.ink)
        .background(isOn ? palette.accentFill : palette.field, in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? Color.clear : palette.line, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// 24 pt tag ("Boarding pass", "KWI to LHR").
struct TagChip: View {
    let text: String
    var systemImage: String?
    /// The larger size used for search suggestions.
    var large = false

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: large ? 6 : 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .laqtaIconFont(large ? 11 : 10, weight: .semibold)
            }
            Text(verbatim: text)
                .lineLimit(1)
        }
        .laqtaFont(large ? 13.5 : 12, weight: .medium)
        .padding(.horizontal, large ? 11 : 9)
        .padding(.vertical, 3)
        .frame(minHeight: large ? 30 : 24)
        .foregroundStyle(palette.ink)
        .background(palette.field, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
    }
}

/// 32 pt tappable entity ("Fri 2 Oct, 8:05 PM", "38.000 KWD").
struct EntityChipLabel: View {
    let text: String
    let systemImage: String
    var done: Bool = false

    @Environment(\.laqta) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark" : systemImage)
                .laqtaIconFont(12, weight: .semibold)
            Text(verbatim: text)
                .lineLimit(1)
        }
        .laqtaFont(13, weight: .medium)
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .foregroundStyle(palette.ink)
        .background(palette.hit, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Intelligence pieces

struct AIBadge: View {
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: "sparkles")
            .laqtaIconFont(size * 0.42, weight: .semibold)
            .foregroundStyle(LaqtaPalette.aiInk)
            .frame(width: size, height: size)
            .background(LaqtaPalette.aiGradient, in: Circle())
            .accessibilityHidden(true)
    }
}

struct BulletList: View {
    let items: [String]
    var reveal: Bool = false

    @Environment(\.laqta) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(palette.goldHi)
                        .frame(width: 6, height: 6)
                        .padding(.top, 8)
                    TypingText(text: item, animate: reveal, delay: Double(index) * 0.35)
                        .laqtaFont(14)
                        .lineSpacing(3)
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Reveals text like it is being written, without moving the layout.
struct TypingText: View {
    let text: String
    var animate: Bool = true
    var delay: Double = 0

    @State private var shown: Int = 0
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: text) {
                guard animate, !reduceMotion else {
                    finished = true
                    return
                }
                finished = false
                shown = 0
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                let count = text.count
                let step = max(1, count / 90)
                var index = 0
                while index < count {
                    index = min(count, index + step)
                    shown = index
                    try? await Task.sleep(for: .milliseconds(14))
                    if Task.isCancelled { break }
                }
                finished = true
            }
    }

    private var attributed: AttributedString {
        var value = AttributedString(text)
        guard animate, !finished, !reduceMotion else { return value }
        let visible = min(shown, text.count)
        let start = value.index(value.startIndex, offsetByCharacters: visible)
        if start < value.endIndex {
            value[start..<value.endIndex].foregroundColor = Color.clear
        }
        return value
    }
}

struct ThinkingDots: View {
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    let phase = sin((time - Double(index) * 0.15) * .pi * 2)
                    Circle()
                        .fill(palette.ink2)
                        .frame(width: 6, height: 6)
                        .opacity(0.25 + 0.75 * max(0, phase))
                        // With Reduce Motion the dots only fade.
                        .offset(y: reduceMotion ? 0 : -2 * max(0, phase))
                }
            }
            .frame(height: 18)
        }
        .accessibilityLabel(Text("Thinking"))
    }
}

struct ShimmerLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: palette.field, location: 0),
                            .init(color: palette.shimmer, location: 0.5),
                            .init(color: palette.field, location: 1)
                        ],
                        startPoint: UnitPoint(x: -1 + progress * 2, y: 0.5),
                        endPoint: UnitPoint(x: progress * 2, y: 0.5)
                    )
                )
                .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Glass

private struct LaqtaGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var interactive: Bool

    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var increasedContrast: Bool { contrast == .increased }

    func body(content: Content) -> some View {
        glass(content)
            .overlay(
                shape
                    .stroke(increasedContrast ? palette.ink3 : palette.glassBorder, lineWidth: increasedContrast ? 1 : 0.75)
                    .allowsHitTesting(false)
            )
            .shadow(color: palette.shadow.opacity(0.6), radius: 15, y: 8)
    }

    /// Reduce Transparency swaps the glass for a solid surface, so text over photos stays readable.
    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(palette.sheet2, in: shape)
        } else {
            content.glassEffect(interactive ? Glass.regular.tint(palette.glass).interactive() : Glass.regular.tint(palette.glass), in: shape)
        }
    }
}

extension View {
    func laqtaGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(LaqtaGlassModifier(shape: shape, interactive: interactive))
    }

    /// Floating bars keep their size at large text sizes; a long press shows the control's name
    /// and symbol in the Large Content Viewer instead.
    func largeContentLabel(_ title: Text, systemImage: String) -> some View {
        accessibilityShowsLargeContentViewer {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

// MARK: - Toasts

@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let systemImage: String
        var actionTitle: String?

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Toast?
    @ObservationIgnored private var action: (() -> Void)?

    /// Shows a short message. With an action ("Undo"), the message stays a little longer.
    func show(_ text: String, systemImage: String = "checkmark", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let toast = Toast(text: text, systemImage: systemImage, actionTitle: action == nil ? nil : actionTitle)
        self.action = action
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            current = toast
        }
        AccessibilityNotification.Announcement(text).post()
        let duration: Double = action == nil ? 2.8 : 5
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, self.current?.id == toast.id else { return }
            self.dismiss()
        }
    }

    func performAction() {
        let action = self.action
        dismiss()
        action?()
    }

    func dismiss() {
        action = nil
        withAnimation(.easeOut(duration: 0.25)) {
            current = nil
        }
    }
}

private struct ToastHostModifier: ViewModifier {
    let center: ToastCenter
    @Environment(\.laqta) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = center.current {
                    HStack(spacing: 8) {
                        Image(systemName: toast.systemImage)
                            .laqtaIconFont(13, weight: .bold)
                            .foregroundStyle(palette.goldHi)
                            .accessibilityHidden(true)
                        Text(verbatim: toast.text)
                            .laqtaFont(14)
                            .foregroundStyle(palette.ink)
                            .multilineTextAlignment(.leading)
                        if let actionTitle = toast.actionTitle {
                            Spacer(minLength: 4)
                            Button {
                                center.performAction()
                            } label: {
                                Text(verbatim: actionTitle)
                                    .laqtaFont(14, weight: .semibold)
                                    .foregroundStyle(palette.goldInk)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 30)
                                    .background(palette.accentFill, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, toast.actionTitle == nil ? 16 : 8)
                    .padding(.vertical, toast.actionTitle == nil ? 11 : 7)
                    .laqtaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .accessibilityElement(children: .contain)
                }
            }
    }
}

extension View {
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}

// MARK: - Sheet chrome

/// "Cancel · Title · Action" bar used by Laqta sheets.
struct SheetBar<Leading: View, Trailing: View>: View {
    let title: Text
    var leading: Leading
    var trailing: Trailing

    @Environment(\.laqta) private var palette

    init(_ title: LocalizedStringKey, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            title
                .laqtaFont(17, weight: .semibold)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            HStack {
                leading
                Spacer(minLength: 0)
                trailing
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// Plain text button in the sheet bar ("Cancel", "Create").
struct BarTextButtonLabel: View {
    let title: LocalizedStringKey
    var prominent: Bool = false
    @Environment(\.laqta) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(title)
            .laqtaFont(17, weight: prominent ? .semibold : .regular)
            .foregroundStyle(prominent ? palette.goldHi : palette.ink2)
            .opacity(isEnabled ? 1 : 0.4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
