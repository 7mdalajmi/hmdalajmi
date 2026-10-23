//
//  StagedMedia.swift
//  Laqta — Shared
//
//  A photo, video or PDF copied into the staging area, and what Laqta learned about it
//  without decoding it in memory.
//

import CryptoKit
import Foundation

nonisolated enum MediaKind: String, Sendable, Codable, CaseIterable {
    case photo
    case video
    case document

    /// The matching item kind in the library.
    var itemKind: ItemKind {
        switch self {
        case .photo: .photo
        case .video: .video
        case .document: .document
        }
    }
}

/// What Laqta reads from a media file before saving it.
nonisolated struct MediaInfo: Sendable, Hashable {
    var kind: MediaKind
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var capturedAt: Date?
    var captureOffsetKnown: Bool = false
    /// Milliseconds of the capture time (EXIF sub-seconds), when the file has them.
    var captureSubsecond: Int?
    /// A screenshot (photo) or a screen recording (video).
    var isScreenCapture: Bool = false
    /// UTType identifier of the file ("public.heic", "com.apple.quicktime-movie", "com.adobe.pdf").
    var typeIdentifier: String?
    /// "Apple iPhone 16 Pro"
    var cameraModel: String?
    // Video
    var duration: Double?
    var hasAudio: Bool?
    var latitude: Double?
    var longitude: Double?
    // Document
    var pageCount: Int?
    var title: String?
    var isEncrypted: Bool = false

    var pixelCount: Int { pixelWidth * pixelHeight }

    init(kind: MediaKind) {
        self.kind = kind
    }
}

/// A media file in the staging area, ready to be filed into a folder.
nonisolated struct StagedMedia: Sendable, Identifiable, Hashable {
    let id: UUID
    let fileURL: URL
    let thumbnailURL: URL?
    /// The extension made a small thumbnail; the app renders a sharp one later.
    let hasLowResThumbnail: Bool
    let info: MediaInfo
    let originalName: String?
    let byteCount: Int
    let sourceAssetID: String?
    /// SHA-256 of the file (hex).
    let contentHash: String?

    var kind: MediaKind { info.kind }
    var captureKey: String? { DuplicateKey.capture(for: info) }
}

/// File names of a media file after it was moved into permanent storage.
nonisolated struct StoredFiles: Sendable {
    let fileName: String
    let thumbnailName: String
}

// MARK: - Content hash

nonisolated enum ContentHasher {
    /// Streams the file through SHA-256, so large videos never sit in memory.
    static func sha256(of url: URL, chunkSize: Int = 1 << 20) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data
            do {
                guard let next = try handle.read(upToCount: chunkSize), !next.isEmpty else { break }
                chunk = next
            } catch {
                return nil
            }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    static func sha256(of data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Duplicate keys

/// Keys that recognize the same photo, video or link when it is saved again.
nonisolated enum DuplicateKey {
    /// The same capture in another encoding (a HEIC shared later as JPEG).
    /// Only built when the capture time is precise enough to tell burst shots apart.
    static func capture(for info: MediaInfo) -> String? {
        guard let captured = info.capturedAt, info.pixelWidth > 0, info.pixelHeight > 0 else { return nil }
        let seconds = Int(captured.timeIntervalSince1970.rounded(.down))
        let size = "\(max(info.pixelWidth, info.pixelHeight))x\(min(info.pixelWidth, info.pixelHeight))"
        switch info.kind {
        case .photo:
            guard !info.isScreenCapture, let subsecond = info.captureSubsecond else { return nil }
            let model = info.cameraModel.map { "|\($0.lowercased())" } ?? ""
            return "p|\(size)|\(seconds).\(subsecond)\(model)"
        case .video:
            guard let duration = info.duration, duration > 0 else { return nil }
            return "v|\(size)|\(seconds)|\(Int((duration * 10).rounded()))"
        case .document:
            return nil
        }
    }

    /// Tracking parameters that don't change what a link points to.
    static let ignoredQueryItems: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igsh", "igshid",
        "si", "ref_src", "ref_url", "share_id"
    ]

    /// Sharing parameters that only mean something on one site.
    static let ignoredQueryItemsByHost: [String: Set<String>] = [
        "x.com": ["s", "t"],
        "twitter.com": ["s", "t"],
        "tiktok.com": ["_r", "_t", "is_from_webapp", "sender_device", "web_id"],
        "instagram.com": ["utm_source", "igsh"],
        "open.spotify.com": ["si", "context"],
        "reddit.com": ["share_id", "utm_name", "context"]
    ]

    /// "yt:dQw4w9WgXcQ", "example.com/article?id=4"
    static func link(for url: URL) -> String {
        if let videoID = YouTubeLink.videoID(from: url) {
            return "yt:\(videoID)"
        }
        var host = (url.host(percentEncoded: false) ?? "").lowercased()
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let siteIgnored = ignoredQueryItemsByHost[host] ?? []
        let items = (components?.queryItems ?? [])
            .filter { item in
                let name = item.name.lowercased()
                return !ignoredQueryItems.contains(name) && !siteIgnored.contains(name) && !name.hasPrefix("utm_")
            }
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
        let query = items.isEmpty ? "" : "?" + items.joined(separator: "&")
        return host + path + query
    }
}
