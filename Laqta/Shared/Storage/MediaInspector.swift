//
//  MediaInspector.swift
//  Laqta — Shared
//
//  Reads photos, videos and PDFs (size, dates, length, location, pages) and makes
//  their thumbnails, without loading the whole file into memory.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

nonisolated enum MediaInspector {
    // MARK: Kind

    static func kind(of type: UTType) -> MediaKind? {
        if type.conforms(to: .pdf) { return .document }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .photo }
        return nil
    }

    static func kind(forFileAt url: URL) -> MediaKind? {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType, let kind = kind(of: type) {
            return kind
        }
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()), let kind = kind(of: type) {
            return kind
        }
        // Files without an extension: images are the only kind ImageIO can tell apart.
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 {
            return .photo
        }
        return nil
    }

    static func typeIdentifier(forFileAt url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier
            ?? UTType(filenameExtension: url.pathExtension.lowercased())?.identifier
    }

    // MARK: Info

    @concurrent
    static func info(forFileAt url: URL, kind: MediaKind) async -> MediaInfo? {
        switch kind {
        case .photo: photoInfo(at: url)
        case .video: await videoInfo(at: url)
        case .document: documentInfo(at: url)
        }
    }

    static func photoInfo(at url: URL) -> MediaInfo? {
        guard let metadata = ImageTools.metadata(at: url), metadata.pixelWidth > 0, metadata.pixelHeight > 0 else {
            return nil
        }
        var info = MediaInfo(kind: .photo)
        info.pixelWidth = metadata.pixelWidth
        info.pixelHeight = metadata.pixelHeight
        info.capturedAt = metadata.capturedAt
        info.captureOffsetKnown = metadata.captureOffsetKnown
        info.captureSubsecond = metadata.subsecond
        info.isScreenCapture = metadata.isScreenshot
        info.typeIdentifier = metadata.typeIdentifier
        info.cameraModel = metadata.cameraModel
        return info
    }

    @concurrent
    static func videoInfo(at url: URL) async -> MediaInfo? {
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.duration, .metadata, .creationDate) else {
            return nil
        }
        let (duration, metadata, creationItem) = loaded
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }

        var info = MediaInfo(kind: .video)
        info.duration = seconds
        info.typeIdentifier = typeIdentifier(forFileAt: url)

        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let geometry = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: geometry.0).applying(geometry.1)
            info.pixelWidth = Int(abs(rect.width).rounded())
            info.pixelHeight = Int(abs(rect.height).rounded())
        }
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        info.hasAudio = !audioTracks.isEmpty

        // Capture date: QuickTime creation date (keeps the time zone), then the common key.
        if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataCreationDate).first,
           let value = try? await item.load(.stringValue) {
            info.capturedAt = parseISODate(value)
            info.captureOffsetKnown = info.capturedAt != nil
        }
        if info.capturedAt == nil, let creationItem, let date = try? await creationItem.load(.dateValue) {
            info.capturedAt = date
            info.captureOffsetKnown = true
        }

        let make = await string(for: .quickTimeMetadataMake, in: metadata)
        let model = await string(for: .quickTimeMetadataModel, in: metadata)
        info.cameraModel = ImageTools.cameraName(make: make, model: model)

        // iPhone videos keep the place in QuickTime metadata; other cameras and apps use
        // the user-data atom (©xyz, in QuickTime or MPEG-4 files) or the common key.
        for item in locationItems(in: metadata) {
            if let value = try? await item.load(.stringValue),
               let coordinate = parseISO6709(value) {
                info.latitude = coordinate.latitude
                info.longitude = coordinate.longitude
                break
            }
        }

        info.isScreenCapture = looksLikeScreenRecording(info, hasCameraMetadata: make != nil || model != nil)
        return info
    }

    /// Screen recordings carry no camera metadata and have the screen's tall shape.
    static func looksLikeScreenRecording(_ info: MediaInfo, hasCameraMetadata: Bool) -> Bool {
        guard !hasCameraMetadata, info.latitude == nil, info.pixelWidth > 0, info.pixelHeight > 0 else { return false }
        let long = Double(max(info.pixelWidth, info.pixelHeight))
        let short = Double(min(info.pixelWidth, info.pixelHeight))
        let ratio = long / short
        return ratio >= 2.0 && ratio <= 2.35
    }

    static func documentInfo(at url: URL) -> MediaInfo? {
        guard let document = PDFDocument(url: url) else { return nil }
        var info = MediaInfo(kind: .document)
        info.typeIdentifier = UTType.pdf.identifier
        info.pageCount = document.pageCount
        info.isEncrypted = document.isLocked
        let attributes = document.documentAttributes ?? [:]
        if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            info.title = isUsefulTitle(trimmed) ? trimmed : nil
        }
        info.capturedAt = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
        if !document.isLocked, let page = document.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            let quarterTurns = (page.rotation / 90) % 2
            let width = quarterTurns == 0 ? bounds.width : bounds.height
            let height = quarterTurns == 0 ? bounds.height : bounds.width
            info.pixelWidth = Int(width.rounded())
            info.pixelHeight = Int(height.rounded())
        }
        return info
    }

    /// PDF titles are often left as "Untitled", "Microsoft Word - x.docx" or a file path.
    static func isUsefulTitle(_ title: String) -> Bool {
        guard title.count >= 3, title.count <= 140 else { return false }
        let lower = title.lowercased()
        let useless = ["untitled", "document", "microsoft word", "pdf", "scan", "print"]
        if useless.contains(where: { lower == $0 || lower.hasPrefix($0 + " -") }) { return false }
        if lower.hasPrefix("/") || lower.contains(":\\") { return false }
        if lower.hasSuffix(".doc") || lower.hasSuffix(".docx") || lower.hasSuffix(".pages") { return false }
        return true
    }

    // MARK: Thumbnails

    @concurrent
    static func thumbnail(forFileAt url: URL, kind: MediaKind, maxPixelSize: Int, allowFullDecode: Bool, duration: Double?) async -> CGImage? {
        switch kind {
        case .photo:
            ImageTools.makeThumbnail(from: url, maxPixelSize: maxPixelSize, allowFullDecode: allowFullDecode)
        case .video:
            await videoFrame(at: url, seconds: posterTime(for: duration), maxPixelSize: maxPixelSize)
        case .document:
            documentThumbnail(at: url, maxPixelSize: maxPixelSize)
        }
    }

    /// A frame a little into the video, past black intros.
    static func posterTime(for duration: Double?) -> Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1.0, duration * 0.1)
    }

    @concurrent
    static func videoFrame(at url: URL, seconds: Double, maxPixelSize: Int) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        if let frame = try? await generator.image(at: time) {
            return frame.image
        }
        return try? await generator.image(at: .zero).image
    }

    /// Frames spread over a video, for on-device analysis.
    @concurrent
    static func videoFrames(at url: URL, count: Int, duration: Double, maxPixelSize: Int) async -> [(seconds: Double, image: CGImage)] {
        guard count > 0, duration > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let step = duration / Double(count + 1)
        let times = (1...count).map { CMTime(seconds: step * Double($0), preferredTimescale: 600) }
        var frames: [(seconds: Double, image: CGImage)] = []
        for await result in generator.images(for: times) {
            if case let .success(requested, image, _) = result {
                frames.append((requested.seconds, image))
            }
        }
        return frames.sorted { $0.seconds < $1.seconds }
    }

    static func documentThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let document = PDFDocument(url: url), !document.isLocked, let page = document.page(at: 0) else { return nil }
        return render(page, maxPixelSize: maxPixelSize)
    }

    /// Draws a PDF page on white at the given size (text recognition and thumbnails).
    static func render(_ page: PDFPage, maxPixelSize: Int) -> CGImage? {
        guard let pageRef = page.pageRef else { return nil }
        let box = pageRef.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0, maxPixelSize > 0 else { return nil }
        let rotated = pageRef.rotationAngle % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let scale = CGFloat(maxPixelSize) / max(size.width, size.height)
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        // A 1:1 drawing transform takes care of the page rotation and the box origin
        // (getDrawingTransform never scales up, so the scale is applied separately).
        let transform = pageRef.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        context.clip(to: box)
        context.drawPDFPage(pageRef)
        return context.makeImage()
    }

    // MARK: Parsing

    /// Location items, the most precise kind first.
    static func locationItems(in items: [AVMetadataItem]) -> [AVMetadataItem] {
        func rank(_ item: AVMetadataItem) -> Int? {
            let identifier = item.identifier?.rawValue ?? ""
            if identifier == AVMetadataIdentifier.quickTimeMetadataLocationISO6709.rawValue { return 0 }
            if identifier.hasSuffix("/%A9xyz") || identifier.hasSuffix("/©xyz") { return 1 }
            if item.commonKey == .commonKeyLocation { return 2 }
            return nil
        }
        return items
            .compactMap { item in rank(item).map { (rank: $0, item: item) } }
            .sorted { $0.rank < $1.rank }
            .map(\.item)
    }

    private static func string(for identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "2026-09-12T18:40:03+0300"
    static func parseISODate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss Z"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// "+29.3759+047.9774+012.345/" → (29.3759, 47.9774)
    static func parseISO6709(_ value: String) -> (latitude: Double, longitude: Double)? {
        let pattern = #"^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let latRange = Range(match.range(at: 1), in: value),
              let lonRange = Range(match.range(at: 2), in: value),
              let latitude = Double(value[latRange]),
              let longitude = Double(value[lonRange]),
              abs(latitude) <= 90, abs(longitude) <= 180,
              abs(latitude) > 0.0001 || abs(longitude) > 0.0001 else { return nil }
        return (latitude, longitude)
    }
}
