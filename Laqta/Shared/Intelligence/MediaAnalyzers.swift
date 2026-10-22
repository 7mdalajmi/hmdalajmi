//
//  MediaAnalyzers.swift
//  Laqta — Shared
//
//  On-device understanding of saved videos (frames: text, labels, codes, location)
//  and PDFs (text layer, scanned pages, document type).
//

import CoreGraphics
import Foundation
import PDFKit

// MARK: - Video

nonisolated struct VideoAnalysisInput: Sendable {
    let fileURL: URL
    let duration: Double
    let isScreenRecording: Bool
    let capturedAt: Date?
    let addedAt: Date
    let latitude: Double?
    let longitude: Double?
    let cameraModel: String?
}

nonisolated enum VideoAnalyzer {
    /// Reads `frameCount` frames spread over the video.
    @concurrent
    static func analyze(_ input: VideoAnalysisInput, frameCount: Int, options: PhotoAnalysisOptions) async -> PhotoAnalysisResult {
        var analysis = ShotAnalysis()
        var coordinate: (latitude: Double, longitude: Double)?
        if let latitude = input.latitude, let longitude = input.longitude {
            coordinate = (latitude, longitude)
        }
        let frames = await MediaInspector.videoFrames(
            at: input.fileURL,
            count: frameCount,
            duration: input.duration,
            maxPixelSize: options.maxPixelSize
        )

        var scores: [String: Float] = [:]
        var lines: [String] = []
        var seen = Set<String>()
        var codeLinks: [String] = []
        var moments: [Chapter] = []
        for frame in frames {
            let reading = await VisionReader.read(
                frame.image,
                readText: options.readText,
                accurate: options.accurate,
                isScreen: input.isScreenRecording,
                cpuOnly: options.cpuOnly
            )
            for entry in reading.identifiers {
                scores[entry.identifier, default: 0] += entry.confidence
            }
            var fresh: [String] = []
            for line in reading.lines where seen.insert(SearchIndex.normalize(line)).inserted {
                fresh.append(line)
            }
            lines.append(contentsOf: fresh)
            // In a screen recording, a new screen of text is a moment worth jumping to.
            if input.isScreenRecording, fresh.count >= 3,
               let heading = fresh.first(where: { $0.count >= 6 && $0.count <= 60 && !SourceDetector.looksLikeDomain($0) }) {
                moments.append(Chapter(seconds: frame.seconds, title: heading))
            }
            for link in reading.codeLinks where !codeLinks.contains(link) {
                codeLinks.append(link)
            }
        }

        let identifiers = scores.sorted { $0.value > $1.value }.prefix(10).map(\.key)
        let text = String(lines.joined(separator: "\n").prefix(8_000))
        if text.count >= 3 {
            analysis.text = text
        }
        analysis.entities = QuickAnalyzer.entities(in: text, codeLinks: codeLinks, reference: input.capturedAt)
        analysis.labels = VisionLabels.display(identifiers)
        analysis.source = source(for: input)
        if moments.count >= 2 {
            analysis.sections = Array(moments.prefix(8))
            analysis.sectionsTitle = "Key moments"
        }

        let heuristics = ShotHeuristics.describe(
            lines: lines,
            entities: analysis.entities,
            labels: identifiers,
            isScreenshot: input.isScreenRecording,
            source: analysis.source
        )
        analysis.title = heuristics.title
        analysis.category = heuristics.category ?? (input.isScreenRecording ? "Screen recording" : "Video")
        if let tag = heuristics.tag, !analysis.labels.contains(tag) {
            analysis.labels.insert(tag, at: 0)
        }
        analysis.analyzedAt = .now
        return PhotoAnalysisResult(analysis: analysis, labelIdentifiers: identifiers, coordinate: coordinate)
    }

    static func source(for input: VideoAnalysisInput) -> SourceRef {
        let taken = input.capturedAt ?? input.addedAt
        let takenText = "Recorded \(LaqtaFormat.shortDate(taken)) at \(LaqtaFormat.time(taken))"
        if input.isScreenRecording {
            return SourceRef(
                app: "Screen Recording",
                headline: "Screen recording",
                detail: takenText,
                url: nil,
                reason: "No camera details, and the video has the screen's shape."
            )
        }
        if let model = input.cameraModel {
            return SourceRef(app: "Camera", headline: "Video · Camera", detail: takenText, url: nil, reason: "Recorded with \(ImageTools.displayCameraName(model)).")
        }
        return SourceRef(app: "Video", headline: "Video", detail: takenText, url: nil, reason: nil)
    }
}

// MARK: - PDF

nonisolated struct DocumentAnalysisInput: Sendable {
    let fileURL: URL
    let title: String?
    let fileName: String?
    let pageCount: Int
    let createdAt: Date?
    let addedAt: Date
}

nonisolated struct DocumentText: Sendable {
    /// Text per page (1-based page numbers).
    var pages: [(page: Int, text: String)] = []
    /// Pages without a text layer (scans).
    var scannedPages: [Int] = []
    var pageCount = 0
    var isLocked = false

    var joined: String {
        pages.map(\.text).joined(separator: "\n\n")
    }
}

nonisolated enum DocumentAnalyzer {
    /// The PDF's own text for the first pages. Fast, and safe in the Share Extension.
    static func textLayer(of url: URL, maxPages: Int, maxCharacters: Int) -> DocumentText? {
        guard let document = PDFDocument(url: url) else { return nil }
        var result = DocumentText()
        result.pageCount = document.pageCount
        result.isLocked = document.isLocked
        guard !document.isLocked else { return result }
        var total = 0
        for index in 0..<min(document.pageCount, maxPages) {
            guard total < maxCharacters else { break }
            let raw = document.page(at: index)?.string ?? ""
            let text = clean(raw)
            if text.filter({ $0.isLetter }).count < 20 {
                result.scannedPages.append(index + 1)
                continue
            }
            let slice = String(text.prefix(maxCharacters - total))
            total += slice.count
            result.pages.append((index + 1, slice))
        }
        return result
    }

    /// Reads scanned pages with Vision.
    @concurrent
    static func recognize(url: URL, pages: [Int], options: PhotoAnalysisOptions) async -> [(page: Int, text: String)] {
        var results: [(page: Int, text: String)] = []
        for page in pages {
            guard let image = renderPage(url: url, page: page, maxPixelSize: 2_200) else { continue }
            let reading = await VisionReader.read(image, readText: true, accurate: true, isScreen: true, cpuOnly: options.cpuOnly)
            let text = reading.lines.joined(separator: "\n")
            if text.filter({ $0.isLetter }).count >= 20 {
                results.append((page, text))
            }
        }
        return results
    }

    private static func renderPage(url: URL, page: Int, maxPixelSize: Int) -> CGImage? {
        guard let document = PDFDocument(url: url), let pdfPage = document.page(at: page - 1) else { return nil }
        return MediaInspector.render(pdfPage, maxPixelSize: maxPixelSize)
    }

    /// Text, dates, prices, headings and what kind of document it is.
    /// `ocrPages` limits how many scanned pages are read (0 in the Share Extension).
    @concurrent
    static func analyze(_ input: DocumentAnalysisInput, maxPages: Int, ocrPages: Int, options: PhotoAnalysisOptions) async -> (result: PhotoAnalysisResult, body: String, scanned: Bool) {
        var analysis = ShotAnalysis()
        var text = textLayer(of: input.fileURL, maxPages: maxPages, maxCharacters: 120_000) ?? DocumentText()
        var scanned = false
        if ocrPages > 0, text.joined.count < 400, !text.scannedPages.isEmpty {
            let recognized = await recognize(url: input.fileURL, pages: Array(text.scannedPages.prefix(ocrPages)), options: options)
            scanned = !recognized.isEmpty
            text.pages.append(contentsOf: recognized)
            text.pages.sort { $0.page < $1.page }
        }

        let body = text.joined
        let preview = String(body.prefix(20_000))
        if preview.count >= 3 {
            analysis.text = preview
        }
        analysis.entities = EntityDetector.detect(in: String(body.prefix(40_000)), reference: input.createdAt)

        let headings = self.headings(in: text)
        if headings.count >= 2 {
            analysis.sections = headings
            analysis.sectionsTitle = "Contents"
        }
        let kind = DocumentHeuristics.kind(of: body, fileName: input.fileName)
        analysis.category = kind?.label ?? "Document"
        if let kind {
            analysis.labels = [kind.label]
        }
        analysis.title = input.title ?? headings.first?.title ?? firstTitleLine(in: text)
        let pages = LaqtaFormat.count(max(text.pageCount, input.pageCount), "page", "pages")
        analysis.source = SourceRef(
            app: "Files",
            headline: "PDF · \(pages)",
            detail: input.createdAt.map { "Created \(LaqtaFormat.shortDate($0))" } ?? "Saved \(LaqtaFormat.shortDate(input.addedAt))",
            url: nil,
            reason: text.isLocked ? "This PDF is protected with a password." : (text.pages.isEmpty ? "This PDF has no readable text." : nil)
        )
        analysis.analyzedAt = .now
        let identifiers = kind.map { [$0.rawValue] } ?? []
        return (PhotoAnalysisResult(analysis: analysis, labelIdentifiers: identifiers, coordinate: nil), body, scanned)
    }

    /// Short lines that read like section titles, with their page.
    static func headings(in text: DocumentText, limit: Int = 10) -> [Chapter] {
        var result: [Chapter] = []
        var seen = Set<String>()
        for entry in text.pages {
            for rawLine in entry.text.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard isHeading(line), seen.insert(SearchIndex.normalize(line)).inserted else { continue }
                result.append(Chapter(seconds: -1, title: line, page: entry.page))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    static func isHeading(_ line: String) -> Bool {
        guard line.count >= 4, line.count <= 60 else { return false }
        guard let last = line.last, !".,;:،".contains(last) else { return false }
        let letters = line.filter(\.isLetter)
        guard letters.count >= 3, Double(letters.count) / Double(line.count) > 0.6 else { return false }
        let words = line.split(separator: " ")
        guard words.count <= 8 else { return false }
        // Numbered ("2. Payment terms"), all caps, or title case.
        if let first = words.first, first.last == "." || first.last == ")", first.dropLast().allSatisfy(\.isNumber) { return true }
        if letters.allSatisfy({ !$0.isLowercase }) && letters.contains(where: \.isUppercase) { return true }
        let capitalized = words.filter { $0.first?.isUppercase == true }.count
        return words.count >= 2 && Double(capitalized) / Double(words.count) >= 0.75
    }

    private static func firstTitleLine(in text: DocumentText) -> String? {
        for entry in text.pages {
            for rawLine in entry.text.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.count >= 4, line.count <= 70, line.filter(\.isLetter).count >= 4 {
                    return line
                }
            }
        }
        return nil
    }

    static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Recognizes common document types from their words.
nonisolated enum DocumentHeuristics {
    enum Kind: String, Sendable, CaseIterable {
        case invoice
        case receipt
        case ticket
        case boardingPass
        case booking
        case contract
        case statement
        case certificate
        case resume
        case menu
        case manual
        case report
        case form

        var label: String {
            switch self {
            case .invoice: "Invoice"
            case .receipt: "Receipt"
            case .ticket: "Ticket"
            case .boardingPass: "Boarding pass"
            case .booking: "Reservation"
            case .contract: "Contract"
            case .statement: "Statement"
            case .certificate: "Certificate"
            case .resume: "Résumé"
            case .menu: "Menu"
            case .manual: "Manual"
            case .report: "Report"
            case .form: "Form"
            }
        }

        var systemImage: String {
            switch self {
            case .invoice, .receipt, .statement: "doc.text.below.ecg"
            case .ticket: "ticket"
            case .boardingPass: "airplane"
            case .booking: "calendar.badge.checkmark"
            case .contract: "signature"
            case .certificate: "rosette"
            case .resume: "person.text.rectangle"
            case .menu: "fork.knife"
            case .manual: "book.closed"
            case .report: "chart.bar.doc.horizontal"
            case .form: "list.bullet.rectangle"
            }
        }

        /// Words that point to this kind, with their weight.
        var keywords: [(String, Int)] {
            switch self {
            case .invoice: [("invoice", 4), ("فاتورة", 4), ("tax invoice", 5), ("bill to", 3), ("vat", 2), ("subtotal", 2), ("amount due", 3)]
            case .receipt: [("receipt", 4), ("إيصال", 4), ("total paid", 3), ("thank you for your purchase", 3), ("cashier", 2), ("change", 1)]
            case .ticket: [("ticket", 3), ("تذكرة", 3), ("admit one", 4), ("seat", 1), ("entry", 1), ("event", 1)]
            case .boardingPass: [("boarding pass", 6), ("بطاقة صعود", 6), ("gate", 2), ("boarding", 2), ("flight", 2), ("seat", 1)]
            case .booking: [("reservation", 4), ("booking confirmation", 5), ("حجز", 4), ("check-in", 2), ("check-out", 2), ("confirmation number", 3)]
            case .contract: [("agreement", 4), ("contract", 4), ("عقد", 4), ("hereinafter", 4), ("terms and conditions", 2), ("signature", 2), ("party", 1)]
            case .statement: [("statement", 3), ("كشف حساب", 5), ("opening balance", 4), ("closing balance", 4), ("account number", 2)]
            case .certificate: [("certificate", 4), ("شهادة", 4), ("this is to certify", 5), ("awarded", 2)]
            case .resume: [("curriculum vitae", 5), ("resume", 3), ("السيرة الذاتية", 5), ("work experience", 3), ("education", 2), ("skills", 2)]
            case .menu: [("menu", 3), ("قائمة الطعام", 5), ("appetizers", 3), ("desserts", 2), ("beverages", 2), ("main course", 3)]
            case .manual: [("user guide", 4), ("user manual", 5), ("دليل المستخدم", 5), ("installation", 2), ("troubleshooting", 3), ("safety instructions", 3)]
            case .report: [("report", 3), ("تقرير", 3), ("executive summary", 4), ("findings", 2), ("conclusion", 2), ("methodology", 3)]
            case .form: [("application form", 5), ("نموذج", 3), ("please fill", 3), ("date of birth", 2), ("applicant", 2)]
            }
        }
    }

    static func kind(of text: String, fileName: String?) -> Kind? {
        let haystack = SearchIndex.normalize(String(text.prefix(12_000)) + " " + (fileName ?? ""))
        var best: (kind: Kind, score: Int)?
        for kind in Kind.allCases {
            let score = kind.keywords.reduce(0) { total, entry in
                haystack.contains(SearchIndex.normalize(entry.0)) ? total + entry.1 : total
            }
            if score >= 4, score > (best?.score ?? 0) {
                best = (kind, score)
            }
        }
        return best?.kind
    }
}
