import UIKit

enum PDFExporter {
    /// Wraps a single image as a one-page PDF, sized to the image itself
    /// (in points, at 72dpi-equivalent scaling) and writes it to a temp file.
    static func makePDF(from image: UIImage, filename: String = "SnapStitch") -> URL? {
        let pageSize = CGSize(width: image.size.width, height: image.size.height)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            image.draw(in: CGRect(origin: .zero, size: pageSize))
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
