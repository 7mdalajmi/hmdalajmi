//
//  LinkReader.swift
//  Laqta — Shared
//
//  Opens a link and reads what's inside: title, preview, author, length, description,
//  chapters, places and prices. Deep reads add the page text. YouTube links get their
//  details from YouTube's oEmbed instead (see YouTubeReader).
//

import Foundation
import LinkPresentation
import UniformTypeIdentifiers

nonisolated struct FetchedPage: Sendable {
    let finalURL: URL
    let html: String
}

nonisolated struct OEmbedInfo: Sendable {
    var title: String?
    var author: String?
    var thumbnail: String?
    var duration: Double?
    var description: String?
}

nonisolated struct MetadataSummary: Sendable {
    var title: String?
    var imageData: Data?
}

nonisolated enum WebFetcher {
    static let safariAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
    static let crawlerAgent = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9,ar;q=0.8"]
        return URLSession(configuration: configuration)
    }()

    @concurrent
    static func page(_ url: URL, crawler: Bool = false) async -> FetchedPage? {
        var request = URLRequest(url: url)
        request.setValue(crawler ? crawlerAgent : safariAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, http) = await boundedData(for: request, limit: 4_000_000) else { return nil }
        let mime = (http.mimeType ?? "").lowercased()
        guard mime.isEmpty || mime.contains("html") || mime.contains("xml") else { return nil }
        let html = String(decoding: data.prefix(4_000_000), as: UTF8.self)
        return FetchedPage(finalURL: http.url ?? url, html: html)
    }

    @concurrent
    static func data(_ url: URL, limit: Int = 12_000_000) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(safariAgent, forHTTPHeaderField: "User-Agent")
        return await boundedData(for: request, limit: limit)?.0
    }

    /// Enforce the memory limit while receiving bytes. Checking after `data(for:)`
    /// has already loaded an oversized response can terminate the share extension.
    private static func boundedData(for request: URLRequest, limit: Int) async -> (Data, HTTPURLResponse)? {
        guard limit > 0, let scheme = request.url?.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= Int64(limit) else { return nil }
            var data = Data()
            data.reserveCapacity(min(limit, Int(max(0, http.expectedContentLength))))
            for try await byte in bytes {
                guard data.count < limit, !Task.isCancelled else { return nil }
                data.append(byte)
            }
            return (data, http)
        } catch {
            return nil
        }
    }

    @concurrent
    static func json(_ url: URL) async -> [String: Any]? {
        guard let data = await data(url, limit: 2_000_000),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    @concurrent
    static func oEmbed(for url: URL) async -> OEmbedInfo? {
        let host = LinkDraft.displayHost(url).lowercased()
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url.absoluteString
        let endpoint: String
        if host.hasSuffix("tiktok.com") {
            endpoint = "https://www.tiktok.com/oembed?url=\(encoded)"
        } else if host.hasSuffix("vimeo.com") {
            endpoint = "https://vimeo.com/api/oembed.json?url=\(encoded)"
        } else if host == "x.com" || host.hasSuffix("twitter.com") {
            endpoint = "https://publish.twitter.com/oembed?omit_script=true&url=\(encoded)"
        } else {
            return nil
        }
        guard let endpointURL = URL(string: endpoint), let object = await json(endpointURL) else { return nil }
        var info = OEmbedInfo()
        info.title = object["title"] as? String
        info.author = object["author_name"] as? String
        info.thumbnail = object["thumbnail_url"] as? String
        info.duration = (object["duration"] as? NSNumber)?.doubleValue
        info.description = object["description"] as? String
        if info.title == nil, let html = object["html"] as? String {
            // Tweets: the text is inside the blockquote.
            info.title = HTMLText.readableText(html).components(separatedBy: "\n").first
        }
        return info
    }
}

/// Reads a link for Save to Laqta (quick) or for the app's analysis (deep).
enum LinkReader {
    static func read(_ original: URL, deep: Bool, downloadImage: Bool = true) async -> LinkDraft {
        if YouTubeLink.isYouTube(original) {
            return await YouTubeReader.read(original)
        }
        var url = original
        var draft = LinkDraft(url: original)
        let requestURL = original
        let crawler = prefersCrawler(original)

        async let pageTask = WebFetcher.page(requestURL, crawler: crawler)
        async let oEmbedTask = WebFetcher.oEmbed(for: requestURL)
        let metadata = await linkMetadata(for: requestURL)
        let page = await pageTask
        let oEmbed = await oEmbedTask

        // A short link that leads to YouTube: YouTube's page isn't read.
        if let finalURL = page?.finalURL, YouTubeLink.isYouTube(finalURL) {
            return await YouTubeReader.read(finalURL)
        }
        if let finalURL = page?.finalURL, finalURL.host() != nil, finalURL != url, !isConsentPage(finalURL) {
            url = finalURL
            draft.url = finalURL
            draft.site = LinkDraft.displayHost(finalURL)
        }

        let info = page.map { HTMLText.parse($0.html, readBody: deep) } ?? PageInfo()
        draft.form = LinkClassifier.form(for: url, ogType: info.ogType)
        draft.sourceName = LinkClassifier.sourceName(for: url)

        // Title.
        let candidates = [oEmbed?.title, info.meta["og:title"], metadata?.title, info.productName, info.title]
        if let title = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) {
            draft.title = cleanTitle(title, site: info.siteName)
        }
        draft.author = oEmbed?.author ?? info.author.flatMap { author in
            author.hasPrefix("http") || author.lowercased().hasPrefix("contributors to") ? nil : author
        }
        if draft.author == nil, draft.form == .post, let handle = socialHandle(from: url) {
            draft.author = handle
        }
        draft.duration = oEmbed?.duration ?? info.duration
        draft.publishedAt = info.published
        var details = [oEmbed?.description, info.ldDescription, info.description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        // Instagram captions come as "123 likes - user on date: "caption"".
        if draft.sourceName == "Instagram", let text = details, let range = text.range(of: ": \"") {
            details = String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" ."))
        }
        draft.details = details.map { String($0.prefix(6_000)) }

        // What's inside (quick).
        let searchable = [draft.title, details ?? ""].joined(separator: "\n")
        draft.chapters = ChapterParser.chapters(in: details ?? "")
        draft.placeNames = PlaceNameFinder.names(in: searchable, limit: 8)
        if let place = info.ldPlace, !draft.placeNames.contains(place.name) {
            draft.placeNames.insert(place.name, at: 0)
        }
        var prices = EntityDetector.priceRows(in: details ?? "")
        if let price = info.price {
            prices.insert(PriceRef(label: info.productName ?? draft.title, value: price), at: 0)
        }
        draft.prices = Array(prices.prefix(6))

        if deep {
            var body: [String] = []
            if let text = info.bodyText, draft.form != .video, text.count > 200 {
                body.append(text)
            }
            if !info.ingredients.isEmpty {
                body.append("Ingredients: " + info.ingredients.joined(separator: ", "))
            }
            draft.bodyText = body.isEmpty ? nil : body.joined(separator: "\n\n")
            if draft.chapters.isEmpty, draft.form == .article {
                draft.chapters = info.headings.enumerated().map { Chapter(seconds: -Double($0.offset + 1), title: $0.element) }
            }
        }

        // Preview image.
        if downloadImage {
            draft.image = await previewImage(
                metadata: metadata,
                candidates: [
                    oEmbed?.thumbnail,
                    info.image.flatMap { absolute($0, base: url) }
                ]
            )
        }
        return draft
    }

    // MARK: Pieces

    /// LinkPresentation title and preview image (the image is only a fallback).
    private static func linkMetadata(for url: URL) async -> MetadataSummary? {
        let provider = LPMetadataProvider()
        provider.timeout = 9
        provider.shouldFetchSubresources = true
        return await withCheckedContinuation { (continuation: CheckedContinuation<MetadataSummary?, Never>) in
            provider.startFetchingMetadata(for: url) { metadata, _ in
                guard let metadata else {
                    continuation.resume(returning: nil)
                    return
                }
                let title = metadata.title
                guard let imageProvider = metadata.imageProvider else {
                    continuation.resume(returning: MetadataSummary(title: title, imageData: nil))
                    return
                }
                let type = imageProvider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
                    ?? UTType.image.identifier
                _ = imageProvider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    continuation.resume(returning: MetadataSummary(title: title, imageData: data))
                }
            }
        }
    }

    private static func previewImage(metadata: MetadataSummary?, candidates: [String?]) async -> StagedMedia? {
        for candidate in candidates.compactMap({ $0 }) {
            guard let imageURL = URL(string: candidate),
                  let data = await WebFetcher.data(imageURL),
                  data.count > 2_000,
                  let staged = try? await MediaStore.stageImageData(data) else { continue }
            return staged
        }
        if let data = metadata?.imageData,
           let staged = try? await MediaStore.stageImageData(data) {
            return staged
        }
        return nil
    }

    private static func absolute(_ value: String, base: URL) -> String? {
        if value.hasPrefix("//") { return "https:" + value }
        return URL(string: value, relativeTo: base)?.absoluteURL.absoluteString
    }

    private static func prefersCrawler(_ url: URL) -> Bool {
        let host = LinkDraft.displayHost(url).lowercased()
        return host.hasSuffix("instagram.com") || host == "x.com" || host.hasSuffix("twitter.com") || host.hasSuffix("threads.net") || host.hasSuffix("facebook.com")
    }

    private static func isConsentPage(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host.hasPrefix("consent.") || url.path().contains("/login")
    }

    private static func socialHandle(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first, !["p", "reel", "reels", "status", "i", "stories"].contains(first) else { return nil }
        return first.hasPrefix("@") ? first : "@\(first)"
    }

    private static func cleanTitle(_ title: String, site: String?) -> String {
        var value = HTMLText.clean(title)
        for suffix in [" - YouTube", " | YouTube", " on TikTok", " | TikTok", " • Instagram", " | Instagram", " - Wikipedia", " — Wikipedia", " | Wikipedia"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        if let site, !site.isEmpty {
            for separator in [" | ", " - ", " – ", " — "] where value.hasSuffix(separator + site) {
                value = String(value.dropLast(separator.count + site.count))
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
