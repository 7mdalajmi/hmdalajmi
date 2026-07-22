import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Combines a list of `StitchImage`s into a single flattened `UIImage`,
/// baking in each image's crop and redactions along the way.
enum ImageStitcher {
    private static let ciContext = CIContext()

    static func stitch(
        images: [StitchImage],
        direction: StitchDirection,
        spacing: CGFloat,
        backgroundColor: UIColor
    ) -> UIImage? {
        guard !images.isEmpty else { return nil }

        let processed = images.map { redacted(image: $0) }

        switch direction {
        case .vertical:
            return stitchVertically(processed, spacing: spacing, backgroundColor: backgroundColor)
        case .horizontal:
            return stitchHorizontally(processed, spacing: spacing, backgroundColor: backgroundColor)
        }
    }

    /// Applies crop + redactions for a single `StitchImage` and returns
    /// the flattened, fully-edited `UIImage`.
    private static func redacted(image stitchImage: StitchImage) -> UIImage {
        let base = stitchImage.croppedImage
        guard !stitchImage.redactions.isEmpty, let cgImage = base.cgImage else { return base }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width / base.scale, height: height / base.scale), format: format)

        return renderer.image { ctx in
            base.draw(at: .zero)
            let cg = ctx.cgContext

            for box in stitchImage.redactions {
                let pxRect = CGRect(
                    x: box.rect.minX * width / base.scale,
                    y: box.rect.minY * height / base.scale,
                    width: box.rect.width * width / base.scale,
                    height: box.rect.height * height / base.scale
                )

                switch box.style {
                case .solid:
                    cg.setFillColor(box.color)
                    cg.fill(pxRect)

                case .blur, .pixelate:
                    if let region = filtered(cgImage: cgImage, region: box.rect, style: box.style) {
                        region.draw(in: pxRect)
                    } else {
                        // Fallback: solid black if the filter pipeline fails.
                        cg.setFillColor(UIColor.black.cgColor)
                        cg.fill(pxRect)
                    }
                }
            }
        }
    }

    /// Runs a CoreImage blur/pixelate filter over just the given unit-space
    /// region of `cgImage` and returns a UIImage sized to that region.
    private static func filtered(cgImage: CGImage, region: CGRect, style: RedactionStyle) -> UIImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let pxRect = CGRect(
            x: region.minX * width,
            y: region.minY * height,
            width: region.width * width,
            height: region.height * height
        ).integral

        guard pxRect.width > 0, pxRect.height > 0,
              let cropped = cgImage.cropping(to: pxRect) else { return nil }

        let ciInput = CIImage(cgImage: cropped)
        let outputCI: CIImage

        switch style {
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = ciInput
            filter.scale = Float(max(pxRect.width, pxRect.height) / 12)
            outputCI = filter.outputImage ?? ciInput
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ciInput
            filter.radius = Float(max(pxRect.width, pxRect.height) / 8)
            outputCI = (filter.outputImage ?? ciInput).clampedToExtent().cropped(to: ciInput.extent)
        case .solid:
            return nil
        }

        guard let outCG = ciContext.createCGImage(outputCI, from: ciInput.extent) else { return nil }
        return UIImage(cgImage: outCG)
    }

    private static func stitchVertically(_ images: [UIImage], spacing: CGFloat, backgroundColor: UIColor) -> UIImage {
        let maxWidth = images.map(\.size.width).max() ?? 0
        let totalHeight = images.reduce(0) { $0 + $1.size.height } + spacing * CGFloat(max(0, images.count - 1))
        let size = CGSize(width: maxWidth, height: totalHeight)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = 0
            for image in images {
                let x = (maxWidth - image.size.width) / 2
                image.draw(at: CGPoint(x: x, y: y))
                y += image.size.height + spacing
            }
        }
    }

    private static func stitchHorizontally(_ images: [UIImage], spacing: CGFloat, backgroundColor: UIColor) -> UIImage {
        let maxHeight = images.map(\.size.height).max() ?? 0
        let totalWidth = images.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, images.count - 1))
        let size = CGSize(width: totalWidth, height: maxHeight)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            var x: CGFloat = 0
            for image in images {
                let y = (maxHeight - image.size.height) / 2
                image.draw(at: CGPoint(x: x, y: y))
                x += image.size.width + spacing
            }
        }
    }
}
