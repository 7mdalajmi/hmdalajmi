import SwiftUI

/// Lets the user trim the top and bottom of a screenshot with two sliders
/// while previewing the result live.
struct CropEditorView: View {
    @ObservedObject var image: StitchImage

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geo in
                ZStack {
                    Theme.screenLine

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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.panelLine, lineWidth: 1))
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Crop from top")
                    Slider(value: $image.cropTop, in: 0...0.9)
                        .tint(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Crop from bottom")
                    Slider(value: $image.cropBottom, in: 0...0.9)
                        .tint(Theme.accent)
                }

                Button("Reset Crop") {
                    image.cropTop = 0
                    image.cropBottom = 0
                }
                .tint(Theme.accent)
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
