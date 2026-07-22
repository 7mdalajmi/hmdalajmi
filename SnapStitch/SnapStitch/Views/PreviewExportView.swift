import SwiftUI

struct PreviewExportView: View {
    @EnvironmentObject private var viewModel: StitchViewModel
    @State private var preview: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.vertical, .horizontal]) {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 600)
                        .padding()
                } else {
                    ContentUnavailableView(
                        "Nothing to preview",
                        systemImage: "photo.stack",
                        description: Text("Import at least one screenshot first.")
                    )
                    .padding(.top, 80)
                }
            }
            .background(Color(.systemGroupedBackground))

            Divider()

            Form {
                Section("Layout") {
                    Picker("Direction", selection: $viewModel.direction) {
                        ForEach(StitchDirection.allCases) { direction in
                            Label(direction.title, systemImage: direction.systemImage).tag(direction)
                        }
                    }
                    HStack {
                        Text("Spacing")
                        Slider(value: $viewModel.spacing, in: 0...40)
                        Text("\(Int(viewModel.spacing))pt").foregroundStyle(.secondary).monospacedDigit()
                    }
                    ColorPicker("Background", selection: $viewModel.backgroundColor, supportsOpacity: false)
                }

                Section("Export") {
                    Picker("Format", selection: $viewModel.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        viewModel.export()
                        showShareSheet = viewModel.exportedURL != nil
                    } label: {
                        Label("Export & Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canStitch)
                }
            }
            .frame(height: 320)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Preview & Export")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refreshKey) {
            preview = viewModel.stitchedPreview()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.exportedURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// Recomputes the preview whenever an input that affects the stitched
    /// output changes, without re-rendering on every SwiftUI redraw.
    private var refreshKey: String {
        let redactionCount = viewModel.images.reduce(0) { $0 + $1.redactions.count }
        return "\(viewModel.images.count)-\(viewModel.direction)-\(Int(viewModel.spacing))-\(redactionCount)-\(viewModel.backgroundColor.description)"
    }
}
