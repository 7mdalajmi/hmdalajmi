//
//  BackupTests.swift
//  LaqtaTests
//
//  The single-file backup format, and restoring: nothing is replaced, missing items
//  come back, trashed ones are recovered.
//

import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Laqta

@Suite("Backup archive")
struct BackupArchiveTests {
    private func temporaryFolder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "LaqtaArchive-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func file(_ name: String, in folder: URL, bytes: Data) throws -> URL {
        let url = folder.appending(path: name)
        try bytes.write(to: url)
        return url
    }

    private func randomData(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    @Test func roundTrip() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = Data(#"{"hello":"world"}"#.utf8)
        // Bigger than one chunk, so the streaming path is used.
        let photo = randomData(BackupArchive.chunkSize + 12_345)
        let thumbnail = randomData(900)
        let empty = Data()
        let entries: [BackupArchive.Entry] = [
            .init(path: BackupArchive.manifestPath, source: try file("m.json", in: folder, bytes: manifest)),
            .init(path: "Media/photo.heic", source: try file("p.heic", in: folder, bytes: photo)),
            .init(path: "Thumbnails/photo.jpg", source: try file("t.jpg", in: folder, bytes: thumbnail)),
            .init(path: "Media/empty.pdf", source: try file("e.pdf", in: folder, bytes: empty))
        ]
        let archive = folder.appending(path: "Test.laqtabackup")
        var reported: Int64 = 0
        try BackupArchive.write(entries: entries, to: archive, progress: { reported = $0 })
        #expect(reported == Int64(manifest.count + photo.count + thumbnail.count))

        let output = folder.appending(path: "Out", directoryHint: .isDirectory)
        let paths = try BackupArchive.extract(archive, to: output)
        #expect(paths == ["Library.json", "Media/photo.heic", "Thumbnails/photo.jpg", "Media/empty.pdf"])
        #expect(try Data(contentsOf: output.appending(path: "Library.json")) == manifest)
        #expect(try Data(contentsOf: output.appending(path: "Media/photo.heic")) == photo)
        #expect(try Data(contentsOf: output.appending(path: "Thumbnails/photo.jpg")) == thumbnail)
        #expect(try Data(contentsOf: output.appending(path: "Media/empty.pdf")).isEmpty)
    }

    @Test("Only known places inside the archive are allowed", arguments: [
        ("Library.json", true),
        ("Media/photo.heic", true),
        ("Thumbnails/photo.jpg", true),
        ("", false),
        ("/etc/passwd", false),
        ("../Library.json", false),
        ("Media/../../secret", false),
        ("Media/./photo.heic", false),
        ("Media/sub/photo.heic", false),
        ("Media/", false),
        ("Documents/photo.heic", false),
        ("Media\\photo.heic", false),
        ("Library.json/x", false)
    ])
    func safePaths(_ path: String, _ isSafe: Bool) {
        #expect(BackupArchive.isSafe(path) == isSafe)
    }

    @Test func writingRejectsUnsafeAndMissingEntries() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try file("a.jpg", in: folder, bytes: Data([1, 2, 3]))
        let archive = folder.appending(path: "Test.laqtabackup")
        #expect(throws: BackupError.damaged) {
            try BackupArchive.write(entries: [.init(path: "../evil.jpg", source: source)], to: archive)
        }
        #expect(throws: (any Error).self) {
            try BackupArchive.write(entries: [.init(path: "Media/missing.jpg", source: folder.appending(path: "missing.jpg"))], to: archive)
        }
        #expect(throws: BackupError.damaged) {
            try BackupArchive.write(entries: [
                .init(path: "Media/a.jpg", source: source),
                .init(path: "Media/A.jpg", source: source)
            ], to: archive)
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "evil.jpg").path(percentEncoded: false)))
    }

    @Test func rejectsDuplicateArchiveEntriesAndTrailingBytes() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try file("a.jpg", in: folder, bytes: Data([1, 2, 3]))
        let archive = folder.appending(path: "Test.laqtabackup")
        try BackupArchive.write(entries: [.init(path: "Media/a.jpg", source: source)], to: archive)
        let complete = try Data(contentsOf: archive)
        var repeated = Data(complete.dropLast())
        repeated.append(contentsOf: complete.dropFirst(6))
        let duplicate = try file("duplicate.laqtabackup", in: folder, bytes: repeated)
        #expect(throws: BackupError.damaged) {
            try BackupArchive.extract(duplicate, to: folder.appending(path: "Duplicate"))
        }
        var extra = complete
        extra.append(42)
        let trailing = try file("trailing.laqtabackup", in: folder, bytes: extra)
        #expect(throws: BackupError.damaged) {
            try BackupArchive.extract(trailing, to: folder.appending(path: "Trailing"))
        }
    }

    @Test func cancellationStopsDuringALargeEntry() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try file("large.mov", in: folder, bytes: randomData(BackupArchive.chunkSize * 3))
        let archive = folder.appending(path: "Test.laqtabackup")
        try BackupArchive.write(entries: [.init(path: "Media/large.mov", source: source)], to: archive)
        var written: Int64 = 0
        #expect(throws: BackupError.cancelled) {
            try BackupArchive.extract(archive, to: folder.appending(path: "Cancelled"), isCancelled: { written > 0 }, progress: { written = $0 })
        }
        #expect(written == Int64(BackupArchive.chunkSize))
    }

    @Test func rejectsOtherFiles() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notBackup = try file("photo.laqtabackup", in: folder, bytes: Data("PK\u{3}\u{4} a zip file".utf8))
        #expect(throws: BackupError.notABackup) {
            try BackupArchive.extract(notBackup, to: folder.appending(path: "Out"))
        }
        let tooShort = try file("short.laqtabackup", in: folder, bytes: Data("LQ".utf8))
        #expect(throws: BackupError.notABackup) {
            try BackupArchive.extract(tooShort, to: folder.appending(path: "Out"))
        }
        var newer = Data(BackupArchive.magic)
        newer.append(contentsOf: [UInt8(BackupArchive.version + 1), 0, 0])
        let newerFile = try file("newer.laqtabackup", in: folder, bytes: newer)
        #expect(throws: BackupError.newerFormat) {
            try BackupArchive.extract(newerFile, to: folder.appending(path: "Out"))
        }
    }

    @Test func rejectsDamagedArchives() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try file("a.jpg", in: folder, bytes: randomData(4_000))
        let archive = folder.appending(path: "Test.laqtabackup")
        try BackupArchive.write(entries: [.init(path: "Media/a.jpg", source: source)], to: archive)
        let complete = try Data(contentsOf: archive)

        // Cut off in the middle of the file, and without the end marker.
        for length in [complete.count - 1, complete.count - 100, 9] {
            let cut = try file("cut-\(length).laqtabackup", in: folder, bytes: complete.prefix(length))
            #expect(throws: BackupError.damaged) {
                try BackupArchive.extract(cut, to: folder.appending(path: "Out-\(length)"))
            }
        }

        // A path that leaves the backup folder.
        var evil = Data(BackupArchive.magic)
        evil.append(contentsOf: [1, 0])
        let path = Array("../../escape.txt".utf8)
        evil.append(1)
        evil.append(contentsOf: [UInt8(path.count), 0])
        evil.append(contentsOf: path)
        evil.append(contentsOf: [3, 0, 0, 0, 0, 0, 0, 0])
        evil.append(contentsOf: [65, 66, 67, 0])
        let evilFile = try file("evil.laqtabackup", in: folder, bytes: evil)
        #expect(throws: BackupError.damaged) {
            try BackupArchive.extract(evilFile, to: folder.appending(path: "Out-evil"))
        }
        #expect(!FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().appending(path: "escape.txt").path(percentEncoded: false)))
    }

    @Test func manifestFormatVersion() throws {
        let info = BackupInfo(
            id: BackupInfo.makeID(date: .now), format: BackupInfo.currentFormat, createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            appVersion: "2.1", deviceName: "iPhone", deviceID: "device", folderCount: 0, itemCount: 0, mediaBytes: 0
        )
        let manifest = BackupManifest(info: info, folders: [], items: [])
        let decoded = try BackupManifest.decode(try manifest.encoded())
        #expect(decoded.info == info)

        var newer = manifest
        newer.info.format = BackupInfo.currentFormat + 1
        let newerData = try newer.encoded()
        #expect(throws: BackupError.newerFormat) {
            try BackupManifest.decode(newerData)
        }
        #expect(throws: (any Error).self) {
            try BackupManifest.decode(Data("[]".utf8))
        }
    }
}

@Suite("Sealed backup files")
struct BackupCryptoTests {
    private let key = SymmetricKey(size: .bits256)

    private func temporaryFolder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "LaqtaSealed-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func randomData(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    @Test func roundTripAcrossSeveralChunks() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = randomData(BackupCrypto.chunkSize * 2 + 1_234)
        let source = folder.appending(path: "photo.heic")
        try original.write(to: source)
        let sealed = folder.appending(path: BackupCrypto.sealedName("photo.heic"))
        try BackupCrypto.seal(source, to: sealed, name: "photo.heic", key: key)

        // Nothing of the photo is readable in the sealed copy.
        let sealedBytes = try Data(contentsOf: sealed)
        #expect(sealedBytes.count > original.count)
        #expect(sealedBytes.range(of: original.prefix(64)) == nil)

        let opened = folder.appending(path: "opened.heic")
        try BackupCrypto.open(sealed, to: opened, name: "photo.heic", key: key)
        #expect(try Data(contentsOf: opened) == original)
    }

    @Test func anEmptyFileSurvives() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "empty.pdf")
        try Data().write(to: source)
        let sealed = folder.appending(path: BackupCrypto.sealedName("empty.pdf"))
        try BackupCrypto.seal(source, to: sealed, name: "empty.pdf", key: key)
        let opened = folder.appending(path: "opened.pdf")
        try BackupCrypto.open(sealed, to: opened, name: "empty.pdf", key: key)
        #expect(try Data(contentsOf: opened).isEmpty)
    }

    @Test func anotherKeyOpensNothing() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "photo.heic")
        try randomData(5_000).write(to: source)
        let sealed = folder.appending(path: BackupCrypto.sealedName("photo.heic"))
        try BackupCrypto.seal(source, to: sealed, name: "photo.heic", key: key)
        let opened = folder.appending(path: "opened.heic")
        #expect(throws: (any Error).self) {
            try BackupCrypto.open(sealed, to: opened, name: "photo.heic", key: SymmetricKey(size: .bits256))
        }
        // Nothing half-written is left behind.
        #expect(!FileManager.default.fileExists(atPath: opened.path(percentEncoded: false)))
    }

    @Test func aChunkCannotBeMovedOrEdited() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "photo.heic")
        try randomData(3_000).write(to: source)
        let sealed = folder.appending(path: BackupCrypto.sealedName("photo.heic"))
        try BackupCrypto.seal(source, to: sealed, name: "photo.heic", key: key)

        // The file's name is sealed in with its bytes, so a sealed file renamed onto
        // another item doesn't open.
        #expect(throws: (any Error).self) {
            try BackupCrypto.open(sealed, to: folder.appending(path: "a"), name: "other.heic", key: key)
        }

        var bytes = try Data(contentsOf: sealed)
        bytes[bytes.count - 1] ^= 0xFF
        let tampered = folder.appending(path: "tampered")
        try bytes.write(to: tampered)
        #expect(throws: (any Error).self) {
            try BackupCrypto.open(tampered, to: folder.appending(path: "b"), name: "photo.heic", key: key)
        }
    }

    @Test func somethingElseIsNotASealedFile() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = folder.appending(path: "plain")
        try Data(repeating: 0x42, count: 100).write(to: plain)
        #expect(throws: BackupError.damaged) {
            try BackupCrypto.open(plain, to: folder.appending(path: "out"), name: "plain", key: key)
        }
    }
}

extension LibraryTests {
    @Suite("Backup and restore")
    @MainActor
    struct RestoreTests {
        private func info() -> BackupInfo {
            BackupInfo(
                id: BackupInfo.makeID(date: .now), format: BackupInfo.currentFormat, createdAt: .now,
                appVersion: "test", deviceName: "Tests", deviceID: "tests", folderCount: 0, itemCount: 0, mediaBytes: 0
            )
        }

        /// The key the tests seal with, standing in for the one in the Keychain.
        private static let key = SymmetricKey(size: .bits256)

        /// A backup folder like the one a file restore extracts. Files from a locked
        /// folder are sealed, under the name the real exporter gives them.
        private func prepared(from library: TestLibrary, dropping dropped: Set<String> = []) throws -> PreparedRestore {
            let manager = FileManager.default
            let snapshot = LibrarySnapshotter.snapshot(context: library.context)
            let folder = library.root.appending(path: "Backup-\(UUID().uuidString)", directoryHint: .isDirectory)
            let media = folder.appending(path: "Media", directoryHint: .isDirectory)
            let thumbnails = folder.appending(path: "Thumbnails", directoryHint: .isDirectory)
            try manager.createDirectory(at: media, withIntermediateDirectories: true)
            try manager.createDirectory(at: thumbnails, withIntermediateDirectories: true)
            let sealedMedia = Set(snapshot.items.filter(\.isSealed).map(\.fileName))
            let sealedThumbnails = Set(snapshot.items.filter(\.isSealed).map(\.thumbnailName))
            for (name, source) in snapshot.mediaSources where !dropped.contains(name) {
                if sealedMedia.contains(name) {
                    try BackupCrypto.seal(source, to: media.appending(path: BackupCrypto.sealedName(name)), name: name, key: Self.key)
                } else {
                    try manager.copyItem(at: source, to: media.appending(path: name))
                }
            }
            for (name, source) in snapshot.thumbnailSources where !dropped.contains(name) {
                if sealedThumbnails.contains(name) {
                    try BackupCrypto.seal(source, to: thumbnails.appending(path: BackupCrypto.sealedName(name)), name: name, key: Self.key)
                } else {
                    try manager.copyItem(at: source, to: thumbnails.appending(path: name))
                }
            }
            let manifest = BackupManifest(info: info(), folders: snapshot.folders, items: snapshot.items)
            return PreparedRestore(manifest: manifest, mediaFolder: media, thumbnailsFolder: thumbnails, canMoveFiles: true, temporaryFolder: folder)
        }

        private func restore(
            _ prepared: PreparedRestore,
            into library: TestLibrary,
            key: SymmetricKey? = Self.key
        ) async throws -> RestoreSummary {
            try await BackupRestorer.restore(prepared, context: library.context, key: key) { _, _ in }
        }

        @Test func snapshotLeavesOutTrashAndYouTubeFiles() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let photo = try library.photo(in: folder)
            let trashed = try library.photo(in: folder)
            let video = try library.link("https://youtu.be/aqz-KE-bpKQ", in: folder)
            let name = "\(video.id.uuidString).jpg"
            try Data([1, 2, 3]).write(to: AppGroup.thumbnailsURL.appending(path: name))
            video.thumbnailName = name
            let deletedFolder = library.folder("Old")
            model.trash([trashed], context: library.context)
            model.trash(folder: deletedFolder, context: library.context)

            let snapshot = LibrarySnapshotter.snapshot(context: library.context)

            #expect(snapshot.folders.map(\.id) == [folder.id])
            #expect(Set(snapshot.items.map(\.id)) == [photo.id, video.id])
            #expect(snapshot.mediaSources.keys.sorted() == [photo.fileName])
            #expect(snapshot.thumbnailSources.keys.sorted() == [photo.thumbnailName])
            let videoRecord = try #require(snapshot.items.first { $0.id == video.id })
            #expect(!videoRecord.hasMedia)
            #expect(!videoRecord.hasThumbnail)
            #expect(videoRecord.linkURL == "https://youtu.be/aqz-KE-bpKQ")
        }

        @Test func restoreAddsOnlyWhatIsMissing() async throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let kept = try library.photo(in: folder)
            let lost = try library.photo(in: folder)
            let keptID = kept.id
            let lostID = lost.id
            let lostFile = lost.fileName
            let backup = try prepared(from: library)

            model.trash([lost], context: library.context)
            model.emptyTrash(context: library.context)
            #expect(!library.fileExists(lostFile))

            let summary = try await restore(backup, into: library)

            #expect(summary.addedItems == 1)
            #expect(summary.alreadyThere == 1)
            #expect(summary.addedFolders == 0)
            #expect(summary.missingFiles == 0)
            let items = LaqtaStore.items(in: folder.id, context: library.context)
            #expect(Set(items.map(\.id)) == [keptID, lostID])
            #expect(library.fileExists(lostFile))
            #expect(summary.message == "Added 1 item. 1 item was already in Laqta.")
            #expect(!FileManager.default.fileExists(atPath: backup.mediaFolder.path(percentEncoded: false)), "The extracted backup is removed")

            // Restoring the same library again changes nothing.
            let again = try await restore(try prepared(from: library), into: library)
            #expect(again.addedItems == 0)
            #expect(again.alreadyThere == 2)
            #expect(again.message == "Everything in this backup is already in Laqta.")
        }

        @Test func restoreRecoversRecentlyDeleted() async throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let item = try library.photo(in: folder)
            let backup = try prepared(from: library)
            model.trash(folder: folder, context: library.context)
            #expect(folder.isInTrash)
            #expect(item.isInTrash)

            let summary = try await restore(backup, into: library)

            #expect(summary.recoveredFolders == 1)
            #expect(summary.recoveredItems == 1)
            #expect(summary.addedItems == 0)
            #expect(!folder.isInTrash)
            #expect(!item.isInTrash)
            #expect(model.trashCount(context: library.context) == 0)
        }

        @Test func restoreRebuildsADeletedFolder() async throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips", locked: true)
            let folderID = folder.id
            try library.photo(in: folder)
            let link = try library.link("https://example.com/guide", in: folder)
            link.note = "Read before the trip"
            try library.context.save()
            let backup = try prepared(from: library)
            model.trash(folder: folder, context: library.context)
            model.emptyTrash(context: library.context)
            #expect(LaqtaStore.foldersByUpdate(library.context).isEmpty)

            let summary = try await restore(backup, into: library)

            #expect(summary.addedFolders == 1)
            #expect(summary.addedItems == 2)
            let restored = try #require(LaqtaStore.foldersByUpdate(library.context).first)
            #expect(restored.id == folderID)
            #expect(restored.name == "Trips")
            #expect(restored.isLocked, "Private folders stay private")
            let items = LaqtaStore.items(in: folderID, context: library.context)
            #expect(items.count == 2)
            let restoredNote = items.first { $0.isLink }?.note
            #expect(restoredNote == "Read before the trip")
        }

        @Test func aLockedFoldersFilesAreSealed() throws {
            let library = try TestLibrary()
            let locked = library.folder("Private", locked: true)
            let inside = library.child("Receipts", of: locked)
            let open = library.folder("Trips")
            let hidden = try library.photo(in: locked)
            let nested = try library.photo(in: inside)
            let shown = try library.photo(in: open)

            let snapshot = LibrarySnapshotter.snapshot(context: library.context)
            let sealed = Set(snapshot.items.filter(\.isSealed).map(\.id))
            #expect(sealed == [hidden.id, nested.id], "A locked folder and everything under it")
            #expect(!sealed.contains(shown.id))

            // The names the backup stores, so the pruner keeps the sealed copies.
            let manifest = BackupManifest(info: info(), folders: snapshot.folders, items: snapshot.items)
            let names = manifest.fileNames
            #expect(names.media.contains(BackupCrypto.sealedName(hidden.fileName)))
            #expect(names.media.contains(shown.fileName))
            #expect(manifest.sealedCount == 2)
        }

        @Test func aSealedBackupRestoresWithItsKey() async throws {
            let library = try TestLibrary()
            let locked = library.folder("Private", locked: true)
            let photo = try library.photo(in: locked)
            let fileName = photo.fileName
            let original = try Data(contentsOf: AppGroup.mediaURL.appending(path: fileName))
            let backup = try prepared(from: library)

            let model = LibraryModel()
            model.trash(folder: locked, context: library.context)
            model.emptyTrash(context: library.context)
            #expect(!library.fileExists(fileName))

            let summary = try await restore(backup, into: library)
            #expect(summary.sealedWithoutKey == 0)
            #expect(summary.addedItems == 1)
            #expect(try Data(contentsOf: AppGroup.mediaURL.appending(path: fileName)) == original)
        }

        @Test func aSealedBackupWithoutItsKeySaysSo() async throws {
            // A device that never had the key — iCloud Keychain off, or another Apple
            // Account. The item stays in the backup and is counted, instead of coming
            // back as an empty photo or not being mentioned at all.
            let library = try TestLibrary()
            let locked = library.folder("Private", locked: true)
            let photo = try library.photo(in: locked)
            let fileName = photo.fileName
            let backup = try prepared(from: library)

            let model = LibraryModel()
            model.trash(folder: locked, context: library.context)
            model.emptyTrash(context: library.context)

            let summary = try await restore(backup, into: library, key: nil)
            #expect(summary.sealedWithoutKey == 1)
            #expect(summary.addedItems == 0)
            #expect(summary.addedFolders == 1, "The folder comes back; only its files are missing")
            #expect(!library.fileExists(fileName))
            #expect(summary.message.contains("locked folders"))
        }

        @Test func itemsWithoutFilesAreReported() async throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let photo = try library.photo(in: folder)
            let link = try library.link("https://example.com/guide", in: folder)
            let backup = try prepared(from: library, dropping: [photo.fileName])
            model.trash([photo, link], context: library.context)
            model.emptyTrash(context: library.context)

            let summary = try await restore(backup, into: library)

            #expect(summary.addedItems == 1, "The link comes back; it has no file")
            #expect(summary.missingFiles == 1)
            #expect(summary.message.contains("1 item couldn't be restored"))
            let remaining = LaqtaStore.items(in: folder.id, context: library.context)
            let onlyLinks = remaining.allSatisfy { $0.isLink }
            #expect(remaining.count == 1)
            #expect(onlyLinks)
        }

        @Test func itemsWithoutAFolderGoToRestored() async throws {
            let library = try TestLibrary()
            let folder = library.folder("Trips")
            try library.photo(in: folder)
            var backup = try prepared(from: library)
            // A backup whose folder list lost this folder.
            backup = PreparedRestore(
                manifest: BackupManifest(info: backup.manifest.info, folders: [], items: backup.manifest.items.map { record in
                    var record = record
                    record.id = UUID()
                    record.folderID = UUID()
                    return record
                }),
                mediaFolder: backup.mediaFolder,
                thumbnailsFolder: backup.thumbnailsFolder,
                canMoveFiles: false,
                temporaryFolder: backup.temporaryFolder
            )

            let summary = try await restore(backup, into: library)

            #expect(summary.addedItems == 1)
            #expect(summary.addedFolders == 1)
            let restoredFolder = try #require(LaqtaStore.foldersByUpdate(library.context).first { $0.name == "Restored" })
            #expect(LaqtaStore.items(in: restoredFolder.id, context: library.context).count == 1)
        }

        @Test func missingMediaCannotProduceASuccessfulBackup() async throws {
            let library = try TestLibrary()
            let folder = library.folder("Trips")
            let photo = try library.photo(in: folder)
            let snapshot = LibrarySnapshotter.snapshot(context: library.context)
            try FileManager.default.removeItem(at: AppGroup.mediaURL.appending(path: photo.fileName))
            await #expect(throws: BackupError.mediaUnavailable) {
                try await BackupEngine.export(snapshot, info: info()) { _, _ in }
            }
            let leftovers = (try? FileManager.default.contentsOfDirectory(at: BackupEngine.exportFolder, includingPropertiesForKeys: nil)) ?? []
            #expect(leftovers.isEmpty)
            BackupEngine.cleanUpExports()
        }

        @Test func fileBackupEndToEnd() async throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let photo = try library.photo(in: folder, bytes: BackupArchive.chunkSize * 2 + 7)
            let photoFile = photo.fileName
            let original = try Data(contentsOf: AppGroup.mediaURL.appending(path: photoFile))
            _ = try library.link("https://example.com/guide", in: folder)
            let snapshot = LibrarySnapshotter.snapshot(context: library.context)

            let archive = try await BackupEngine.export(snapshot, info: info()) { _, _ in }
            defer { BackupEngine.cleanUpExports() }
            #expect(archive.pathExtension == "laqtabackup")

            model.trash(folder: folder, context: library.context)
            model.emptyTrash(context: library.context)
            #expect(!library.fileExists(photoFile))

            let prepared = try await BackupEngine.prepareRestore(fromFile: archive) { _, _ in }
            #expect(prepared.manifest.items.count == 2)
            #expect(prepared.manifest.info.itemCount == 2)
            #expect(prepared.manifest.info.mediaBytes == Int64(original.count))

            let summary = try await restore(prepared, into: library)

            #expect(summary.addedFolders == 1)
            #expect(summary.addedItems == 2)
            #expect(summary.missingFiles == 0)
            #expect(try Data(contentsOf: AppGroup.mediaURL.appending(path: photoFile)) == original)
            #expect(!FileManager.default.fileExists(atPath: prepared.mediaFolder.path(percentEncoded: false)))
        }
    }
}
