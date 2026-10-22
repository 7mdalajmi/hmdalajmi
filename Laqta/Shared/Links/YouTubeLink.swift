//
//  YouTubeLink.swift
//  Laqta — Shared
//
//  Recognizes YouTube links and their video IDs.
//

import Foundation

nonisolated enum YouTubeLink {
    static func isYouTube(_ url: URL) -> Bool {
        let host = LinkDraft.displayHost(url).lowercased()
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
    }

    /// "https://youtu.be/dQw4w9WgXcQ?si=…" → "dQw4w9WgXcQ"
    static func videoID(from url: URL) -> String? {
        guard isYouTube(url) else { return nil }
        let host = LinkDraft.displayHost(url).lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "youtu.be" {
            return parts.first.flatMap(validID)
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
           let id = validID(value) {
            return id
        }
        if let index = parts.firstIndex(where: { ["shorts", "embed", "live", "v", "e"].contains($0.lowercased()) }),
           parts.count > index + 1 {
            return validID(parts[index + 1])
        }
        return nil
    }

    /// YouTube channel and handle pages ("/@name", "/channel/…").
    static func isChannelPage(_ url: URL) -> Bool {
        guard isYouTube(url) else { return false }
        let path = url.path().lowercased()
        return path.hasPrefix("/@") || path.hasPrefix("/channel/") || path.hasPrefix("/c/") || path.hasPrefix("/user/")
    }

    static func validID(_ raw: String) -> String? {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count == 11,
              candidate.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }),
              candidate.allSatisfy(\.isASCII) else { return nil }
        return candidate
    }

    static func watchURL(for videoID: String, at seconds: Double? = nil) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/watch")
        var items = [URLQueryItem(name: "v", value: videoID)]
        if let seconds, seconds > 0 {
            items.append(URLQueryItem(name: "t", value: "\(Int(seconds))s"))
        }
        components?.queryItems = items
        return components?.url
    }
}
