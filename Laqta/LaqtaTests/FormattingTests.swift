//
//  FormattingTests.swift
//  LaqtaTests
//

import Foundation
import Testing
@testable import Laqta

@Suite("Formatting")
struct FormattingTests {
    @Test func counts() {
        #expect(LaqtaFormat.count(1, "item", "items") == "1 item")
        #expect(LaqtaFormat.count(0, "item", "items") == "0 items")
        #expect(LaqtaFormat.count(1_204, "shot", "shots") == "1,204 shots")
    }

    @Test func folderContents() {
        var stats = FolderStats()
        #expect(LaqtaFormat.contents(stats) == "Empty")
        stats.photos = 4
        stats.links = 1
        #expect(LaqtaFormat.contents(stats) == "4 shots · 1 link")
        stats.videos = 2
        stats.documents = 1
        // Four kinds collapse into three parts.
        #expect(LaqtaFormat.contents(stats) == "4 shots · 2 videos · 2 more")
    }

    @Test func durations() {
        #expect(LaqtaFormat.duration(5) == "0:05")
        #expect(LaqtaFormat.duration(65) == "1:05")
        #expect(LaqtaFormat.duration(3_725) == "1:02:05")
    }
}

@Suite("Folder sort")
struct FolderSortTests {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func key(added: Double, taken: Double? = nil, kind: ItemKind = .photo, title: String = "") -> FolderSort.Key {
        FolderSort.Key(
            addedAt: base.addingTimeInterval(added),
            takenAt: taken.map { base.addingTimeInterval($0) },
            kind: kind,
            title: title
        )
    }

    private func sorted(_ keys: [FolderSort.Key], by sort: FolderSort) -> [FolderSort.Key] {
        keys.sorted(by: sort.areInIncreasingOrder)
    }

    @Test func newestAndOldest() {
        let keys = [key(added: 10), key(added: 30), key(added: 20)]
        #expect(sorted(keys, by: .newest).map(\.addedAt) == [30, 20, 10].map { base.addingTimeInterval($0) })
        #expect(sorted(keys, by: .oldest).map(\.addedAt) == [10, 20, 30].map { base.addingTimeInterval($0) })
    }

    @Test func dateTakenFallsBackToDateAdded() {
        let old = key(added: 100, taken: -1_000)
        let noDate = key(added: 50)
        let recent = key(added: 10, taken: 60)
        #expect(sorted([old, noDate, recent], by: .taken).map(\.addedAt) == [recent, noDate, old].map(\.addedAt))
    }

    @Test func kindOrder() {
        let link = key(added: 40, kind: .link)
        let pdf = key(added: 30, kind: .document)
        let video = key(added: 20, kind: .video)
        let photo = key(added: 10, kind: .photo)
        #expect(sorted([link, pdf, video, photo], by: .kind).map(\.kind) == [.photo, .video, .document, .link])
    }

    @Test func titlesSortNaturally() {
        let keys = [key(added: 1, title: "Item 10"), key(added: 2, title: "item 2"), key(added: 3, title: "Alpha")]
        #expect(sorted(keys, by: .title).map(\.title) == ["Alpha", "item 2", "Item 10"])
    }

    @Test func storedSortRoundTrips() {
        for sort in FolderSort.allCases {
            #expect(FolderSort(rawValue: sort.rawValue) == sort)
        }
    }
}
