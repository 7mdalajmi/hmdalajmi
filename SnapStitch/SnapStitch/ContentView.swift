import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: StitchViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.images.isEmpty {
                    ImportView()
                } else {
                    ArrangeView()
                }
            }
            .stitchBackground()
            .navigationTitle("SnapStitch")
            .toolbarBackground(Theme.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if !viewModel.images.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink {
                            PreviewExportView()
                        } label: {
                            Label("Preview", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(role: .destructive) {
                            viewModel.removeAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(StitchViewModel())
}
