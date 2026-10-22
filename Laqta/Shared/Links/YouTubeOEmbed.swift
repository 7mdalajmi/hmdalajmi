//
//  YouTubeOEmbed.swift
//  Laqta — Shared
//
//  A YouTube video's title, channel and thumbnail from YouTube's public oEmbed
//  endpoint. No API key and no account; Laqta doesn't read YouTube pages or captions.
//

import Foundation

/// Public details of one video, as YouTube's oEmbed returns them.
nonisolated struct YouTubeVideo: Sendable, Hashable {
    var id: String
    var title: String
    var channelTitle: String?
    var thumbnailURL: String?
}

/// What YouTube says about one video.
nonisolated enum YouTubeLookup: Sendable, Equatable {
    case found(YouTubeVideo)
    /// Removed, private, or not a video.
    case unavailable
    /// Offline or YouTube didn't answer; try again later.
    case unknown
}

nonisolated enum YouTubeOEmbed {
    static let endpoint = "https://www.youtube.com/oembed"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private nonisolated struct Response: Decodable, Sendable {
        let title: String?
        let author_name: String?
        let thumbnail_url: String?
    }

    @concurrent
    static func video(id: String) async -> YouTubeLookup {
        guard let url = requestURL(for: id) else { return .unknown }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let loaded = try? await session.data(for: request),
              let http = loaded.1 as? HTTPURLResponse else { return .unknown }
        return lookup(status: http.statusCode, body: loaded.0, id: id)
    }

    static func requestURL(for id: String) -> URL? {
        guard let watch = YouTubeLink.watchURL(for: id),
              var components = URLComponents(string: endpoint) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: watch.absoluteString)
        ]
        return components.url
    }

    /// Reads oEmbed's answer for one video.
    static func lookup(status: Int, body: Data, id: String) -> YouTubeLookup {
        switch status {
        case 200:
            guard let decoded = try? JSONDecoder().decode(Response.self, from: body),
                  let title = decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .unknown
            }
            let author = decoded.author_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let thumbnail = decoded.thumbnail_url.flatMap { $0.hasPrefix("https://") ? $0 : nil }
            return .found(YouTubeVideo(
                id: id,
                title: title,
                channelTitle: author?.isEmpty == false ? author : nil,
                thumbnailURL: thumbnail
            ))
        case 400, 404:
            return .unavailable
        default:
            // 401 means embedding is turned off; the video may still exist.
            return .unknown
        }
    }
}
