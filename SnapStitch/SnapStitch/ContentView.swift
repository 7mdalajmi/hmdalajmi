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
            .navigationTitle("SnapStitch")
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
