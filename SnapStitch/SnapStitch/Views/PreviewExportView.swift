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
            .background(Theme.background)

            Divider()
                .background(Theme.panelLine)

            Form {
                Section {
                    Picker("Direction", selection: $viewModel.direction) {
                        ForEach(StitchDirection.allCases) { direction in
                            Label(direction.title, systemImage: direction.systemImage).tag(direction)
                        }
                    }
                    HStack {
                        Text("Spacing")
                        Slider(value: $viewModel.spacing, in: 0...40)
                            .tint(Theme.accent)
                        Text("\(Int(viewModel.spacing))pt")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    ColorPicker("Background", selection: $viewModel.backgroundColor, supportsOpacity: false)
                } header: {
                    Eyebrow(text: "Layout")
                }
                .listRowBackground(Theme.panel)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)

                Section {
                    Picker("Format", selection: $viewModel.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)

                    Button {
                        viewModel.export()
                        showShareSheet = viewModel.exportedURL != nil
                    } label: {
                        Label("Export & Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.accentInk)
                    .disabled(!viewModel.canStitch)
                } header: {
                    Eyebrow(text: "Export")
                }
                .listRowBackground(Theme.panel)
            }
            .frame(height: 340)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .stitchBackground()
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
