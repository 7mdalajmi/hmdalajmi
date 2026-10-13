import SwiftUI

/// The 128 × 64-pt histogram overlay shown at the top-left of the canvas.
///
/// Red, green and blue are filled additively (`.plusLighter`, so overlaps read as cyan, magenta,
/// yellow and white, like Lightroom), with luminance as a soft grey area and a line on top. Small
/// triangles at the top corners light up when more than 0.1 % of the pixels clip to black
/// (left, blue) or white (right, red).
///
/// The graph is a tonal axis (dark → light), so it is always drawn left-to-right, also in Arabic.
/// The data comes from the rendered preview (`EditorModel.histogram`), throttled by the renderer.
struct HistogramView: View {
    let histogram: Histogram?

    @Environment(\.locale) private var locale

    /// Fraction of pixels above which a clipping triangle is filled.
    private static let clippingThreshold: Float = 0.001

    var body: some View {
        Canvas { context, size in
            guard let histogram else { return }
            HistogramView.draw(histogram, in: &context, size: size)
        }
        .frame(width: 128, height: 64)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .fill(Theme.scrim)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text("Histogram"))
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Accessibility

    private var accessibilitySummary: Text {
        guard let histogram else { return Text("Not available") }
        let shadows = percent(histogram.shadowClipping)
        let highlights = percent(histogram.highlightClipping)
        return Text("Shadows clipped \(shadows), highlights clipped \(highlights)")
    }

    private func percent(_ fraction: Float) -> String {
        let value = fraction.isFinite ? Double(min(max(fraction, 0), 1)) : 0
        return value.formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
    }

    // MARK: Drawing

    private static func draw(_ histogram: Histogram, in context: inout GraphicsContext, size: CGSize) {
        let inset: CGFloat = 4
        let plot = CGRect(x: inset, y: inset,
                          width: max(size.width - inset * 2, 1),
                          height: max(size.height - inset * 2, 1))

        // Luminance underneath, as a soft neutral area.
        context.fill(areaPath(histogram.luma, in: plot), with: .color(Theme.histLuma.opacity(0.22)))

        // Colour channels, added together.
        var additive = context
        additive.blendMode = .plusLighter
        additive.fill(areaPath(histogram.red, in: plot), with: .color(Theme.histRed.opacity(0.55)))
        additive.fill(areaPath(histogram.green, in: plot), with: .color(Theme.histGreen.opacity(0.55)))
        additive.fill(areaPath(histogram.blue, in: plot), with: .color(Theme.histBlue.opacity(0.55)))

        // Luminance outline on top.
        context.stroke(linePath(histogram.luma, in: plot), with: .color(Theme.histLuma.opacity(0.85)), lineWidth: 1)

        drawClippingIndicators(histogram, in: &context, plot: plot)
    }

    private static func drawClippingIndicators(_ histogram: Histogram, in context: inout GraphicsContext, plot: CGRect) {
        let side: CGFloat = 7

        var shadow = Path()
        shadow.move(to: CGPoint(x: plot.minX, y: plot.minY))
        shadow.addLine(to: CGPoint(x: plot.minX + side, y: plot.minY))
        shadow.addLine(to: CGPoint(x: plot.minX, y: plot.minY + side))
        shadow.closeSubpath()

        var highlight = Path()
        highlight.move(to: CGPoint(x: plot.maxX, y: plot.minY))
        highlight.addLine(to: CGPoint(x: plot.maxX - side, y: plot.minY))
        highlight.addLine(to: CGPoint(x: plot.maxX, y: plot.minY + side))
        highlight.closeSubpath()

        if histogram.shadowClipping > clippingThreshold {
            context.fill(shadow, with: .color(Theme.clipShadow))
        } else {
            context.stroke(shadow, with: .color(Theme.textTertiary.opacity(0.7)), lineWidth: 1)
        }
        if histogram.highlightClipping > clippingThreshold {
            context.fill(highlight, with: .color(Theme.clipHighlight))
        } else {
            context.stroke(highlight, with: .color(Theme.textTertiary.opacity(0.7)), lineWidth: 1)
        }
    }

    /// Closed area under the bins (each bin 0…1 of the plot height).
    private static func areaPath(_ bins: [Float], in rect: CGRect) -> Path {
        var path = Path()
        guard bins.count > 1 else { return path }
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (index, bin) in bins.enumerated() {
            path.addLine(to: point(index: index, bin: bin, count: bins.count, in: rect))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// Open polyline through the bins.
    private static func linePath(_ bins: [Float], in rect: CGRect) -> Path {
        var path = Path()
        guard bins.count > 1 else { return path }
        for (index, bin) in bins.enumerated() {
            let p = point(index: index, bin: bin, count: bins.count, in: rect)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private static func point(index: Int, bin: Float, count: Int, in rect: CGRect) -> CGPoint {
        let x = rect.minX + rect.width * CGFloat(index) / CGFloat(max(count - 1, 1))
        let level = bin.isFinite ? CGFloat(min(max(bin, 0), 1)) : 0
        return CGPoint(x: x, y: rect.maxY - level * rect.height)
    }
}
