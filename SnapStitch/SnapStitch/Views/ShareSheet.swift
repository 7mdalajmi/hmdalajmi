import SwiftUI

/// Thin SwiftUI wrapper around `UIActivityViewController` so we can share
/// exported files (image or PDF) to Messages, Mail, Files, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
