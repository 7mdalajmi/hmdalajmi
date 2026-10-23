//
//  YouTubeDetailsTests.swift
//  LaqtaTests
//
//  YouTube links get their title, channel and thumbnail from YouTube's oEmbed,
//  and load them later when they were saved offline.
//

import Foundation
import SwiftData
import Testing
@testable import Laqta

@Suite("YouTube oEmbed")
struct YouTubeOEmbedTests {
    static let bunny = YouTubeVideo(
        id: "aqz-KE-bpKQ",
        title: "Big Buck Bunny 60fps 4K",
        channelTitle: "Blender",
        thumbnailURL: "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg"
    )

    private let answer = Data("""
    {
      "title": "Big Buck Bunny 60fps 4K",
      "author_name": "Blender",
      "author_url": "https://www.youtube.com/@BlenderOfficial",
      "type": "video",
      "provider_name": "YouTube",
      "thumbnail_url": "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg",
      "html": "<iframe></iframe>"
    }
    """.utf8)

    @Test func readsTheVideo() {
        #expect(YouTubeOEmbed.lookup(status: 200, body: answer, id: "aqz-KE-bpKQ") == .found(Self.bunny))
    }

    @Test func dropsThumbnailsThatArentHTTPS() {
        let body = Data(#"{"title": "Lofi", "author_name": " ", "thumbnail_url": "http://i.ytimg.com/vi/x/hq.jpg"}"#.utf8)
        let expected = YouTubeVideo(id: "jfKfPfyJRdk", title: "Lofi", channelTitle: nil, thumbnailURL: nil)
        #expect(YouTubeOEmbed.lookup(status: 200, body: body, id: "jfKfPfyJRdk") == .found(expected))
    }

    @Test("Other answers", arguments: [
        (200, "{}", YouTubeLookup.unknown),
        (200, "<html>", YouTubeLookup.unknown),
        (400, "Bad Request", YouTubeLookup.unavailable),
        (404, "Not Found", YouTubeLookup.unavailable),
        (401, "Unauthorized", YouTubeLookup.unknown),
        (500, "", YouTubeLookup.unknown)
    ])
    func otherAnswers(_ status: Int, _ body: String, _ expected: YouTubeLookup) {
        #expect(YouTubeOEmbed.lookup(status: status, body: Data(body.utf8), id: "aqz-KE-bpKQ") == expected)
    }

    @Test func asksForTheWatchPage() throws {
        let url = try #require(YouTubeOEmbed.requestURL(for: "aqz-KE-bpKQ"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host() == "www.youtube.com")
        #expect(url.path() == "/oembed")
        #expect(items.first { $0.name == "format" }?.value == "json")
        #expect(items.first { $0.name == "url" }?.value == "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
    }

    @Test func videoDetailsFillALink() throws {
        var draft = LinkDraft(url: try #require(URL(string: "https://youtu.be/aqz-KE-bpKQ")))
        draft.isUnavailable = true
        YouTubeReader.apply(Self.bunny, to: &draft)

        #expect(draft.title == "Big Buck Bunny 60fps 4K")
        #expect(draft.author == "Blender")
        #expect(draft.imageURL == Self.bunny.thumbnailURL)
        #expect(draft.hasYouTubeDetails)
        #expect(!draft.isUnavailable)
    }

    @Test func channelLinksNeedNothingMore() async throws {
        let draft = await YouTubeReader.read(try #require(URL(string: "https://www.youtube.com/@BlenderOfficial")))
        #expect(draft.title == "@BlenderOfficial")
        #expect(draft.form == .page)
        #expect(draft.hasYouTubeDetails)
    }
}

extension LibraryTests {
    @Suite("YouTube details")
    @MainActor
    struct YouTubeDetailsTests {
        private let now = Date(timeIntervalSince1970: 1_790_000_000)

        /// A video link as Save to Laqta stores it, with or without YouTube's details.
        private func videoLink(in library: TestLibrary, loaded: Bool) throws -> Shot {
            var draft = LinkDraft(url: try #require(URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")))
            draft.isYouTube = true
            draft.form = .video
            draft.title = YouTubeReader.placeholderTitle
            if loaded { YouTubeReader.apply(YouTubeOEmbedTests.bunny, to: &draft) }
            let item = LibraryWriter.addLink(draft, to: library.folder("Videos"), deep: false, context: library.context)
            try library.context.save()
            return item
        }

        @Test func linkSavedOfflineWaitsForDetails() throws {
            let library = try TestLibrary()
            let item = try videoLink(in: library, loaded: false)
            #expect(item.isYouTube)
            #expect(item.linkRefreshedAt == nil)
            #expect(YouTubeRefresher.needsDetails(item))

            let loaded = try videoLink(in: library, loaded: true)
            #expect(loaded.linkRefreshedAt != nil)
            #expect(!YouTubeRefresher.needsDetails(loaded))
        }

        @Test func placeholderTitleStillCountsAsMissing() throws {
            let library = try TestLibrary()
            let item = try videoLink(in: library, loaded: false)
            item.linkRefreshedAt = now
            #expect(YouTubeRefresher.needsDetails(item))
        }

        @Test func foundVideoFillsTheLink() throws {
            let library = try TestLibrary()
            let item = try videoLink(in: library, loaded: false)

            YouTubeRefresher.apply(.found(YouTubeOEmbedTests.bunny), to: item, now: now)

            #expect(item.linkTitle == "Big Buck Bunny 60fps 4K")
            #expect(item.linkAuthor == "Blender")
            #expect(item.linkImageURL == "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg")
            #expect(item.linkUnavailable == nil)
            #expect(item.linkRefreshedAt == now)
            #expect(!YouTubeRefresher.needsDetails(item))
            #expect(item.analysisState == .done)
            #expect(item.analysis?.basis == "Details from YouTube")
            #expect(item.analysis?.source?.app == "YouTube")
        }

        @Test func removedVideoKeepsWhatItWas() throws {
            let library = try TestLibrary()
            let item = try videoLink(in: library, loaded: true)

            YouTubeRefresher.apply(.unavailable, to: item, now: now)

            #expect(item.linkUnavailable == true)
            #expect(item.linkTitle == "Big Buck Bunny 60fps 4K")
            #expect(item.linkAuthor == "Blender")
            #expect(item.linkURL == "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
            #expect(item.linkRefreshedAt == now)
            #expect(!YouTubeRefresher.needsDetails(item))
            #expect(item.analysis?.basis == "This video is no longer available on YouTube")
        }

        @Test func offlineChangesNothing() throws {
            let library = try TestLibrary()
            let item = try videoLink(in: library, loaded: false)
            YouTubeRefresher.apply(.unknown, to: item, now: now)
            #expect(item.linkTitle == YouTubeReader.placeholderTitle)
            #expect(item.linkRefreshedAt == nil)
            #expect(YouTubeRefresher.needsDetails(item))

            let loaded = try videoLink(in: library, loaded: true)
            let refreshed = loaded.linkRefreshedAt
            YouTubeRefresher.apply(.unknown, to: loaded, now: now)
            #expect(loaded.linkTitle == "Big Buck Bunny 60fps 4K")
            #expect(loaded.linkRefreshedAt == refreshed)
        }

        @Test func chaptersSavedEarlierStay() throws {
            let library = try TestLibrary()
            let item = try videoLink(in: library, loaded: false)
            var analysis = ShotAnalysis()
            analysis.sections = [Chapter(seconds: 0, title: "Intro"), Chapter(seconds: 90, title: "The meadow")]
            analysis.sectionsTitle = "Chapters"
            item.store(analysis, state: .done)

            YouTubeRefresher.apply(.found(YouTubeOEmbedTests.bunny), to: item, now: now)

            #expect(item.analysis?.sections.map(\.title) == ["Intro", "The meadow"])
            #expect(item.analysis?.sectionsTitle == "Chapters")
        }
    }
}
