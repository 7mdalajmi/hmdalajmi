import SwiftUI
import CoreText

/// The two bundled fonts (OFL): Amiri Bold for names and titles, Cormorant Garamond (variable) for every number.
nonisolated enum BundledFonts {
    static let files = ["Amiri-Bold", "CormorantGaramond-VF"]

    /// Registers the fonts for this process, once, at launch.
    static func register() {
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Cormorant Garamond numerals: lining figures always (its default figures are old-style),
/// tabular where numbers stack, at a weight on the variable axis.
enum Numerals {
    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let tabular: Bool
    }

    private static var cache: [Key: Font] = [:]

    static func font(_ size: CGFloat, weight: CGFloat = 600, tabular: Bool = true) -> Font {
        let key = Key(size: size, weight: weight, tabular: tabular)
        if let f = cache[key] { return f }
        let f = Font(ctFont(size: size, weight: weight, tabular: tabular))
        cache[key] = f
        return f
    }

    nonisolated static func ctFont(size: CGFloat, weight: CGFloat, tabular: Bool) -> CTFont {
        var features: [[CFString: Any]] = [[kCTFontOpenTypeFeatureTag: "lnum", kCTFontOpenTypeFeatureValue: 1]]
        if tabular { features.append([kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]) }
        let wght: UInt32 = 0x7767_6874 // 'wght'
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: "CormorantGaramond-Light", // the variable font's default instance
            kCTFontVariationAttribute: [NSNumber(value: wght): NSNumber(value: Double(weight))],
            kCTFontFeatureSettingsAttribute: features
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

extension Font {
    /// Amiri Bold at a fixed size: names and titles are display text.
    static func amiri(_ size: CGFloat) -> Font {
        .custom("Amiri-Bold", fixedSize: size)
    }

    static func numerals(_ size: CGFloat, weight: CGFloat = 600, tabular: Bool = true) -> Font {
        Numerals.font(size, weight: weight, tabular: tabular)
    }
}

/// System Arabic labels that follow Dynamic Type (capped at the root).
struct ScaledLabelFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// A system label at the design's size and weight, growing with Dynamic Type.
    func label(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(ScaledLabelFont(size: size, weight: weight))
    }

    /// The design's line height: the text keeps its own height for drawing but takes `height` in the layout,
    /// centred, so tall fonts (Amiri's line is 1.76 em) sit where the boards put them.
    func lineBox(_ height: CGFloat) -> some View {
        frame(height: height)
    }
}
