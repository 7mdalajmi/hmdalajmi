import SwiftUI
import PhotosUI

@MainActor
final class StitchViewModel: ObservableObject {
    @Published var images: [StitchImage] = []
    @Published var direction: StitchDirection = .vertical
    @Published var spacing: CGFloat = 0
    @Published var backgroundColor: Color = .white
    @Published var exportFormat: ExportFormat = .png

    @Published var isImporting = false
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var errorMessage: String?

    var canStitch: Bool { !images.isEmpty }

    func addImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                images.append(StitchImage(image: uiImage))
            }
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        images.move(fromOffsets: source, toOffset: destination)
    }

    func remove(at offsets: IndexSet) {
        images.remove(atOffsets: offsets)
    }

    func removeAll() {
        images.removeAll()
        exportedURL = nil
    }

    func stitchedPreview() -> UIImage? {
        ImageStitcher.stitch(
            images: images,
            direction: direction,
            spacing: spacing,
            backgroundColor: UIColor(backgroundColor)
        )
    }

    func export() {
        guard let final = stitchedPreview() else {
            errorMessage = "Add at least one screenshot before exporting."
            return
        }

        isExporting = true
        defer { isExporting = false }

        switch exportFormat {
        case .png:
            exportedURL = writeTemp(data: final.pngData(), ext: "png")
        case .jpg:
            exportedURL = writeTemp(data: final.jpegData(compressionQuality: 0.95), ext: "jpg")
        case .pdf:
            exportedURL = PDFExporter.makePDF(from: final)
        }

        if exportedURL == nil {
            errorMessage = "Something went wrong while exporting. Please try again."
        }
    }

    private func writeTemp(data: Data?, ext: String) -> URL? {
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnapStitch-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
