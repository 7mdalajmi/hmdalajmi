//
//  RecentPhotos.swift
//  Laqta
//
//  The "Recents" grid in Add to Laqta. With Photos access, picked photos and videos keep
//  their exact identifier, so deleting the original never guesses.
//

import Foundation
import Observation
import Photos
import SwiftData
import SwiftUI
import UIKit

@Observable
final class RecentPhotosModel {
    private(set) var assets: [PHAsset] = []
    private(set) var status: PHAuthorizationStatus = PhotoLibraryService.authorizationStatus
    /// Photos and videos that are already in Laqta.
    private(set) var savedAssetIDs: Set<String> = []

    var canBrowse: Bool {
        status == .authorized || status == .limited
    }

    func load(context: ModelContext) {
        status = PhotoLibraryService.authorizationStatus
        guard canBrowse else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        options.fetchLimit = 150
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        assets = list

        let identifiers = list.map(\.localIdentifier)
        let descriptor = FetchDescriptor<Shot>(predicate: #Predicate<Shot> { shot in
            shot.deletedAt == nil && (shot.sourceAssetID.flatMap { identifiers.contains($0) } ?? false)
        })
        savedAssetIDs = Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.sourceAssetID))
    }

    func requestAccess(context: ModelContext) async {
        status = await PhotoLibraryService.requestAccess()
        load(context: context)
    }

    func asset(with identifier: String) -> PHAsset? {
        assets.first { $0.localIdentifier == identifier }
    }
}

enum AssetFiles {
    static func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        let box: ImageBox? = await withCheckedContinuation { (continuation: CheckedContinuation<ImageBox?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image.map { ImageBox(image: $0) })
            }
        }
        return box?.image
    }

    /// Copies the photo or video as it looks in Photos (with edits) to a temporary file.
    static func exportOriginal(_ asset: PHAsset) async throws -> SaveInput {
        let resources = PHAssetResource.assetResources(for: asset)
        let resource: PHAssetResource?
        let fallbackName: String
        if asset.mediaType == .video {
            resource = resources.first { $0.type == .fullSizeVideo } ?? resources.first { $0.type == .video }
            fallbackName = "Video.mov"
        } else {
            resource = resources.first { $0.type == .fullSizePhoto } ?? resources.first { $0.type == .photo } ?? resources.first
            fallbackName = "Photo.jpg"
        }
        guard let resource else { throw MediaError.noData }
        let name = resource.filename ?? fallbackName
        let fallbackExtension = (fallbackName as NSString).pathExtension
        let ext = (name as NSString).pathExtension.isEmpty ? fallbackExtension : (name as NSString).pathExtension
        try FileManager.default.createDirectory(at: PickedMediaFile.directory, withIntermediateDirectories: true)
        let destination = PickedMediaFile.directory.appending(path: "\(UUID().uuidString).\(ext)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options)
        return .file(url: destination, name: (name as NSString).deletingPathExtension, assetID: asset.localIdentifier)
    }
}

struct RecentPhotosGrid: View {
    let model: RecentPhotosModel
    @Binding var selection: [String]

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 150 : 110), spacing: 2)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(model.assets, id: \.localIdentifier) { asset in
                    RecentPhotoCell(
                        asset: asset,
                        order: selection.firstIndex(of: asset.localIdentifier).map { $0 + 1 },
                        isSaved: model.savedAssetIDs.contains(asset.localIdentifier)
                    ) {
                        toggle(asset.localIdentifier)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func toggle(_ identifier: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if let index = selection.firstIndex(of: identifier) {
                selection.remove(at: index)
            } else if selection.count < SaveSession.itemLimit {
                selection.append(identifier)
            }
        }
    }
}

private struct RecentPhotoCell: View {
    let asset: PHAsset
    let order: Int?
    let isSaved: Bool
    let onTap: () -> Void

    @Environment(\.laqta) private var palette
    @State private var image: UIImage?

    private var isVideo: Bool { asset.mediaType == .video }
    private var isScreenshot: Bool { asset.mediaSubtypes.contains(.photoScreenshot) }

    private var kindLabel: String {
        if isVideo { return "Video" }
        return isScreenshot ? "Screenshot" : "Photo"
    }

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .frame(height: 166)
                .frame(maxWidth: .infinity)
                .overlay {
                    ZStack {
                        palette.field
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .accessibilityIgnoresInvertColors()
                                .transition(.opacity)
                        }
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: isVideo ? "video.fill" : (isScreenshot ? "rectangle.dashed" : "camera"))
                            .laqtaIconFont(9, weight: .semibold)
                        Text(verbatim: isVideo ? LaqtaFormat.duration(asset.duration) : kindLabel)
                            .laqtaFont(10.5, weight: .medium, monospacedDigit: true, maxScale: 1.25)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 20)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if isSaved {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .laqtaIconFont(8, weight: .bold)
                            Text("In Laqta")
                                .laqtaFont(10, weight: .semibold, maxScale: 1.25)
                        }
                        .foregroundStyle(palette.goldInk)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 18)
                        .background(palette.accentFill, in: Capsule())
                        .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let order {
                        Text(order, format: .number)
                            .laqtaFont(12, weight: .bold)
                            .foregroundStyle(palette.goldInk)
                            .frame(width: 22, height: 22)
                            .background(palette.accentFill, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay {
                    if order != nil {
                        Rectangle().strokeBorder(palette.accentFill, lineWidth: 3)
                    }
                }
                .opacity(isSaved && order == nil ? 0.72 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityAddTraits(order != nil ? .isSelected : [])
        .task(id: asset.localIdentifier) {
            guard image == nil else { return }
            if let loaded = await AssetFiles.thumbnail(for: asset, side: 330) {
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            }
        }
    }

    private var accessibilityText: String {
        var parts = [kindLabel]
        if isVideo { parts.append(LaqtaFormat.spokenDuration(asset.duration)) }
        if let date = asset.creationDate { parts.append(LaqtaFormat.dateTime(date)) }
        if isSaved { parts.append("Already in Laqta") }
        return parts.joined(separator: ", ")
    }
}
