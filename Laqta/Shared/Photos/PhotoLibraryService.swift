//
//  PhotoLibraryService.swift
//  Laqta — Shared
//
//  Finds the original photo or video in the Photos library and deletes it.
//  iOS always asks the user to confirm, and deleted photos go to Recently Deleted.
//
//  There are two kinds of answer here, and only one of them may delete anything on
//  its own. An item saved from inside Laqta carries the asset's own identifier, so
//  its original is known. An item shared from another app carries nothing, and the
//  original is worked out from the file name, the pixel size and the capture time —
//  a good guess, and still a guess. Three photos of the same wall, a second shot
//  within the same second, a counter that wrapped back to IMG_0001: all of those can
//  score the same. A guess now has to be shown to the user, side by side with Laqta's
//  own copy, before anything leaves Photos.
//

import Foundation
import Photos
import Synchronization
import UIKit

/// The original Laqta found in Photos, and how sure it is.
nonisolated struct AssetMatch: Sendable, Equatable {
    let identifier: String
    /// The item carries this asset's identifier: it is the original, not a likeness.
    let isExact: Bool
}

nonisolated enum PhotoLibraryService {
    static var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var canModifyLibrary: Bool {
        let status = authorizationStatus
        return status == .authorized || status == .limited
    }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Maps shot IDs to the originals Laqta found in Photos.
    @concurrent
    static func resolve(_ fingerprints: [AssetFingerprint]) async -> [UUID: AssetMatch] {
        guard canModifyLibrary else {
            DebugLog.write("resolve: no Photos access (status \(authorizationStatus.rawValue))")
            return [:]
        }
        var matches: [UUID: AssetMatch] = [:]
        var claimed = Set<String>()
        for fingerprint in fingerprints {
            if let match = bestMatch(for: fingerprint, excluding: claimed) {
                matches[fingerprint.shotID] = match
                claimed.insert(match.identifier)
            }
        }
        return matches
    }

    /// A thumbnail of one asset, for the sheet that asks whether this is the original.
    @concurrent
    static func thumbnail(for identifier: String, pixelSize: CGFloat) async -> ImageBox? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        let size = CGSize(width: pixelSize, height: pixelSize)
        return await withCheckedContinuation { (continuation: CheckedContinuation<ImageBox?, Never>) in
            // Opportunistic delivery can call back twice (a quick one, then the real
            // one). `isDegraded` marks the first; only the full image is answered with,
            // and a resume that already happened is not repeated.
            let box = OneShot()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                guard !isDegraded else { return }
                guard box.claim() else { return }
                continuation.resume(returning: image.map { ImageBox(image: $0) })
            }
        }
    }

    /// Lets exactly one of several callbacks answer the continuation.
    nonisolated private final class OneShot: @unchecked Sendable {
        private let lock = Mutex(false)

        func claim() -> Bool {
            lock.withLock { done in
                if done { return false }
                done = true
                return true
            }
        }
    }

    /// Shows the system confirmation, then moves the assets to Recently Deleted.
    static func deleteAssets(withIdentifiers identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    static func isUserCancellation(_ error: any Error) -> Bool {
        let nsError = error as NSError
        // PHPhotosErrorUserCancelled
        return nsError.domain == "PHPhotosErrorDomain" && nsError.code == 3072
    }

    // MARK: Matching

    private struct Candidate {
        let identifier: String
        let score: Int
        let created: Date?
    }

    static func bestMatch(for fingerprint: AssetFingerprint, excluding claimed: Set<String>) -> AssetMatch? {
        if let known = fingerprint.knownAssetID, !claimed.contains(known) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [known], options: nil)
            if result.count > 0 { return AssetMatch(identifier: known, isExact: true) }
        }
        if fingerprint.isVideo {
            return bestVideoMatch(for: fingerprint, excluding: claimed)
        }
        guard fingerprint.pixelWidth > 0, fingerprint.pixelHeight > 0 else { return nil }

        let width = NSNumber(value: fingerprint.pixelWidth)
        let height = NSNumber(value: fingerprint.pixelHeight)
        var format = "mediaType == %@ AND ((pixelWidth == %@ AND pixelHeight == %@) OR (pixelWidth == %@ AND pixelHeight == %@))"
        var arguments: [Any] = [NSNumber(value: PHAssetMediaType.image.rawValue), width, height, height, width]
        if let captured = fingerprint.capturedAt {
            // Without an EXIF offset the capture time could be in any time zone.
            let window: TimeInterval = fingerprint.captureOffsetKnown ? 180 : 14 * 3600 + 180
            format += " AND creationDate >= %@ AND creationDate <= %@"
            arguments.append(captured.addingTimeInterval(-window) as NSDate)
            arguments.append(captured.addingTimeInterval(window) as NSDate)
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: format, argumentArray: arguments)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 500
        let assets = PHAsset.fetchAssets(with: options)
        guard assets.count > 0 else {
            DebugLog.write("match: no assets with size \(fingerprint.pixelWidth)x\(fingerprint.pixelHeight) date=\(fingerprint.capturedAt?.description ?? "-")")
            return nil
        }

        let wantedName = normalizedName(fingerprint.originalName)
        var candidates: [Candidate] = []
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            let identifier = asset.localIdentifier
            if claimed.contains(identifier) { continue }

            var score = 0
            if let wantedName {
                let names = PHAssetResource.assetResources(for: asset).compactMap { normalizedName($0.filename) }
                if names.contains(wantedName) { score += 4 }
            }
            if let captured = fingerprint.capturedAt, let created = asset.creationDate {
                let delta = abs(created.timeIntervalSince(captured))
                // Distance to the nearest whole quarter hour (time-zone shifts).
                let quarterRemainder = delta.truncatingRemainder(dividingBy: 900)
                let zoneShifted = min(quarterRemainder, 900 - quarterRemainder)
                if delta <= 2 {
                    score += 3
                } else if !fingerprint.captureOffsetKnown, zoneShifted <= 2 {
                    score += 2
                } else if delta <= 180 {
                    score += 1
                }
            }
            if fingerprint.isScreenshot, asset.mediaSubtypes.contains(.photoScreenshot) {
                score += 1
            }
            if score > 0 {
                candidates.append(Candidate(identifier: identifier, score: score, created: asset.creationDate))
            }
        }

        DebugLog.write("match name=\(wantedName ?? "-") size=\(fingerprint.pixelWidth)x\(fingerprint.pixelHeight) date=\(fingerprint.capturedAt?.description ?? "-") offset=\(fingerprint.captureOffsetKnown) fetched=\(assets.count) scores=\(candidates.map(\.score))")
        // Exact size plus the same capture second (3) or the same file name (4) is enough
        // to show the user — never, on its own, to delete anything.
        return pick(from: candidates, minimumScore: 3, addedAt: fingerprint.addedAt)
    }

    /// Videos shared to Laqta may be re-encoded, so the size is only a hint. The length
    /// (to a fraction of a second), the recording time and the file name decide.
    static func bestVideoMatch(for fingerprint: AssetFingerprint, excluding claimed: Set<String>) -> AssetMatch? {
        let duration = fingerprint.duration ?? 0
        var format = "mediaType == %@"
        var arguments: [Any] = [NSNumber(value: PHAssetMediaType.video.rawValue)]
        if let captured = fingerprint.capturedAt {
            let window: TimeInterval = fingerprint.captureOffsetKnown ? 180 : 14 * 3600 + 180
            format += " AND creationDate >= %@ AND creationDate <= %@"
            arguments.append(captured.addingTimeInterval(-window) as NSDate)
            arguments.append(captured.addingTimeInterval(window) as NSDate)
        } else if duration > 0 {
            format += " AND duration >= %@ AND duration <= %@"
            arguments.append(NSNumber(value: max(0, duration - 0.6)))
            arguments.append(NSNumber(value: duration + 0.6))
        } else {
            return nil
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: format, argumentArray: arguments)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 500
        let assets = PHAsset.fetchAssets(with: options)
        guard assets.count > 0 else {
            DebugLog.write("match video: nothing near \(fingerprint.capturedAt?.description ?? "-") length=\(duration)")
            return nil
        }

        let wantedName = normalizedName(fingerprint.originalName)
        var candidates: [Candidate] = []
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            let identifier = asset.localIdentifier
            if claimed.contains(identifier) { continue }

            var score = 0
            if duration > 0 {
                let delta = abs(asset.duration - duration)
                if delta <= 0.15 {
                    score += 3
                } else if delta <= 0.6 {
                    score += 1
                } else {
                    // A different length is a different video, whatever its name.
                    continue
                }
            }
            if let wantedName {
                let names = PHAssetResource.assetResources(for: asset).compactMap { normalizedName($0.filename) }
                if names.contains(wantedName) { score += 4 }
            }
            let sameSize = (asset.pixelWidth == fingerprint.pixelWidth && asset.pixelHeight == fingerprint.pixelHeight)
                || (asset.pixelWidth == fingerprint.pixelHeight && asset.pixelHeight == fingerprint.pixelWidth)
            if fingerprint.pixelWidth > 0, sameSize {
                score += 1
            }
            if let captured = fingerprint.capturedAt, let created = asset.creationDate {
                let delta = abs(created.timeIntervalSince(captured))
                let quarterRemainder = delta.truncatingRemainder(dividingBy: 900)
                let zoneShifted = min(quarterRemainder, 900 - quarterRemainder)
                if delta <= 2 {
                    score += 2
                } else if !fingerprint.captureOffsetKnown, zoneShifted <= 2 {
                    score += 1
                }
            }
            if score > 0 {
                candidates.append(Candidate(identifier: identifier, score: score, created: asset.creationDate))
            }
        }

        DebugLog.write("match video name=\(wantedName ?? "-") length=\(duration) date=\(fingerprint.capturedAt?.description ?? "-") fetched=\(assets.count) scores=\(candidates.map(\.score))")
        // For example: the same length and recording second (5), or the same length and name (7).
        return pick(from: candidates, minimumScore: 5, addedAt: fingerprint.addedAt)
    }

    /// The single best candidate, or nil when two are equally likely. Always a guess:
    /// nothing here is the asset's own identifier.
    private static func pick(from candidates: [Candidate], minimumScore: Int, addedAt: Date) -> AssetMatch? {
        guard let topScore = candidates.map(\.score).max(), topScore >= minimumScore else { return nil }
        let top = candidates
            .filter { $0.score == topScore }
            .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        if top.count == 1 { return AssetMatch(identifier: top[0].identifier, isExact: false) }

        // Same name on several items (the IMG_#### counter wraps): only accept the newest
        // one when it is clearly the one that was just shared.
        guard let newest = top.first?.created,
              abs(newest.timeIntervalSince(addedAt)) < 2 * 86_400,
              let runnerUp = top.dropFirst().first?.created,
              newest.timeIntervalSince(runnerUp) > 7 * 86_400 else { return nil }
        return AssetMatch(identifier: top[0].identifier, isExact: false)
    }

    static func normalizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, ext.count <= 5 {
            name = (name as NSString).deletingPathExtension
        }
        if name.hasPrefix("img_e") {
            name = "img_" + name.dropFirst(5)
        }
        let generic: Set<String> = ["", "img", "image", "photo", "file", "screenshot", "fullsizerender"]
        return generic.contains(name) ? nil : name
    }
}
