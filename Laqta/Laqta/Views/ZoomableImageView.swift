//
//  ZoomableImageView.swift
//  لقطة
//
//  تكبير بإصبعين ونقرتين، مبني على UIScrollView لسلاسة أفضل.
//

import Foundation
import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage?
    @Binding var isZoomed: Bool
    var onSingleTap: () -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        // Smart Invert leaves photos as they are.
        view.accessibilityIgnoresInvertColors = true
        let coordinator = context.coordinator
        view.onZoomChange = { zoomed in
            coordinator.zoomChanged(zoomed)
        }
        view.onSingleTap = {
            coordinator.singleTap()
        }
        return view
    }

    func updateUIView(_ uiView: ZoomingScrollView, context: Context) {
        context.coordinator.parent = self
        uiView.display(image)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: ZoomableImageView

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        func zoomChanged(_ zoomed: Bool) {
            if parent.isZoomed != zoomed {
                parent.isZoomed = zoomed
            }
        }

        func singleTap() {
            parent.onSingleTap()
        }
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastLayoutSize: CGSize = .zero

    var onZoomChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        decelerationRate = .fast
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func display(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        imageView.image = image
        setZoomScale(1, animated: false)
        layoutImage()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            setZoomScale(1, animated: false)
            layoutImage()
        }
        centerImage()
    }

    private func layoutImage() {
        guard let image = imageView.image,
              bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else {
            imageView.frame = bounds
            contentSize = bounds.size
            return
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        // Allow zooming up to the image's real pixels (at least 3×).
        maximumZoomScale = max(3, 1 / scale)
        centerImage()
    }

    private func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        imageView.center = CGPoint(
            x: contentSize.width / 2 + horizontalInset,
            y: contentSize.height / 2 + verticalInset
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomChange?(scale > minimumZoomScale + 0.01)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
            onZoomChange?(false)
            return
        }
        let point = gesture.location(in: imageView)
        let targetScale = min(maximumZoomScale, 2.5)
        let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        zoom(to: rect, animated: true)
        onZoomChange?(true)
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }
}
