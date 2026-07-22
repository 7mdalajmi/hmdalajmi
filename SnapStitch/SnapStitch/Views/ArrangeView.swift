import SwiftUI
import PhotosUI

struct ArrangeView: View {
    @EnvironmentObject private var viewModel: StitchViewModel
    @State private var editingImage: StitchImage?
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        List {
            Section {
                ForEach(viewModel.images) { image in
                    Button {
                        editingImage = image
                    } label: {
                        HStack(spacing: 12) {
                            Image(uiImage: image.croppedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Screenshot")
                                    .font(.subheadline.weight(.medium))
                                if !image.redactions.isEmpty {
                                    Label("\(image.redactions.count) redaction(s)", systemImage: "eye.slash")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onMove { viewModel.move(from: $0, to: $1) }
                .onDelete { viewModel.remove(at: $0) }
            } header: {
                Text("Drag to reorder · tap to crop or redact")
            }

            Section {
                PhotosPicker(selection: $selectedItems, maxSelectionCount: 0, matching: .images) {
                    Label("Add More Screenshots", systemImage: "plus")
                }
            }
        }
        .toolbar { EditButton() }
        .sheet(item: $editingImage) { image in
            ImageEditorView(image: image)
        }
        .onChange(of: selectedItems) { _, newItems in
            Task {
                await viewModel.addImages(from: newItems)
                selectedItems = []
            }
        }
    }
}

/// Hosts the crop and redact tools for a single imported screenshot.
private struct ImageEditorView: View {
    @ObservedObject var image: StitchImage
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .crop

    private enum Tab: String, CaseIterable, Identifiable {
        case crop, redact
        var id: String { rawValue }
        var title: String { rawValue == "crop" ? "Crop" : "Redact" }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Mode", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch tab {
                case .crop:
                    CropEditorView(image: image)
                case .redact:
                    RedactEditorView(image: image)
                }
            }
            .navigationTitle("Edit Screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
