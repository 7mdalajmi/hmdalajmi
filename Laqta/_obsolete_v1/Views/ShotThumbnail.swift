//
//  ShotThumbnail.swift
//  لقطة
//

import Foundation
import SwiftUI
import UIKit

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 800
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}

/// صورة مصغّرة تملأ الإطار المتاح دون أن تغيّر تخطيطه.
struct ShotThumbnail: View {
    let thumbnailURL: URL
    let originalURL: URL
    var cornerRadius: CGFloat = 0

    @State private var image: UIImage? = nil

    init(shot: Shot, cornerRadius: CGFloat = 0) {
        self.thumbnailURL = shot.thumbnailURL
        self.originalURL = shot.fileURL
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: thumbnailURL) {
                await load()
            }
    }

    private func load() async {
        let key = thumbnailURL.lastPathComponent
        if let cached = ThumbnailCache.shared.image(for: key) {
            image = cached
            return
        }
        guard let box = await ImageLoader.thumbnail(at: thumbnailURL, original: originalURL) else { return }
        ThumbnailCache.shared.insert(box.image, for: key)
        withAnimation(.easeOut(duration: 0.18)) {
            image = box.image
        }
    }
}
