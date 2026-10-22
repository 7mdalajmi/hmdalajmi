import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import LaqtaMac

final class MacLibraryTests: XCTestCase {
    func testRestoredLinksCannotLaunchLocalFilesOrCustomSchemes() {
        XCTAssertTrue(MacWebLink.isAllowed(URL(string: "https://example.com/path")!))
        XCTAssertTrue(MacWebLink.isAllowed(URL(string: "http://example.com/path")!))
        XCTAssertFalse(MacWebLink.isAllowed(URL(filePath: "/Applications/Calculator.app")))
        XCTAssertFalse(MacWebLink.isAllowed(URL(string: "laqta://open/item")!))
        XCTAssertFalse(MacWebLink.isAllowed(URL(string: "javascript:alert(1)")!))
    }

    func testAnalysisDeadlineResumesOnlyOnceEvenWhenWorkFinishesLater() async {
        let result = await withCheckedContinuation { continuation in
            let flight = MacAnalysisFlight(continuation)
            flight.expire()
            flight.finish(MacAnalysisResult(analysis: ShotAnalysis(), completed: true))
            flight.expire()
        }
        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.analysis.tips.isEmpty)
    }

    @MainActor
    func testArchiveRejectsUnsafeDuplicateAndTrailingData() throws {
        let (root, _) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source.bin")
        try Data([1, 2, 3]).write(to: source)
        let archive = root.appending(path: "archive.laqtabackup")
        XCTAssertThrowsError(try BackupArchive.write(entries: [.init(path: "../escape", source: source)], to: archive))
        XCTAssertThrowsError(try BackupArchive.write(entries: [.init(path: "Media/a", source: source), .init(path: "Media/A", source: source)], to: archive))
        for path in ["/etc/passwd", "Media/../../Laqta.store", "Media/sub/file", "Media\\file", "Media/./file"] {
            XCTAssertFalse(BackupArchive.isSafe(path))
        }
        try BackupArchive.write(entries: [.init(path: "Media/a", source: source)], to: archive)
        let complete = try Data(contentsOf: archive)
        var repeated = Data(complete.dropLast())
        repeated.append(contentsOf: complete.dropFirst(6))
        let duplicate = root.appending(path: "duplicate.laqtabackup")
        try repeated.write(to: duplicate)
        XCTAssertThrowsError(try BackupArchive.extract(duplicate, to: root.appending(path: "Duplicate")))
        var extra = complete
        extra.append(42)
        let trailing = root.appending(path: "trailing.laqtabackup")
        try extra.write(to: trailing)
        XCTAssertThrowsError(try BackupArchive.extract(trailing, to: root.appending(path: "Trailing")))
    }

    @MainActor
    func testManifestRejectsDuplicateIdentifiersUnsafeNamesAndNegativeSizes() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        await library.importFiles([source], folderID: nil)
        let context = try XCTUnwrap(library.container?.mainContext)
        let snapshot = LibrarySnapshotter.snapshot(context: context)
        let info = BackupInfo(id: "test", format: 1, createdAt: .now, appVersion: "test", deviceName: "Mac",
                              deviceID: "test", folderCount: 1, itemCount: 1, mediaBytes: 0)
        let valid = BackupManifest(info: info, folders: snapshot.folders, items: snapshot.items)
        XCTAssertEqual(try BackupManifest.decode(valid.encoded()).items.count, 1)
        var duplicateFolders = valid
        duplicateFolders.folders += valid.folders
        XCTAssertThrowsError(try BackupManifest.decode(duplicateFolders.encoded()))
        var duplicateItems = valid
        duplicateItems.items += valid.items
        XCTAssertThrowsError(try BackupManifest.decode(duplicateItems.encoded()))
        var unsafe = valid
        unsafe.items[0].fileName = "../Laqta.store"
        XCTAssertThrowsError(try BackupManifest.decode(unsafe.encoded()))
        var negative = valid
        negative.items[0].byteCount = -1
        XCTAssertThrowsError(try BackupManifest.decode(negative.encoded()))
        var overflow = valid
        overflow.items[0].pixelWidth = Int.max
        overflow.items[0].pixelHeight = 2
        XCTAssertThrowsError(try BackupManifest.decode(overflow.encoded()))
    }

    @MainActor
    func testVisionRequestCannotBlockCallerPastDeadline() async throws {
        let (root, _) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        let start = ContinuousClock.now
        let result = await MacAnalyzer.analyze(url: source, kind: .photo, timeout: 1)
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
        print("Vision worker still active after deadline: \(MacAnalyzer.hasRunningRequest)")
        if !result.completed { XCTAssertFalse(result.analysis.tips.isEmpty) }
    }
    @MainActor
    private func fixture() throws -> (URL, MacLibrary) {
        let root = URL.temporaryDirectory.appending(path: "LaqtaMacTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppGroup.useTestRoot(root)
        try AppGroup.prepareDirectories()
        AppGroup.defaults.set(true, forKey: SettingsKey.skipDuplicates)
        // Storage/security tests do not depend on the host's downloadable Vision models.
        let library = MacLibrary(analyzeImports: false)
        XCTAssertNotNil(library.container, library.launchError ?? "No container")
        return (root, library)
    }

    @MainActor
    private func image(in root: URL) throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        let file = root.appending(path: "Fixture.jpg")
        try ImageTools.writeJPEG(try XCTUnwrap(context.makeImage()), to: file)
        return file
    }

    @MainActor
    func testNativeImportCopiesOriginalAndSkipsDuplicate() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        let folder = try XCTUnwrap(library.createFolder(name: "صور", parent: nil, locked: false))
        await library.importFiles([source, source], folderID: folder.id)
        let context = try XCTUnwrap(library.container?.mainContext)
        let items = try context.fetch(FetchDescriptor<Shot>())
        XCTAssertEqual(items.count, 1)
        let shot = try XCTUnwrap(items.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.thumbnailURL.path))
        XCTAssertEqual(shot.pixelWidth, 80)
        XCTAssertEqual(shot.pixelHeight, 60)
        XCTAssertNotNil(shot.contentHash)
    }

    @MainActor
    func testPrivateFolderProtectionIncludesAncestors() throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let parent = try XCTUnwrap(library.createFolder(name: "خاص", parent: nil, locked: true))
        library.unlockedFolders.insert(parent.id)
        let child = try XCTUnwrap(library.createFolder(name: "داخل الخاص", parent: parent.id, locked: false))
        library.lockAll()
        let folders = [parent, child]
        XCTAssertFalse(library.canAccess(child.id, folders: folders))
        XCTAssertFalse(library.canAccess(UUID(), folders: folders))
        library.unlockedFolders.insert(parent.id)
        XCTAssertTrue(library.canAccess(child.id, folders: folders))
        library.lockAll()
        XCTAssertFalse(library.canAccess(child.id, folders: folders))
    }

    @MainActor
    func testImportAndExportRejectRelockedFolder() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        let folder = try XCTUnwrap(library.createFolder(name: "خاص", parent: nil, locked: true))
        let context = try XCTUnwrap(library.container?.mainContext)
        await library.importFiles([source], folderID: folder.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shot>()), 0)
        library.unlockedFolders.insert(folder.id)
        await library.importFiles([source], folderID: folder.id)
        let shot = try XCTUnwrap(try context.fetch(FetchDescriptor<Shot>()).first)
        let exported = root.appending(path: "Export", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exported, withIntermediateDirectories: true)
        library.lockAll()
        do {
            try await library.export([shot], to: exported)
            XCTFail("Export must require access again after relocking")
        } catch { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: exported.path).isEmpty)
        library.deletePermanently([shot])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shot>()), 1)
    }

    @MainActor
    func testRepeatedExportPreservesExistingFilesAndBytes() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        await library.importFiles([source], folderID: nil)
        let context = try XCTUnwrap(library.container?.mainContext)
        let shot = try XCTUnwrap(try context.fetch(FetchDescriptor<Shot>()).first)
        let exported = root.appending(path: "Export", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exported, withIntermediateDirectories: true)
        let existing = exported.appending(path: shot.shareFileName)
        let sentinel = Data("keep this existing file".utf8)
        try sentinel.write(to: existing)
        try await library.export([shot], to: exported)
        try await library.export([shot], to: exported)
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        let files = try FileManager.default.contentsOfDirectory(at: exported, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        for file in files where file.lastPathComponent != existing.lastPathComponent {
            XCTAssertEqual(try Data(contentsOf: file), try Data(contentsOf: source))
        }
    }

    @MainActor
    func testUnavailableDestinationDoesNotSilentlyMoveImportToInbox() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        await library.importFiles([source], folderID: UUID())
        let context = try XCTUnwrap(library.container?.mainContext)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shot>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Folder>()), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testSymbolicLinkImportCopiesPayloadIndependentlyOfFinderSource() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        let originalBytes = try Data(contentsOf: source)
        let alias = root.appending(path: "Linked.jpg")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        await library.importFiles([alias], folderID: nil)
        let context = try XCTUnwrap(library.container?.mainContext)
        let shot = try XCTUnwrap(try context.fetch(FetchDescriptor<Shot>()).first)
        XCTAssertFalse(try shot.fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true)
        XCTAssertEqual(try Data(contentsOf: shot.fileURL), originalBytes)
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: shot.fileURL), originalBytes)
    }

    @MainActor
    func testTrashIsReversibleAndKeepsFilesUntilPermanentDeletion() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        let parent = try XCTUnwrap(library.createFolder(name: "الأصل", parent: nil, locked: false))
        let child = try XCTUnwrap(library.createFolder(name: "الفرع", parent: parent.id, locked: false))
        await library.importFiles([source], folderID: child.id)
        let context = try XCTUnwrap(library.container?.mainContext)
        let shot = try XCTUnwrap(try context.fetch(FetchDescriptor<Shot>()).first)
        let file = shot.fileURL
        library.trash(parent, folders: [parent, child], items: [shot])
        XCTAssertTrue(parent.isInTrash)
        XCTAssertTrue(child.isInTrash)
        XCTAssertTrue(shot.isInTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        library.restore([shot], folders: [parent, child])
        XCTAssertFalse(parent.isInTrash)
        XCTAssertFalse(child.isInTrash)
        XCTAssertFalse(shot.isInTrash)
        // A permanent-delete request cannot delete a live item.
        library.deletePermanently([shot])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shot>()), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        library.trash([shot])
        library.deletePermanently([shot])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shot>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testBackupRoundTripPreservesNotesFoldersAndMedia() async throws {
        let (root, library) = try fixture()
        defer { AppGroup.useTestRoot(nil); BackupEngine.cleanUpExports(); try? FileManager.default.removeItem(at: root) }
        let source = try image(in: root)
        let folder = try XCTUnwrap(library.createFolder(name: "أرشيف", parent: nil, locked: false))
        await library.importFiles([source], folderID: folder.id)
        let context = try XCTUnwrap(library.container?.mainContext)
        let original = try XCTUnwrap(try context.fetch(FetchDescriptor<Shot>()).first)
        XCTAssertTrue(library.save { original.setNote("ملاحظة عربية محفوظة"); original.isFavorite = true })
        let snapshot = LibrarySnapshotter.snapshot(context: context)
        let info = BackupInfo(id: BackupInfo.makeID(date: .now), format: 1, createdAt: .now, appVersion: "test",
            deviceName: "Mac", deviceID: "test", folderCount: snapshot.folders.count, itemCount: snapshot.items.count, mediaBytes: 0)
        let archive = try await BackupEngine.export(snapshot, info: info) { _, _ in }
        let prepared = try await BackupEngine.prepareRestore(fromFile: archive) { _, _ in }
        defer { BackupEngine.finish(prepared) }
        let restoredContainer = try LaqtaStore.makeContainer(inMemory: true)
        let restoredContext = restoredContainer.mainContext
        let result = try await BackupRestorer.restore(prepared, context: restoredContext) { _, _ in }
        XCTAssertEqual(result.addedItems, 1)
        XCTAssertEqual(result.addedFolders, 1)
        let restored = try XCTUnwrap(try restoredContext.fetch(FetchDescriptor<Shot>()).first)
        XCTAssertEqual(restored.note, "ملاحظة عربية محفوظة")
        XCTAssertTrue(restored.isFavorite)
        XCTAssertEqual(restored.folderID, folder.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.fileURL.path))
        let again = try await BackupRestorer.restore(prepared, context: restoredContext) { _, _ in }
        XCTAssertEqual(again.addedItems, 0)
        XCTAssertEqual(again.alreadyThere, 1)
    }
}
