//
//  Analysis.swift
//  Laqta — Shared
//
//  What Laqta understood about a photo or a link. Stored as JSON on the item.
//

import Foundation

nonisolated struct ShotAnalysis: Codable, Sendable, Hashable {
    var version: Int = 1
    /// Short name for the pill ("Kuwait Towers", "Boarding pass").
    var title: String?
    /// Second line ("Landmark · Arabian Gulf Street").
    var subtitle: String?
    /// "Landmark photo", "Product page", "Boarding pass".
    var category: String?
    /// Short labels shown as tags.
    var labels: [String] = []
    /// Recognized text.
    var text: String?
    var entities: [DetectedEntity] = []
    /// Where a photo was taken, or the place a screenshot shows.
    var place: PlaceRef?
    /// Places mentioned in a link.
    var places: [PlaceRef] = []
    var source: SourceRef?
    var summary: [String] = []
    var sections: [Chapter] = []
    var sectionsTitle: String?
    var prices: [PriceRef] = []
    var tips: [String] = []
    var questions: [String] = []
    /// "From the video's captions, chapters and description".
    var basis: String?
    var analyzedAt: Date?
    var usedLanguageModel: Bool = false
    /// Spoken words in a saved video, with their start time.
    var transcript: [TranscriptLine]? = nil
    /// Language of the transcript ("en-US", "ar-SA").
    var transcriptLanguage: String? = nil
    /// Why a video has no transcript ("No speech", "Arabic isn't available on this device yet").
    var transcriptNote: String? = nil
}

nonisolated struct TranscriptLine: Codable, Sendable, Hashable, Identifiable {
    var seconds: Double
    var text: String
    var id: String { "\(seconds)|\(text.prefix(24))" }
}

nonisolated struct DetectedEntity: Codable, Sendable, Hashable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case date
        case address
        case phone
        case link
        case price
        case flight
        case email
        case code
    }

    var kind: Kind
    /// Raw value (URL, phone number, flight number…).
    var value: String
    /// What the chip shows.
    var display: String
    var date: Date?
    var duration: Double?
    var allDay: Bool = false

    var id: String { "\(kind.rawValue)|\(value)" }

    var systemImage: String {
        switch kind {
        case .date: "calendar"
        case .address: "mappin.and.ellipse"
        case .phone: "phone"
        case .link: "link"
        case .price: "tag"
        case .flight: "airplane"
        case .email: "envelope"
        case .code: "number"
        }
    }
}

nonisolated struct PlaceRef: Codable, Sendable, Hashable, Identifiable {
    var name: String
    /// "Sharq, Kuwait City"
    var detail: String?
    /// "Landmark"
    var category: String?
    /// "372 m telecom tower", "Departure airport · KWI"
    var note: String?
    var latitude: Double?
    var longitude: Double?
    /// "GPS", "From text", "Mentioned"
    var origin: String?
    /// Seconds into a video where the place is mentioned.
    var mentionedAt: Double?

    var id: String { "\(name)|\(latitude ?? 0)|\(longitude ?? 0)" }
    var hasCoordinate: Bool { latitude != nil && longitude != nil }

    /// The area line for display, unless it only repeats the name
    /// (a photo taken outside a town is named after its area).
    var distinctDetail: String? {
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty,
              detail.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
        else { return nil }
        return detail
    }
}

nonisolated struct SourceRef: Codable, Sendable, Hashable {
    /// "Safari", "Wallet", "Maps", "Notes", "Mail", "Camera", "YouTube", "Web"
    var app: String
    /// "Screenshot of Wallet", "Shared from Safari", "Photo · Camera"
    var headline: String
    /// Domain or "Taken Sep 10 at 9:14 PM"
    var detail: String?
    var url: String?
    /// Why Laqta thinks so.
    var reason: String?

    var systemImage: String {
        switch app {
        case "Safari": "safari"
        case "Wallet": "wallet.pass"
        case "Maps": "map"
        case "Notes": "note.text"
        case "Mail": "envelope"
        case "Messages": "message"
        case "Camera": "camera"
        case "YouTube", "TikTok", "Vimeo": "play.rectangle"
        case "Instagram", "X", "Threads", "Snapchat": "bubble.left.and.text.bubble.right"
        case "Calendar": "calendar"
        case "Screen Recording": "record.circle"
        case "Video": "video"
        case "Files": "doc.richtext"
        case "Photos": "photo"
        case "Screenshot": "camera.viewfinder"
        default: "globe"
        }
    }
}

nonisolated struct Chapter: Codable, Sendable, Hashable, Identifiable {
    /// Seconds into a video; negative for sections without a time.
    var seconds: Double
    var title: String
    /// PDF page (1-based) for document sections.
    var page: Int? = nil

    var id: String { "\(seconds)|\(page ?? 0)|\(title)" }
    var isTimed: Bool { seconds >= 0 }
}

nonisolated struct PriceRef: Codable, Sendable, Hashable, Identifiable {
    var label: String
    var value: String
    var id: String { "\(label)|\(value)" }
}

// MARK: - Search

nonisolated enum SearchIndex {
    /// Lowercased text that search matches against.
    static func text(for item: Shot, analysis: ShotAnalysis?) -> String {
        var parts: [String] = []
        if let title = item.linkTitle { parts.append(title) }
        if let site = item.linkSite { parts.append(site) }
        if let author = item.linkAuthor { parts.append(author) }
        if let details = item.linkDetails { parts.append(String(details.prefix(4_000))) }
        if !item.note.isEmpty { parts.append(item.note) }
        if let source = item.sourceName { parts.append(source) }
        if let title = item.documentTitle { parts.append(title) }
        if let name = item.originalName { parts.append(name) }
        if let camera = item.cameraModel { parts.append(camera) }
        if let analysis {
            parts.append(contentsOf: [analysis.title, analysis.subtitle, analysis.category, analysis.text].compactMap { $0 })
            parts.append(contentsOf: analysis.labels)
            parts.append(contentsOf: analysis.entities.map(\.display))
            if let place = analysis.place {
                parts.append(contentsOf: [place.name, place.detail, place.category].compactMap { $0 })
            }
            for place in analysis.places {
                parts.append(contentsOf: [place.name, place.detail].compactMap { $0 })
            }
            if let source = analysis.source {
                parts.append(contentsOf: [source.app, source.detail, source.url].compactMap { $0 })
            }
            parts.append(contentsOf: analysis.summary)
            parts.append(contentsOf: analysis.sections.map(\.title))
            parts.append(contentsOf: analysis.prices.map { "\($0.label) \($0.value)" })
            parts.append(contentsOf: analysis.tips)
            if let transcript = analysis.transcript {
                parts.append(String(transcript.map(\.text).joined(separator: " ").prefix(8_000)))
            }
        }
        return normalize(parts.joined(separator: "\n"))
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
