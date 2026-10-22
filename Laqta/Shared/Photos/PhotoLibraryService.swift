//
//  PhotoLibraryService.swift
//  Laqta — Shared
//
//  Finds the original photo or video in the Photos library and deletes it.
//  iOS always asks the user to confirm, and deleted photos go to Recently Deleted.
//

import Foundation
import Photos

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

    /// Maps shot IDs to the local identifiers of their originals.
    @concurrent
    static func resolve(_ fingerprints: [AssetFingerprint]) async -> [UUID: String] {
        guard canModifyLibrary else {
            DebugLog.write("resolve: no Photos access (status \(authorizationStatus.rawValue))")
            return [:]
        }
        var matches: [UUID: String] = [:]
        var claimed = Set<String>()
        for fingerprint in fingerprints {
            if let identifier = bestMatch(for: fingerprint, excluding: claimed) {
                matches[fingerprint.shotID] = identifier
                claimed.insert(identifier)
            }
        }
        return matches
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

    static func bestMatch(for fingerprint: AssetFingerprint, excluding claimed: Set<String>) -> String? {
        if let known = fingerprint.knownAssetID, !claimed.contains(known) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [known], options: nil)
            if result.count > 0 { return known }
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
        // Exact size plus the same capture second (3) or the same file name (4) is enough.
        return pick(from: candidates, minimumScore: 3, addedAt: fingerprint.addedAt)
    }

    /// Videos shared to Laqta may be re-encoded, so the size is only a hint. The length
    /// (to a fraction of a second), the recording time and the file name decide.
    static func bestVideoMatch(for fingerprint: AssetFingerprint, excluding claimed: Set<String>) -> String? {
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

    /// The single best candidate, or nil when two are equally likely.
    private static func pick(from candidates: [Candidate], minimumScore: Int, addedAt: Date) -> String? {
        guard let topScore = candidates.map(\.score).max(), topScore >= minimumScore else { return nil }
        let top = candidates
            .filter { $0.score == topScore }
            .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        if top.count == 1 { return top[0].identifier }

        // Same name on several items (the IMG_#### counter wraps): only accept the newest
        // one when it is clearly the one that was just shared.
        guard let newest = top.first?.created,
              abs(newest.timeIntervalSince(addedAt)) < 2 * 86_400,
              let runnerUp = top.dropFirst().first?.created,
              newest.timeIntervalSince(runnerUp) > 7 * 86_400 else { return nil }
        return top[0].identifier
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
