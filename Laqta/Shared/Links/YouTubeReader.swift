//
//  YouTubeReader.swift
//  Laqta — Shared
//
//  Turns a YouTube link into a saved link's details: the video's title, channel and
//  thumbnail from YouTube's oEmbed. YouTube pages aren't opened or read.
//

import Foundation

nonisolated enum YouTubeReader {
    /// The title a video link keeps until YouTube's details arrive.
    static let placeholderTitle = "YouTube video"

    /// Details for Save to Laqta and for loading a saved link's details again.
    @concurrent
    static func read(_ url: URL) async -> LinkDraft {
        var draft = LinkDraft(url: url)
        draft.isYouTube = true
        draft.sourceName = "YouTube"
        draft.site = "youtube.com"
        if let videoID = YouTubeLink.videoID(from: url) {
            draft.form = .video
            draft.title = placeholderTitle
            switch await lookup([videoID])[videoID] ?? .unknown {
            case let .found(video):
                apply(video, to: &draft)
            case .unavailable:
                draft.isUnavailable = true
            case .unknown:
                break
            }
        } else {
            // Channels and other YouTube pages: there is nothing more to load.
            draft.form = .page
            draft.title = YouTubeLink.isChannelPage(url) ? (channelName(from: url) ?? "YouTube channel") : "YouTube"
            draft.hasYouTubeDetails = true
        }
        return draft
    }

    static func apply(_ video: YouTubeVideo, to draft: inout LinkDraft) {
        draft.title = video.title.isEmpty ? placeholderTitle : video.title
        draft.author = video.channelTitle
        draft.imageURL = video.thumbnailURL
        draft.isUnavailable = false
        draft.hasYouTubeDetails = true
    }

    /// Looks videos up with oEmbed, a few at a time.
    @concurrent
    static func lookup(_ ids: [String]) async -> [String: YouTubeLookup] {
        let unique = Array(Set(ids.compactMap(YouTubeLink.validID))).sorted()
        guard !unique.isEmpty else { return [:] }
        var result: [String: YouTubeLookup] = [:]
        var start = 0
        while start < unique.count {
            let chunk = Array(unique[start..<min(start + 4, unique.count)])
            await withTaskGroup(of: (String, YouTubeLookup).self) { group in
                for id in chunk {
                    group.addTask {
                        (id, await YouTubeOEmbed.video(id: id))
                    }
                }
                for await (id, value) in group {
                    result[id] = value
                }
            }
            start += 4
        }
        return result
    }

    /// "@name" from a channel link.
    static func channelName(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@") { return first }
        if ["channel", "user", "c"].contains(first.lowercased()), parts.count > 1 { return parts[1] }
        return nil
    }
}
