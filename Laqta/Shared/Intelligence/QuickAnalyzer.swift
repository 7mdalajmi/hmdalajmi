//
//  QuickAnalyzer.swift
//  Laqta — Shared
//
//  On-device photo understanding with Vision: text, labels, codes and where a shot came from.
//  The Share Extension runs it on the small thumbnail; the app runs it again in full.
//

import CoreGraphics
import CoreML
import Foundation
import Vision

nonisolated struct PhotoAnalysisInput: Sendable {
    /// Image to read (thumbnail in the extension, original in the app).
    let imageURL: URL
    /// The stored file (EXIF, GPS).
    let fileURL: URL
    let isScreenshot: Bool
    let capturedAt: Date?
    let addedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    /// A web page that was shared together with the image.
    let sharedURL: String?
}

nonisolated struct PhotoAnalysisOptions: Sendable {
    var readText = true
    var findSource = true
    var accurate = false
    var maxPixelSize = 1_024
    /// Background work stays off the Neural Engine and GPU.
    var cpuOnly = false

    static let quick = PhotoAnalysisOptions(readText: true, findSource: true, accurate: false, maxPixelSize: 640)
    static let full = PhotoAnalysisOptions(readText: true, findSource: true, accurate: true, maxPixelSize: 2_048)
}

nonisolated struct PhotoAnalysisResult: Sendable {
    var analysis: ShotAnalysis
    /// Raw classification identifiers (for folder suggestions).
    var labelIdentifiers: [String]
    var coordinate: (latitude: Double, longitude: Double)?
}

/// What Vision found in one image.
nonisolated struct ImageReading: Sendable {
    var identifiers: [(identifier: String, confidence: Float)] = []
    var lines: [String] = []
    var codeLinks: [String] = []
}

nonisolated enum VisionReader {
    @concurrent
    static func read(_ image: CGImage, readText: Bool, accurate: Bool, isScreen: Bool, cpuOnly: Bool) async -> ImageReading {
        var reading = ImageReading()

        // What is in the picture.
        var classify = ClassifyImageRequest()
        if cpuOnly { preferCPU(&classify) }
        if let observations = try? await classify.perform(on: image) {
            reading.identifiers = observations
                .filter { $0.confidence >= 0.3 }
                .sorted { $0.confidence > $1.confidence }
                .prefix(10)
                .map { ($0.identifier, $0.confidence) }
        }

        // Text.
        if readText {
            // Arabic and English are named outright rather than left to automatic
            // detection: on a receipt carrying Latin digits and one English word,
            // detection can settle on English and drop every Arabic line.
            var observations = await recognize(image, accurate: accurate, cpuOnly: cpuOnly, languages: Self.readingLanguages)
            if observations == nil {
                // This revision or recognition level does not take that pair.
                // Better Vision's own guess than no text at all.
                observations = await recognize(image, accurate: accurate, cpuOnly: cpuOnly, languages: nil)
            }
            if let observations {
                let minimumConfidence: Float = isScreen ? 0.3 : 0.5
                reading.lines = observations.compactMap { observation -> String? in
                    guard let candidate = observation.topCandidates(1).first,
                          candidate.confidence >= minimumConfidence else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespaces)
                    let letters = text.filter { $0.isLetter || $0.isNumber }.count
                    return letters >= 2 ? text : nil
                }
                // A few stray letters in a photo aren't text worth keeping.
                if !isScreen, reading.lines.joined().count < 8 {
                    reading.lines = []
                }
            }
        }

        // QR codes and barcodes that carry links.
        var barcodes = DetectBarcodesRequest()
        if cpuOnly { preferCPU(&barcodes) }
        if let observations = try? await barcodes.perform(on: image) {
            for observation in observations {
                if let payload = observation.payloadString, payload.lowercased().hasPrefix("http") {
                    reading.codeLinks.append(payload)
                }
            }
        }
        return reading
    }

    /// Arabic first, then English: the order is a priority, not a filter.
    static let readingLanguages: [Locale.Language] = [
        Locale.Language(identifier: "ar"),
        Locale.Language(identifier: "en-US")
    ]

    /// One text pass. `languages == nil` leaves the choice to Vision.
    /// Returns nil when the request itself failed, and [] when it simply found nothing —
    /// the caller needs to tell those apart before paying for a second pass.
    @concurrent
    static func recognize(
        _ image: CGImage,
        accurate: Bool,
        cpuOnly: Bool,
        languages: [Locale.Language]?
    ) async -> [RecognizedTextObservation]? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = accurate
        if let languages, !languages.isEmpty {
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = languages
        } else {
            request.automaticallyDetectsLanguage = true
        }
        if cpuOnly { preferCPU(&request) }
        return try? await request.perform(on: image)
    }

    /// Runs every stage of a request on the CPU (allowed in the background).
    static func preferCPU<Request: VisionRequest>(_ request: inout Request) {
        for (stage, devices) in request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { device in
                if case .cpu = device { return true }
                return false
            }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
    }
}

nonisolated enum QuickAnalyzer {
    @concurrent
    static func analyzePhoto(_ input: PhotoAnalysisInput, options: PhotoAnalysisOptions) async -> PhotoAnalysisResult {
        var analysis = ShotAnalysis()
        let coordinate = ImageTools.gpsCoordinate(at: input.fileURL)

        guard let image = ImageTools.makeThumbnail(from: input.imageURL, maxPixelSize: options.maxPixelSize) else {
            return PhotoAnalysisResult(analysis: analysis, labelIdentifiers: [], coordinate: coordinate)
        }

        let reading = await VisionReader.read(
            image,
            readText: options.readText,
            accurate: options.accurate,
            isScreen: input.isScreenshot,
            cpuOnly: options.cpuOnly
        )
        let identifiers = reading.identifiers.map(\.identifier)
        let lines = reading.lines

        let text = lines.joined(separator: "\n")
        if text.count >= 3 {
            analysis.text = text
        }
        analysis.entities = entities(in: text, codeLinks: reading.codeLinks, reference: input.capturedAt)
        analysis.labels = VisionLabels.display(identifiers)

        if options.findSource {
            analysis.source = SourceDetector.detect(
                lines: lines,
                entities: analysis.entities,
                labels: identifiers,
                input: input
            )
        }

        let heuristics = ShotHeuristics.describe(lines: lines, entities: analysis.entities, labels: identifiers, isScreenshot: input.isScreenshot, source: analysis.source)
        analysis.title = heuristics.title
        analysis.category = heuristics.category
        if let tag = heuristics.tag, !analysis.labels.contains(tag) {
            analysis.labels.insert(tag, at: 0)
        }
        analysis.analyzedAt = .now
        return PhotoAnalysisResult(analysis: analysis, labelIdentifiers: identifiers, coordinate: coordinate)
    }

    /// Dates, prices, phones… plus links carried by QR codes.
    static func entities(in text: String, codeLinks: [String], reference: Date?) -> [DetectedEntity] {
        var entities = EntityDetector.detect(in: text, reference: reference)
        for link in codeLinks {
            if let url = URL(string: link) {
                let entity = DetectedEntity(kind: .link, value: url.absoluteString, display: LinkDraft.displayHost(url))
                if !entities.contains(entity) { entities.append(entity) }
            }
        }
        return entities
    }
}

// MARK: - Source

nonisolated enum SourceDetector {
    static func detect(lines: [String], entities: [DetectedEntity], labels: [String], input: PhotoAnalysisInput) -> SourceRef? {
        let taken = input.capturedAt ?? input.addedAt
        let takenText = "Taken \(LaqtaFormat.shortDate(taken)) at \(LaqtaFormat.time(taken))"
        let joined = lines.joined(separator: " ").lowercased()

        if let shared = input.sharedURL, let url = URL(string: shared) {
            let host = LinkDraft.displayHost(url)
            return SourceRef(
                app: "Safari",
                headline: "Shared from Safari",
                detail: host + (url.path().count > 1 ? url.path() : ""),
                url: shared,
                reason: "Laqta kept the page link when you shared this from Safari."
            )
        }

        guard input.isScreenshot || looksLikeScreenshot(input) else {
            let device = ImageTools.captureDevice(at: input.fileURL)
            if let model = device.model, !model.isEmpty {
                let isPhone = (device.make ?? "").lowercased().contains("apple")
                return SourceRef(
                    app: "Camera",
                    headline: isPhone ? "Photo · Camera" : "Photo · \(model)",
                    detail: takenText,
                    url: nil,
                    reason: "Taken with \(model)."
                )
            }
            return SourceRef(app: "Photos", headline: "Photo", detail: takenText, url: nil, reason: nil)
        }

        func screenshot(_ app: String, _ reason: String, url: String? = nil, detail: String? = nil) -> SourceRef {
            SourceRef(app: app, headline: "Screenshot of \(app)", detail: detail ?? takenText, url: url, reason: reason)
        }

        if joined.contains("boarding pass") || (joined.contains("gate") && joined.contains("seat")) || joined.contains("add to apple wallet") {
            return screenshot("Wallet", "Recognized from the boarding pass layout in the screenshot.")
        }
        if (joined.contains("directions") || joined.contains("route") || joined.contains("arrival")) && (joined.contains(" min") || joined.contains(" km")) {
            return screenshot("Maps", "Recognized from the route details in the screenshot.")
        }
        if joined.contains("inbox") || (joined.contains("from:") && joined.contains("to:")) || joined.contains("reply all") {
            return screenshot("Mail", "Recognized from the email header in the screenshot.")
        }
        if joined.contains("imessage") || joined.contains("text message") || joined.contains("delivered") && joined.contains("read") {
            return screenshot("Messages", "Recognized from the conversation layout.")
        }
        // A web address near the top means a browser.
        let top = lines.prefix(4).joined(separator: " ")
        if let link = entities.first(where: { $0.kind == .link }), top.contains(LinkDraft.displayHost(URL(string: link.value) ?? URL(fileURLWithPath: "/")).prefix(6)) {
            return screenshot("Safari", "Laqta found the page address at the top of the screenshot.", url: link.value, detail: link.display)
        }
        if let domainLine = lines.prefix(3).first(where: { looksLikeDomain($0) }) {
            let url = "https://\(domainLine.lowercased())"
            return screenshot("Safari", "Laqta found the page address at the top of the screenshot.", url: url, detail: domainLine.lowercased())
        }
        if joined.contains("notes") && (lines.first?.lowercased().contains("notes") ?? false) {
            return screenshot("Notes", "Recognized from the Notes layout.")
        }
        if let link = entities.first(where: { $0.kind == .link }) {
            return SourceRef(app: "Web", headline: "Screenshot · Web", detail: link.display, url: link.value, reason: "A web address appears in the screenshot.")
        }
        return SourceRef(app: "Screenshot", headline: "Screenshot", detail: takenText, url: nil, reason: nil)
    }

    static func looksLikeScreenshot(_ input: PhotoAnalysisInput) -> Bool {
        // iPhone screen sizes at 3× without camera data.
        let width = min(input.pixelWidth, input.pixelHeight)
        let height = max(input.pixelWidth, input.pixelHeight)
        let knownWidths: Set<Int> = [1_170, 1_179, 1_206, 1_242, 1_260, 1_284, 1_290, 1_320, 828, 750, 1_125, 1_080]
        return knownWidths.contains(width) && height >= 2 * width - 200 && ImageTools.captureDevice(at: input.fileURL).model == nil
    }

    static func looksLikeDomain(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5, trimmed.count <= 60, !trimmed.contains(" ") else { return false }
        let tlds = [".com", ".net", ".org", ".io", ".co", ".app", ".kw", ".sa", ".ae", ".qa", ".bh", ".om", ".uk", ".me", ".store", ".shop"]
        let lower = trimmed.lowercased()
        return tlds.contains { lower.hasSuffix($0) || lower.contains($0 + "/") }
    }
}

// MARK: - Titles

nonisolated enum ShotHeuristics {
    struct Description {
        var title: String?
        var category: String?
        var tag: String?
    }

    static func describe(lines: [String], entities: [DetectedEntity], labels: [String], isScreenshot: Bool, source: SourceRef?) -> Description {
        let joined = lines.joined(separator: " ").lowercased()
        var result = Description()

        if joined.contains("boarding pass") || (joined.contains("gate") && joined.contains("seat")) {
            result.category = "Boarding pass"
            result.tag = "Boarding pass"
            if let flight = entities.first(where: { $0.kind == .flight }) {
                result.title = "Flight \(flight.display)"
            } else {
                result.title = "Boarding pass"
            }
            return result
        }
        if joined.contains("reservation") || joined.contains("booking confirmed") || joined.contains("check-in") && joined.contains("check-out") {
            result.category = "Reservation"
            result.tag = "Reservation"
            result.title = lines.first(where: { $0.count > 6 && $0.count < 48 && !$0.lowercased().contains("reservation") })
            return result
        }
        if joined.contains("warranty") || joined.contains("receipt") || joined.contains("invoice") || joined.contains("فاتورة") {
            result.category = joined.contains("warranty") ? "Warranty" : "Receipt"
            result.tag = result.category
            result.title = result.category
            return result
        }
        if entities.contains(where: { $0.kind == .price }), joined.contains("add to cart") || joined.contains("buy") || joined.contains("delivery") || joined.contains("ml") {
            result.category = "Product page"
            result.tag = "Product page"
            result.title = lines.first(where: { line in line.count > 3 && line.count < 48 && !SourceDetector.looksLikeDomain(line) && EntityDetector.prices(in: line).isEmpty })
            return result
        }
        if labels.contains(where: { ["document", "text", "receipt"].contains($0) }) || lines.count >= 8 {
            result.category = isScreenshot ? "Text" : "Document"
            result.title = lines.first(where: { $0.count > 4 && $0.count < 44 })
            return result
        }
        if labels.contains(where: { VisionLabels.placeLike.contains($0) }) {
            result.category = "Place"
            return result
        }
        if labels.contains(where: { ["food", "meal", "dessert", "drink"].contains($0) }) {
            result.category = "Food"
            return result
        }
        return result
    }
}
