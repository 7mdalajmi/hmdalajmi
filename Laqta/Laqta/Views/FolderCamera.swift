//
//  FolderCamera.swift
//  Laqta
//
//  Hold a folder, pick the camera, and the shutter puts the picture in that
//  folder. No picking it out of the Photos app afterwards, no share sheet, no
//  sorting later — the folder is decided before the shot is taken.
//
//  The picture is written straight into Laqta's own staging area and never goes
//  near the photo library, so nothing has to be deleted from Photos after.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct FolderCameraSheet: View {
    let folder: Folder

    @Environment(\.dismiss) private var dismiss
    @Environment(\.laqta) private var palette
    @AppObject(ToastCenter.self) private var toasts

    @State private var session: SaveSession?
    @State private var failure: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                SaveSheet(session: session)
                    .laqtaThemed()
            } else {
                CameraCapture(folderName: folder.name) { image in
                    guard let image else {
                        dismiss()
                        return
                    }
                    capture(image)
                }
                .ignoresSafeArea()
            }
        }
        .alert("Camera", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { dismiss() }
        } message: {
            Text(verbatim: failure ?? "")
        }
    }

    private func capture(_ image: UIImage) {
        let box = ImageBox(image: image)
        let folderID = folder.id
        Task {
            let made = await Task.detached(priority: .userInitiated) {
                FolderCameraFile.write(box.image)
            }.value
            guard let made else {
                failure = String(localized: "Laqta could not save that picture.")
                return
            }
            session = SaveSession(
                inputs: [.file(url: made, name: made.lastPathComponent, assetID: nil)],
                fixedFolderID: folderID,
                onFinish: {
                    toasts.show(String(localized: "Saved to \(folder.name)"), systemImage: "checkmark")
                    dismiss()
                },
                onCancel: { dismiss() }
            )
        }
    }
}

// MARK: - Writing the picture

nonisolated enum FolderCameraFile {
    /// A JPEG in the staging area, named after the moment it was taken.
    static func write(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let stamp = Int(Date.now.timeIntervalSince1970)
        let url = AppGroup.stagingURL.appending(path: "camera-\(stamp)-\(UUID().uuidString.prefix(6)).jpg")
        do {
            try FileManager.default.createDirectory(at: AppGroup.stagingURL, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - The viewfinder

/// The system camera, with the folder it is shooting into named across the top.
private struct CameraCapture: UIViewControllerRepresentable {
    let folderName: String
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        // The simulator has no camera; the caller checks first, and this is the net.
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        controller.allowsEditing = false
        if controller.sourceType == .camera {
            controller.cameraCaptureMode = .photo
            controller.cameraOverlayView = Self.banner(folderName: folderName, in: controller.view.bounds)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    /// "→ Perfumes" across the top, so the folder cannot be forgotten mid-shot.
    private static func banner(folderName: String, in bounds: CGRect) -> UIView {
        let overlay = UIView(frame: bounds)
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false

        let label = PaddedLabel()
        label.text = "→ \(folderName)"
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = UIColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 1)
        label.backgroundColor = UIColor(red: 0.89, green: 0.79, blue: 0.56, alpha: 0.96)
        label.textAlignment = .center
        label.layer.cornerRadius = 15
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 14),
            label.heightAnchor.constraint(equalToConstant: 30)
        ])
        return overlay
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// A rounded pill that does not clip its own text.
private final class PaddedLabel: UILabel {
    private let inset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: inset))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + inset.left + inset.right, height: size.height)
    }
}
