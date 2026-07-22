import SwiftUI

/// Lets the user draw rectangles over sensitive content and choose how
/// each rectangle should be obscured (blur, pixelate, or solid fill).
struct RedactEditorView: View {
    @ObservedObject var image: StitchImage

    @State private var style: RedactionStyle = .blur
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 16) {
            Picker("Style", selection: $style) {
                ForEach(RedactionStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image.croppedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(
                            GeometryReader { imgGeo in
                                Color.clear.onAppear { canvasSize = imgGeo.size }
                            }
                        )

                    ForEach(image.redactions) { box in
                        redactionOverlay(for: box, in: canvasSize)
                            .onTapGesture {
                                image.redactions.removeAll { $0.id == box.id }
                            }
                    }

                    if let start = dragStart, let current = dragCurrent {
                        let rect = normalizedRect(start, current)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.35))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                            .frame(width: rect.width * canvasSize.width, height: rect.height * canvasSize.height)
                            .position(
                                x: rect.midX * canvasSize.width,
                                y: rect.midY * canvasSize.height
                            )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if dragStart == nil { dragStart = value.startLocation }
                            dragCurrent = value.location
                        }
                        .onEnded { value in
                            defer {
                                dragStart = nil
                                dragCurrent = nil
                            }
                            guard let start = dragStart, canvasSize.width > 0, canvasSize.height > 0 else { return }
                            let rect = normalizedRect(start, value.location)
                            guard rect.width > 0.02, rect.height > 0.02 else { return }
                            image.redactions.append(RedactionBox(rect: rect, style: style))
                        }
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Text("Drag over the parts of the screenshot you want to hide.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !image.redactions.isEmpty {
                Button(role: .destructive) {
                    image.redactions.removeAll()
                } label: {
                    Label("Clear All Redactions", systemImage: "trash")
                }
            }

            Spacer()
        }
        .padding(.top)
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        let minX = max(0, min(a.x, b.x))
        let minY = max(0, min(a.y, b.y))
        let maxX = min(canvasSize.width, max(a.x, b.x))
        let maxY = min(canvasSize.height, max(a.y, b.y))
        return CGRect(
            x: minX / canvasSize.width,
            y: minY / canvasSize.height,
            width: (maxX - minX) / canvasSize.width,
            height: (maxY - minY) / canvasSize.height
        )
    }

    @ViewBuilder
    private func redactionOverlay(for box: RedactionBox, in size: CGSize) -> some View {
        Rectangle()
            .fill(Color(box.style == .solid ? UIColor(cgColor: box.color) : .black).opacity(box.style == .solid ? 1 : 0.4))
            .overlay(
                Image(systemName: box.style == .blur ? "drop.fill" : (box.style == .pixelate ? "square.grid.3x3.fill" : "eye.slash.fill"))
                    .foregroundStyle(.white.opacity(0.8))
            )
            .frame(width: box.rect.width * size.width, height: box.rect.height * size.height)
            .position(x: box.rect.midX * size.width, y: box.rect.midY * size.height)
    }
}
