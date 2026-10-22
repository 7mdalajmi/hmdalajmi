//
//  ScaledFont.swift
//  Laqta — Shared
//
//  Laqta's type sizes follow the reader's text size setting (Dynamic Type):
//  each size scales with the text style closest to it.
//

import SwiftUI
import UIKit

nonisolated enum LaqtaType {
    /// The text style a size scales with.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<13.5: .footnote
        case ..<15.5: .subheadline
        case ..<17.5: .body
        case ..<20.5: .title3
        case ..<24: .title2
        case ..<30: .title
        default: .largeTitle
        }
    }

    static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }

    /// `size` at the reader's text size, never smaller than designed and at most `maxScale` times larger.
    static func scaled(_ size: CGFloat, style: Font.TextStyle, dynamicTypeSize: DynamicTypeSize, maxScale: CGFloat?) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle(style))
        var value = metrics.scaledValue(for: size, compatibleWith: traits)
        if let maxScale {
            value = min(value, size * maxScale)
        }
        return max(value, size * 0.82).rounded(toPlaces: 1)
    }
}

private extension CGFloat {
    nonisolated func rounded(toPlaces places: Int) -> CGFloat {
        let factor = CGFloat(pow(10, Double(places)))
        return (self * factor).rounded() / factor
    }
}

private struct ScaledSystemFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    let style: Font.TextStyle?
    let monospacedDigit: Bool
    let maxScale: CGFloat?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let scaledSize = LaqtaType.scaled(
            size,
            style: style ?? LaqtaType.textStyle(for: size),
            dynamicTypeSize: dynamicTypeSize,
            maxScale: maxScale
        )
        var font = Font.system(size: scaledSize, weight: weight, design: design)
        if monospacedDigit {
            font = font.monospacedDigit()
        }
        return content.font(font)
    }
}

private struct AdaptiveLineLimit: ViewModifier {
    let regular: Int
    let accessibility: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.lineLimit(dynamicTypeSize.isAccessibilitySize ? accessibility : regular)
    }
}

private struct ScaledDisplayFont: ViewModifier {
    let size: CGFloat
    let bold: Bool
    let maxScale: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let scaledSize = LaqtaType.scaled(size, style: .largeTitle, dynamicTypeSize: dynamicTypeSize, maxScale: maxScale)
        return content.font(LaqtaFont.display(fixedSize: scaledSize, bold: bold))
    }
}

extension View {
    /// `regular` lines at standard text sizes; more room (or no limit) at accessibility sizes,
    /// so large text wraps instead of being cut off.
    func adaptiveLineLimit(_ regular: Int, accessibility: Int? = nil) -> some View {
        modifier(AdaptiveLineLimit(regular: regular, accessibility: accessibility))
    }

    /// Cormorant Garamond titles: they grow with the text size, up to `maxScale` times the design size.
    func laqtaDisplayFont(_ size: CGFloat, bold: Bool = false, maxScale: CGFloat = 1.35) -> some View {
        modifier(ScaledDisplayFont(size: size, bold: bold, maxScale: maxScale))
    }

    /// A system font at `size` that grows and shrinks with the reader's text size.
    func laqtaFont(
        _ size: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design? = nil,
        relativeTo style: Font.TextStyle? = nil,
        monospacedDigit: Bool = false,
        maxScale: CGFloat? = nil
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, style: style, monospacedDigit: monospacedDigit, maxScale: maxScale))
    }

    /// Symbols inside fixed shapes grow a little with the text size, so they never spill out.
    func laqtaIconFont(_ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, style: nil, monospacedDigit: false, maxScale: 1.3))
    }
}
