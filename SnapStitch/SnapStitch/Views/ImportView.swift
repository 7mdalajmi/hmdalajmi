import SwiftUI
import PhotosUI

struct ImportView: View {
    @EnvironmentObject private var viewModel: StitchViewModel
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Eyebrow(text: "Roll No. 001")

            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)

            Text("Combine Screenshots")
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)

            Text("Import multiple screenshots and stitch them into one long image — free, unlimited, no watermark.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 0,
                matching: .images
            ) {
                Label("Import Screenshots", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 32)
            .disabled(viewModel.isImporting)

            if viewModel.isImporting {
                ProgressView("Loading…")
                    .tint(Theme.accent)
            }

            Spacer()
            Spacer()
        }
        .stitchBackground()
        .onChange(of: selectedItems) { _, newItems in
            Task {
                await viewModel.addImages(from: newItems)
                selectedItems = []
            }
        }
    }
}
