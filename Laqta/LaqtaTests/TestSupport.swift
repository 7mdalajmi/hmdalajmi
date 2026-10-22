//
//  TestSupport.swift
//  LaqtaTests
//
//  An in-memory library in a temporary folder, so tests never touch real data.
//

import Foundation
import SwiftData
import Testing
@testable import Laqta

/// Every suite that uses a `TestLibrary` lives in here: they share the App Group
/// test folder, so they run one at a time.
@Suite(.serialized)
@MainActor
enum LibraryTests {}

@MainActor
final class TestLibrary {
    let container: ModelContainer
    let root: URL

    var context: ModelContext { container.mainContext }

    init() throws {
        root = URL.temporaryDirectory.appending(path: "LaqtaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppGroup.useTestRoot(root)
        try AppGroup.prepareDirectories()
        AppGroup.defaults.removePersistentDomain(forName: "Hmdalajmi.Laqta.tests")
        AppGroup.registerDefaults()
        container = try LaqtaStore.makeContainer(inMemory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        AppGroup.useTestRoot(nil)
    }

    @discardableResult
    func folder(_ name: String, locked: Bool = false) -> Folder {
        let folder = Folder(name: name, symbol: "folder", tone: .ember, isLocked: locked)
        context.insert(folder)
        try? context.save()
        return folder
    }

    @discardableResult
    func child(_ name: String, of parent: Folder, locked: Bool = false) -> Folder {
        let folder = Folder(name: name, symbol: "folder", tone: .tide, isLocked: locked)
        folder.parentID = parent.id
        context.insert(folder)
        try? context.save()
        return folder
    }

    func everyFolder() -> [Folder] {
        (try? context.fetch(FetchDescriptor<Folder>())) ?? []
    }

    /// A photo item with a real (tiny) file in the media folder.
    @discardableResult
    func photo(in folder: Folder, added: Date = .now, bytes: Int = 64) throws -> Shot {
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        let data = Data(repeating: 0xAB, count: bytes)
        try data.write(to: AppGroup.mediaURL.appending(path: fileName))
        try data.write(to: AppGroup.thumbnailsURL.appending(path: "\(id.uuidString).jpg"))
        var info = MediaInfo(kind: .photo)
        info.pixelWidth = 10
        info.pixelHeight = 10
        let staged = StagedMedia(
            id: id,
            fileURL: AppGroup.mediaURL.appending(path: fileName),
            thumbnailURL: nil,
            hasLowResThumbnail: false,
            info: info,
            originalName: "IMG_\(Int.random(in: 1000...9999))",
            byteCount: bytes,
            sourceAssetID: nil,
            contentHash: ContentHasher.sha256(of: data)
        )
        let item = Shot(staged: staged, files: StoredFiles(fileName: fileName, thumbnailName: "\(id.uuidString).jpg"), folderID: folder.id)
        item.addedAt = added
        context.insert(item)
        try context.save()
        return item
    }

    func link(_ string: String, in folder: Folder) throws -> Shot {
        let url = try #require(URL(string: string))
        let draft = LinkDraft(url: url)
        let item = Shot(link: draft, files: nil, folderID: folder.id)
        context.insert(item)
        try context.save()
        return item
    }

    func fileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: AppGroup.mediaURL.appending(path: name).path(percentEncoded: false))
    }
}
