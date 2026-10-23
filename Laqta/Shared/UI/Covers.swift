//
//  Covers.swift
//  Laqta — Shared
//
//  Folder covers are a soft blur of the newest item (nothing recognizable),
//  or a cover mood when the folder is empty. Plus thumbnails with caching.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI
import UIKit

// MARK: - Rendering

nonisolated enum CoverRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// A tiny, heavily blurred rendition of an image. Upscaled on screen it reads as color and light only.
    @concurrent
    static func blurredCover(from url: URL, fallback: URL?, heavy: Bool) async -> ImageBox? {
        let source = ImageTools.makeThumbnail(from: url, maxPixelSize: 96)
            ?? fallback.flatMap { ImageTools.makeThumbnail(from: $0, maxPixelSize: 96) }
        guard let source else { return nil }
        let input = CIImage(cgImage: source)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = input.clampedToExtent()
        blur.radius = heavy ? 16 : 10
        let controls = CIFilter.colorControls()
        controls.inputImage = blur.outputImage
        controls.saturation = 1.18
        controls.brightness = heavy ? -0.08 : 0
        controls.contrast = 1.02
        guard let output = controls.outputImage?.cropped(to: input.extent),
              let rendered = context.createCGImage(output, from: input.extent) else { return nil }
        return ImageBox(image: UIImage(cgImage: rendered))
    }

    /// Blurred backdrop for the link page hero.
    @concurrent
    static func backdrop(from url: URL) async -> ImageBox? {
        guard let source = ImageTools.makeThumbnail(from: url, maxPixelSize: 160) else { return nil }
        let input = CIImage(cgImage: source)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = input.clampedToExtent()
        blur.radius = 12
        let controls = CIFilter.colorControls()
        controls.inputImage = blur.outputImage
        controls.saturation = 1.2
        controls.brightness = -0.12
        guard let output = controls.outputImage?.cropped(to: input.extent),
              let rendered = context.createCGImage(output, from: input.extent) else { return nil }
        return ImageBox(image: UIImage(cgImage: rendered))
    }

    static func makeGrain(side: Int = 128) -> CGImage? {
        let noise = CIFilter.randomGenerator()
        guard let output = noise.outputImage else { return nil }
        let mono = CIFilter.colorControls()
        mono.inputImage = output
        mono.saturation = 0
        mono.contrast = 1.4
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let image = mono.outputImage?.cropped(to: rect) else { return nil }
        return context.createCGImage(image, from: rect)
    }
}

enum CoverArt {
    static let grain: UIImage = {
        guard let image = CoverRenderer.makeGrain() else { return UIImage() }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()
}

final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 900
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

// MARK: - Views

struct ToneMesh: View {
    let tone: FolderTone

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.55, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: tone.meshColors
        )
    }
}

struct GrainOverlay: View {
    var opacity: Double = 0.5

    var body: some View {
        Image(uiImage: CoverArt.grain)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// What a cover is made of.
nonisolated struct CoverSource: Hashable, Sendable {
    let id: UUID
    let thumbnailURL: URL
    let originalURL: URL?
}

struct FolderCoverView: View {
    let source: CoverSource?
    let tone: FolderTone
    var heavy: Bool = false

    @Environment(\.laqta) private var palette
    @State private var image: UIImage?

    /// How much colour the cover photo keeps of its own. The rest of it comes
    /// from the mood — otherwise the newest shot decides what the folder looks
    /// like and choosing a mood changes nothing you can see.
    private static let photoSaturation: Double = 0.6
    /// A little of the mood multiplied back in, for depth. Kept low: more than
    /// this and a dark photo under a dark mood turns to mud.
    private static let moodWeight: Double = 0.12

    var body: some View {
        ZStack {
            ToneMesh(tone: tone)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(Self.photoSaturation)
                    .clipped()
                    // The mood lights the picture rather than sitting behind it.
                    .overlay { ToneMesh(tone: tone).blendMode(.softLight) }
                    .overlay { ToneMesh(tone: tone).blendMode(.multiply).opacity(Self.moodWeight) }
                    .accessibilityIgnoresInvertColors()
                    .transition(.opacity)
            }
        }
        // Keeps the blends above inside the cover instead of reaching the card.
        .compositingGroup()
        .saturation(palette.coverSaturation)
        .brightness(palette.coverBrightness)
        .clipped()
        .task(id: taskKey) {
            await load()
        }
        .accessibilityHidden(true)
    }

    private var taskKey: String {
        "\(source?.id.uuidString ?? "none")-\(heavy)"
    }

    private func load() async {
        guard let source else {
            image = nil
            return
        }
        let key = "cover-\(source.id.uuidString)-\(heavy)"
        if let cached = ImageMemoryCache.shared.image(for: key) {
            image = cached
            return
        }
        guard let box = await CoverRenderer.blurredCover(from: source.thumbnailURL, fallback: source.originalURL, heavy: heavy) else {
            image = nil
            return
        }
        ImageMemoryCache.shared.insert(box.image, for: key)
        withAnimation(.easeOut(duration: 0.3)) {
            image = box.image
        }
    }
}

/// Fills its frame with the stored thumbnail (regenerated from the original when missing).
struct ShotThumbnail: View {
    let thumbnailURL: URL
    let originalURL: URL?
    var kind: MediaKind = .photo
    var duration: Double?
    var cornerRadius: CGFloat = 0
    var placeholder: Color?
    /// Shown from the web when nothing is stored (YouTube thumbnails).
    var remoteURL: URL?
    /// Fit instead of fill, so nothing is cropped.
    var fits = false

    @Environment(\.laqta) private var palette
    @State private var image: UIImage?

    init(shot: Shot, cornerRadius: CGFloat = 0, fits: Bool = false) {
        self.thumbnailURL = shot.thumbnailURL
        self.originalURL = shot.hasMediaFile ? shot.fileURL : nil
        self.kind = shot.kind.mediaKind ?? .photo
        self.duration = shot.mediaDuration
        self.cornerRadius = cornerRadius
        self.remoteURL = shot.remoteImageURL
        self.fits = fits
    }

    init(thumbnailURL: URL, originalURL: URL?, kind: MediaKind = .photo, cornerRadius: CGFloat = 0, remoteURL: URL? = nil, fits: Bool = false) {
        self.thumbnailURL = thumbnailURL
        self.originalURL = originalURL
        self.kind = kind
        self.cornerRadius = cornerRadius
        self.remoteURL = remoteURL
        self.fits = fits
    }

    private var taskKey: String {
        remoteURL?.absoluteString ?? thumbnailURL.absoluteString
    }

    var body: some View {
        Rectangle()
            .fill(placeholder ?? palette.field)
            .overlay {
                if let image {
                    if fits {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityIgnoresInvertColors()
                            .transition(.opacity)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .accessibilityIgnoresInvertColors()
                            .transition(.opacity)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: taskKey) {
                await load()
            }
    }

    private func load() async {
        if let remoteURL {
            let key = "remote-\(remoteURL.absoluteString)"
            if let cached = ImageMemoryCache.shared.image(for: key) {
                image = cached
                return
            }
            guard let box = await RemoteImageLoader.image(at: remoteURL, maxPixelSize: 960) else { return }
            ImageMemoryCache.shared.insert(box.image, for: key)
            withAnimation(.easeOut(duration: 0.18)) {
                image = box.image
            }
            return
        }
        let key = "thumb-\(thumbnailURL.lastPathComponent)"
        if let cached = ImageMemoryCache.shared.image(for: key) {
            image = cached
            return
        }
        guard let box = await ImageLoader.thumbnail(at: thumbnailURL, original: originalURL, kind: kind, duration: duration) else { return }
        ImageMemoryCache.shared.insert(box.image, for: key)
        withAnimation(.easeOut(duration: 0.18)) {
            image = box.image
        }
    }
}
