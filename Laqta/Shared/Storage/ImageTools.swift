//
//  ImageTools.swift
//  Laqta — Shared
//
//  Reads image metadata and makes thumbnails with ImageIO, without decoding the full image.
//

import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import UniformTypeIdentifiers

/// What we learn from an image file without decoding it.
nonisolated struct ImageMetadata: Sendable, Hashable {
    var pixelWidth: Int
    var pixelHeight: Int
    var capturedAt: Date?
    var captureOffsetKnown: Bool
    var isScreenshot: Bool
    var typeIdentifier: String?
    /// EXIF sub-seconds of the capture time, in milliseconds.
    var subsecond: Int? = nil
    /// "Apple iPhone 16 Pro"
    var cameraModel: String? = nil

    var pixelCount: Int { pixelWidth * pixelHeight }
}

/// `UIImage` wrapper that can cross concurrency boundaries.
nonisolated struct ImageBox: @unchecked Sendable {
    #if canImport(UIKit)
    let image: UIImage
    #else
    let image: NSImage
    #endif

    init(cgImage: CGImage) {
        #if canImport(UIKit)
        image = UIImage(cgImage: cgImage)
        #else
        image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    #if canImport(UIKit)
    init(image: UIImage) { self.image = image }
    #else
    init(image: NSImage) { self.image = image }
    #endif
}

nonisolated enum ImageTools {
    private static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    static func metadata(at url: URL) -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }

        let typeIdentifier = CGImageSourceGetType(source) as String?
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any] else {
            return nil
        }

        var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) { swap(&width, &height) }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let comment = exif?[kCGImagePropertyExifUserComment] as? String
        let isScreenshot = comment?.localizedCaseInsensitiveContains("screenshot") ?? false

        let rawDate = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        let offset = (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifOffsetTime] as? String)
        let capturedAt = rawDate.flatMap { parseExifDate($0, offset: offset) }
        let rawSubsecond = (exif?[kCGImagePropertyExifSubsecTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifSubsecTimeDigitized] as? String)
        let make = (tiff?[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)

        return ImageMetadata(
            pixelWidth: width,
            pixelHeight: height,
            capturedAt: capturedAt,
            captureOffsetKnown: capturedAt != nil && offset != nil,
            isScreenshot: isScreenshot,
            typeIdentifier: typeIdentifier,
            subsecond: rawSubsecond.flatMap(parseSubsecond),
            cameraModel: cameraName(make: make, model: model)
        )
    }

    /// "123" → 123 ms, "5" → 500 ms, "04" → 40 ms.
    static func parseSubsecond(_ raw: String) -> Int? {
        let digits = raw.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let padded = (String(digits) + "000").prefix(3)
        return Int(padded)
    }

    /// "Apple iPhone 16 Pro" (the model often repeats the make).
    static func cameraName(make: String?, model: String?) -> String? {
        let make = make?.isEmpty == false ? make : nil
        let model = model?.isEmpty == false ? model : nil
        switch (make, model) {
        case let (make?, model?):
            return model.lowercased().hasPrefix(make.lowercased()) ? model : "\(make) \(model)"
        case let (nil, model?):
            return model
        case let (make?, nil):
            return make
        default:
            return nil
        }
    }

    /// The camera as people read it: "NIKON CORPORATION NIKON D800E" → "NIKON D800E",
    /// "OLYMPUS IMAGING CORP. E-M5" → "OLYMPUS E-M5". Stored names stay as the file wrote
    /// them, because duplicate keys are built from them.
    static func displayCameraName(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 2 else { return name }
        var index = 1
        while index < words.count, companyWords.contains(simplifiedWord(words[index])) {
            index += 1
        }
        guard index > 1 else { return name }
        var rest = Array(words[index...])
        // The model often repeats the brand.
        if let first = rest.first, simplifiedWord(first) == simplifiedWord(words[0]) {
            rest.removeFirst()
        }
        guard !rest.isEmpty else { return name }
        return ([words[0]] + rest).joined(separator: " ")
    }

    private static let companyWords: Set<String> = [
        "corporation", "corp", "co", "company", "ltd", "limited", "inc", "incorporated",
        "imaging", "electronics", "electric", "camera", "cameras", "ag", "gmbh", "llc", "optical"
    ]

    private static func simplifiedWord(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    /// Downsamples straight from the file. When `allowFullDecode` is false only an
    /// embedded thumbnail is used, which keeps the Share Extension far below its memory limit.
    static func makeThumbnail(from url: URL, maxPixelSize: Int, allowFullDecode: Bool = true) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: allowFullDecode,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: allowFullDecode,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Where the photo was taken, when the file carries GPS data.
    static func gpsCoordinate(at url: URL) -> (latitude: Double, longitude: Double)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else { return nil }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        let lat = latRef.uppercased() == "S" ? -latitude : latitude
        let lon = lonRef.uppercased() == "W" ? -longitude : longitude
        guard abs(lat) > 0.0001 || abs(lon) > 0.0001 else { return nil }
        return (lat, lon)
    }

    /// Camera make/model and the software that wrote the file.
    static func captureDevice(at url: URL) -> (make: String?, model: String?, software: String?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any] else {
            return (nil, nil, nil)
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return (
            tiff?[kCGImagePropertyTIFFMake] as? String,
            tiff?[kCGImagePropertyTIFFModel] as? String,
            tiff?[kCGImagePropertyTIFFSoftware] as? String
        )
    }

    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.82) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw MediaError.unreadable(.photo) }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw MediaError.unreadable(.photo) }
    }

    static func fileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, let type = UTType(filenameExtension: ext),
           type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .pdf) {
            return ext
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
           let identifier = CGImageSourceGetType(source) as String?,
           let preferred = UTType(identifier)?.preferredFilenameExtension {
            return preferred
        }
        return "jpg"
    }

    static func fileExtension(for data: Data) -> String {
        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
           let identifier = CGImageSourceGetType(source) as String?,
           let preferred = UTType(identifier)?.preferredFilenameExtension {
            return preferred
        }
        return "png"
    }

    static func parseExifDate(_ value: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = offset.flatMap(timeZone(fromOffset:)) ?? .current
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Parses EXIF offsets such as "+03:00".
    static func timeZone(fromOffset offset: String) -> TimeZone? {
        let trimmed = offset.trimmingCharacters(in: .whitespaces)
        guard let sign = trimmed.first, sign == "+" || sign == "-" else { return nil }
        let parts = trimmed.dropFirst().split(separator: ":")
        guard let hours = parts.first.flatMap({ Int($0) }) else { return nil }
        let minutes = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }
}

/// Off-main image loading for the UI.
nonisolated enum ImageLoader {
    /// Loads the stored thumbnail, regenerating it from the original when it is missing.
    @concurrent
    static func thumbnail(at thumbnailURL: URL, original: URL?, kind: MediaKind = .photo, duration: Double? = nil) async -> ImageBox? {
        let manager = FileManager.default
        if manager.fileExists(atPath: thumbnailURL.path(percentEncoded: false)),
           let image = ImageTools.makeThumbnail(from: thumbnailURL, maxPixelSize: MediaStore.thumbnailPixelSize) {
            return ImageBox(cgImage: image)
        }
        // Another device may have made the thumbnail already (iCloud sync).
        if CloudMediaStore.copyThumbnailIfAvailable(named: thumbnailURL.lastPathComponent, to: thumbnailURL),
           let image = ImageTools.makeThumbnail(from: thumbnailURL, maxPixelSize: MediaStore.thumbnailPixelSize) {
            return ImageBox(cgImage: image)
        }
        guard let original, manager.fileExists(atPath: original.path(percentEncoded: false)),
              let image = await MediaInspector.thumbnail(
                forFileAt: original,
                kind: kind,
                maxPixelSize: MediaStore.thumbnailPixelSize,
                allowFullDecode: true,
                duration: duration
              ) else {
            return nil
        }
        try? ImageTools.writeJPEG(image, to: thumbnailURL)
        return ImageBox(cgImage: image)
    }

    @concurrent
    static func image(at url: URL, maxPixelSize: Int) async -> ImageBox? {
        guard let image = ImageTools.makeThumbnail(from: url, maxPixelSize: maxPixelSize) else { return nil }
        return ImageBox(cgImage: image)
    }
}

/// Preview images shown straight from the web (YouTube thumbnails). They are cached
/// only as the server's HTTP cache headers allow, never saved into the library.
nonisolated enum RemoteImageLoader {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = URL.cachesDirectory.appending(path: "RemoteImages", directoryHint: .isDirectory)
        configuration.urlCache = URLCache(memoryCapacity: 12 * 1024 * 1024, diskCapacity: 48 * 1024 * 1024, directory: directory)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    @concurrent
    static func image(at url: URL, maxPixelSize: Int) async -> ImageBox? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let limit = 8_000_000
        var data = Data()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= Int64(limit) else { return nil }
            data.reserveCapacity(min(limit, Int(max(0, http.expectedContentLength))))
            for try await byte in bytes {
                guard data.count < limit, !Task.isCancelled else { return nil }
                data.append(byte)
            }
        } catch {
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return ImageBox(cgImage: image)
    }
}
