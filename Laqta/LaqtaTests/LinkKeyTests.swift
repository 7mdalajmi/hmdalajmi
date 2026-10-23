//
//  LinkKeyTests.swift
//  LaqtaTests
//

import Foundation
import Testing
@testable import Laqta

@Suite("YouTube links")
struct YouTubeLinkTests {
    @Test("Finds the video ID in every YouTube link shape", arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
        "https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abcdef",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ?feature=shared",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
    ])
    func videoID(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(YouTubeLink.videoID(from: url) == "dQw4w9WgXcQ")
    }

    @Test("Ignores links without a valid video ID", arguments: [
        "https://www.youtube.com/",
        "https://www.youtube.com/@channel",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/watch?v=dQw4w9WgXc%21",
        "https://example.com/watch?v=dQw4w9WgXcQ",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ"
    ])
    func noVideoID(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(YouTubeLink.videoID(from: url) == nil)
    }

    @Test func channelPages() throws {
        #expect(YouTubeLink.isChannelPage(try #require(URL(string: "https://www.youtube.com/@apple"))))
        #expect(YouTubeLink.isChannelPage(try #require(URL(string: "https://youtube.com/channel/UC123"))))
        #expect(!YouTubeLink.isChannelPage(try #require(URL(string: "https://youtube.com/watch?v=dQw4w9WgXcQ"))))
    }

    @Test func watchURLKeepsTheMoment() throws {
        let url = try #require(YouTubeLink.watchURL(for: "dQw4w9WgXcQ", at: 95.8))
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=95s")
        #expect(YouTubeLink.watchURL(for: "dQw4w9WgXcQ")?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }
}

@Suite("Duplicate link keys")
struct LinkKeyTests {
    private func key(_ link: String) throws -> String {
        DuplicateKey.link(for: try #require(URL(string: link)))
    }

    @Test func youTubeLinksShareOneKey() throws {
        let keys = try [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ?si=xyz",
            "https://m.youtube.com/shorts/dQw4w9WgXcQ"
        ].map(key)
        #expect(Set(keys) == ["yt:dQw4w9WgXcQ"])
    }

    @Test func trackingParametersAreIgnored() throws {
        let plain = try key("https://example.com/article?id=4")
        #expect(try key("https://www.example.com/article/?utm_source=x&id=4&fbclid=abc") == plain)
        #expect(try key("https://m.example.com/article?id=4&utm_campaign=spring&gclid=1") == plain)
        #expect(plain == "example.com/article?id=4")
    }

    @Test func meaningfulParametersAreKept() throws {
        #expect(try key("https://example.com/search?s=shoes") != key("https://example.com/search?s=bags"))
        #expect(try key("https://example.com/list?page=2") != key("https://example.com/list?page=3"))
        #expect(try key("https://example.com/a?ref=summer") != key("https://example.com/a"))
    }

    @Test func siteSpecificShareParametersAreIgnored() throws {
        #expect(try key("https://x.com/apple/status/123?s=20&t=abc") == "x.com/apple/status/123")
        #expect(try key("https://www.tiktok.com/@a/video/1?is_from_webapp=1&sender_device=pc") == key("https://tiktok.com/@a/video/1"))
    }

    @Test func parameterOrderDoesNotMatter() throws {
        #expect(try key("https://example.com/p?b=2&a=1") == key("https://example.com/p?a=1&b=2"))
    }

    @Test func rootPathsMatch() throws {
        #expect(try key("https://example.com/") == key("https://www.example.com"))
    }
}
