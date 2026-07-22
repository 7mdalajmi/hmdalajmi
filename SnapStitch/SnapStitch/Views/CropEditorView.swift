import SwiftUI

/// Lets the user trim the top and bottom of a screenshot with two sliders
/// while previewing the result live.
struct CropEditorView: View {
    @ObservedObject var image: StitchImage

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geo in
                ZStack {
                    Color(.secondarySystemBackground)

                    Image(uiImage: image.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(.black.opacity(0.55))
                                .frame(height: geo.size.height * image.cropTop)
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(.black.opacity(0.55))
                                .frame(height: geo.size.height * image.cropBottom)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Crop from top")
                    Slider(value: $image.cropTop, in: 0...0.9)
                }
                VStack(alignment: .leading) {
                    Text("Crop from bottom")
                    Slider(value: $image.cropBottom, in: 0...0.9)
                }

                Button("Reset Crop") {
                    image.cropTop = 0
                    image.cropBottom = 0
                }
                .disabled(image.cropTop == 0 && image.cropBottom == 0)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .onChange(of: image.cropTop) { _, newValue in
            if newValue + image.cropBottom > 0.95 {
                image.cropBottom = 0.95 - newValue
            }
        }
        .onChange(of: image.cropBottom) { _, newValue in
            if newValue + image.cropTop > 0.95 {
                image.cropTop = 0.95 - newValue
            }
        }
    }
}
