import UIKit

/// Direction in which imported screenshots are combined.
enum StitchDirection: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }

    var systemImage: String {
        switch self {
        case .vertical: return "rectangle.arrowtriangle.2.outward"
        case .horizontal: return "rectangle.arrowtriangle.2.outward.rotate.90"
        }
    }
}

/// File format used when exporting the final stitched image.
enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpg
    case pdf

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

/// The visual technique used to hide sensitive content in a redaction box.
enum RedactionStyle: String, CaseIterable, Identifiable {
    case blur
    case pixelate
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .solid: return "Solid"
        }
    }
}

/// A single redaction rectangle, stored in unit coordinates (0...1)
/// relative to the *cropped* image so it survives cropping/resizing.
struct RedactionBox: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect // unit space, origin top-left
    var style: RedactionStyle
    var color: CGColor // used only when style == .solid

    init(id: UUID = UUID(), rect: CGRect, style: RedactionStyle, color: CGColor = UIColor.black.cgColor) {
        self.id = id
        self.rect = rect
        self.style = style
        self.color = color
    }

    static func == (lhs: RedactionBox, rhs: RedactionBox) -> Bool {
        lhs.id == rhs.id
    }
}

/// One imported screenshot plus all the edits the user has made to it.
final class StitchImage: Identifiable, ObservableObject, Equatable {
    let id: UUID
    let original: UIImage

    /// Fraction of the image height cropped away from the top (0...1).
    @Published var cropTop: CGFloat = 0
    /// Fraction of the image height cropped away from the bottom (0...1).
    @Published var cropBottom: CGFloat = 0
    @Published var redactions: [RedactionBox] = []

    init(id: UUID = UUID(), image: UIImage) {
        self.id = id
        self.original = image
    }

    /// The image after crop has been applied, at full resolution.
    var croppedImage: UIImage {
        let scale = original.scale
        let fullHeight = original.size.height * scale
        let topPx = fullHeight * cropTop
        let bottomPx = fullHeight * cropBottom
        let keptHeight = max(1, fullHeight - topPx - bottomPx)

        guard let cgImage = original.cgImage else { return original }
        let widthPx = CGFloat(cgImage.width)
        let cropRect = CGRect(x: 0, y: topPx, width: widthPx, height: keptHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else { return original }
        return UIImage(cgImage: cropped, scale: scale, orientation: original.imageOrientation)
    }

    static func == (lhs: StitchImage, rhs: StitchImage) -> Bool {
        lhs.id == rhs.id
    }
}
