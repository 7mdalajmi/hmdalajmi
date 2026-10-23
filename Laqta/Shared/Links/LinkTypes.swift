//
//  LinkTypes.swift
//  Laqta — Shared
//

import Foundation

nonisolated enum LinkForm: String, Codable, Sendable, CaseIterable {
    case video
    case post
    case article
    case product
    case place
    case page

    var label: String {
        switch self {
        case .video: "Video"
        case .post: "Post"
        case .article: "Article"
        case .product: "Product page"
        case .place: "Place"
        case .page: "Web page"
        }
    }

    var systemImage: String {
        switch self {
        case .video: "play.rectangle"
        case .post: "bubble.left.and.text.bubble.right"
        case .article: "doc.text"
        case .product: "bag"
        case .place: "mappin.and.ellipse"
        case .page: "globe"
        }
    }

    /// "Watch", "Read", "View", "Open"
    var primaryAction: String {
        switch self {
        case .video: "Watch"
        case .article: "Read"
        case .post, .product: "View"
        case .place, .page: "Open"
        }
    }

    var primarySymbol: String {
        switch self {
        case .video: "play.fill"
        case .article: "book"
        case .post, .product: "eye"
        case .place: "map"
        case .page: "arrow.up.right"
        }
    }

    /// Title of the timestamps card.
    var sectionsTitle: String {
        switch self {
        case .video: "Chapters"
        case .article: "Sections"
        default: "Key moments"
        }
    }
}

/// A link on its way into the library.
nonisolated struct LinkDraft: Sendable, Hashable {
    var url: URL
    var title: String
    var site: String
    var author: String?
    var duration: Double?
    var form: LinkForm
    /// Description, caption or the first part of the page text.
    var details: String?
    var publishedAt: Date?
    var views: Int?
    var sourceName: String?
    /// Downloaded preview image, staged in the App Group.
    var image: StagedMedia?
    var chapters: [Chapter] = []
    var placeNames: [String] = []
    var prices: [PriceRef] = []
    /// Longer text (page body or transcript) for the app's analysis.
    var bodyText: String?
    /// Preview image on the web (YouTube thumbnails are shown from YouTube, never stored).
    var imageURL: String?
    /// A YouTube link: its details come from YouTube's oEmbed.
    var isYouTube = false
    /// YouTube's details were loaded (or there are none to load, as for a channel).
    var hasYouTubeDetails = false
    /// The video was removed or made private.
    var isUnavailable = false

    init(url: URL) {
        self.url = url
        self.site = LinkDraft.displayHost(url)
        self.title = self.site
        self.form = LinkClassifier.form(for: url, ogType: nil)
        self.sourceName = LinkClassifier.sourceName(for: url)
    }

    static func displayHost(_ url: URL) -> String {
        var host = url.host(percentEncoded: false) ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        return host
    }
}

nonisolated enum LinkClassifier {
    static func form(for url: URL, ogType: String?) -> LinkForm {
        let host = LinkDraft.displayHost(url).lowercased()
        let path = url.path().lowercased()
        let type = ogType?.lowercased() ?? ""
        if host.hasSuffix("youtube.com") || host == "youtu.be" || host.hasSuffix("vimeo.com") || host.hasSuffix("tiktok.com") {
            return host.hasSuffix("youtube.com") && path.hasPrefix("/@") ? .page : .video
        }
        if host.hasSuffix("instagram.com") {
            return path.hasPrefix("/reel") ? .video : .post
        }
        if host == "x.com" || host.hasSuffix("twitter.com") || host.hasSuffix("threads.net") || host.hasSuffix("threads.com") || host.hasSuffix("snapchat.com") || host.hasSuffix("facebook.com") {
            return .post
        }
        if host.hasPrefix("maps.") || host.hasSuffix("maps.apple.com") || path.hasPrefix("/maps") || host == "goo.gl" && path.hasPrefix("/maps") || host == "maps.app.goo.gl" {
            return .place
        }
        if type.hasPrefix("video") { return .video }
        if type.contains("product") || host.contains("amazon.") || host.hasSuffix("noon.com") || path.contains("/product") || path.contains("/p/") && !host.hasSuffix("instagram.com") {
            return .product
        }
        if type == "article" || host.hasSuffix("wikipedia.org") || path.contains("/blog") || path.contains("/news") || path.contains("/article") || host.hasSuffix("medium.com") || host.hasSuffix("substack.com") {
            return .article
        }
        return .page
    }

    static func sourceName(for url: URL) -> String {
        let host = LinkDraft.displayHost(url).lowercased()
        switch true {
        case host.hasSuffix("youtube.com"), host == "youtu.be": return "YouTube"
        case host.hasSuffix("tiktok.com"): return "TikTok"
        case host.hasSuffix("instagram.com"): return "Instagram"
        case host == "x.com", host.hasSuffix("twitter.com"): return "X"
        case host.hasSuffix("threads.net"), host.hasSuffix("threads.com"): return "Threads"
        case host.hasSuffix("vimeo.com"): return "Vimeo"
        case host.hasSuffix("snapchat.com"): return "Snapchat"
        case host.hasSuffix("maps.apple.com"), host.hasPrefix("maps."), host == "maps.app.goo.gl": return "Maps"
        default: return "Safari"
        }
    }

    /// Finds the first web link in shared text ("Look at this https://…").
    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = normalizedURL(from: trimmed) { return direct }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for match in detector.matches(in: trimmed, options: [], range: range) {
            if let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url
            }
        }
        return nil
    }

    /// Accepts "youtube.com/watch?v=…" without a scheme.
    static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else { return nil }
        let candidate = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let host = url.host(), host.contains("."), host.count > 3 else { return nil }
        return url
    }
}
