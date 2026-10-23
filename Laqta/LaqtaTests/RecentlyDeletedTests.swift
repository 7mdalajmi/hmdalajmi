//
//  RecentlyDeletedTests.swift
//  LaqtaTests
//

import Foundation
import SwiftData
import Testing
@testable import Laqta

extension LibraryTests {
    @Suite("Recently Deleted")
    @MainActor
    struct RecentlyDeletedTests {
        @Test func deletingADuplicateRecordRetainsSharedFiles() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let first = try library.photo(in: folder)
            let second = try library.photo(in: folder)
            let sharedFile = first.fileName
            let sharedThumbnail = first.thumbnailName
            MediaStore.deleteStoredFiles(fileName: second.fileName, thumbnailName: second.thumbnailName)
            second.fileName = sharedFile
            second.thumbnailName = sharedThumbnail
            try library.context.save()

            model.trash([first], context: library.context)
            model.deletePermanently([first], context: library.context)
            #expect(library.fileExists(sharedFile))
            #expect(FileManager.default.fileExists(atPath: AppGroup.thumbnailsURL.appending(path: sharedThumbnail).path(percentEncoded: false)))
            #expect(LaqtaStore.items(in: folder.id, context: library.context).map(\.id) == [second.id])

            model.trash([second], context: library.context)
            model.emptyTrash(context: library.context)
            #expect(!library.fileExists(sharedFile))
        }

        @Test func trashingHidesItemsButKeepsFiles() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let first = try library.photo(in: folder)
            let second = try library.photo(in: folder)

            model.trash([first], context: library.context)

            #expect(first.isInTrash)
            #expect(!second.isInTrash)
            #expect(LaqtaStore.items(in: folder.id, context: library.context).map(\.id) == [second.id])
            #expect(LaqtaStore.itemCount(in: folder.id, context: library.context) == 1)
            #expect(model.trashCount(context: library.context) == 1)
            #expect(library.fileExists(first.fileName))
        }

        @Test func restoreBringsItemsBack() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Trips")
            let item = try library.photo(in: folder)

            model.trash([item], context: library.context)
            model.restore([item], context: library.context)

            #expect(!item.isInTrash)
            #expect(item.deletionBatch == nil)
            #expect(model.trashCount(context: library.context) == 0)
            #expect(LaqtaStore.itemCount(in: folder.id, context: library.context) == 1)
        }

        @Test func folderComesBackWithItsOwnItemsOnly() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Receipts")
            let deletedEarlier = try library.photo(in: folder)
            let kept = try library.photo(in: folder)

            model.trash([deletedEarlier], context: library.context)
            model.trash(folder: folder, context: library.context)

            #expect(folder.isInTrash)
            #expect(kept.isInTrash)
            #expect(LaqtaStore.foldersByUpdate(library.context).isEmpty)

            model.restore(folder: folder, context: library.context)

            #expect(!folder.isInTrash)
            #expect(!kept.isInTrash)
            // Deleted on its own before the folder, so it stays in Recently Deleted.
            #expect(deletedEarlier.isInTrash)
        }

        @Test func restoringAnItemRestoresItsFolder() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Menus")
            let item = try library.photo(in: folder)

            model.trash(folder: folder, context: library.context)
            model.restore([item], context: library.context)

            #expect(!folder.isInTrash)
            #expect(!item.isInTrash)
        }

        @Test func expiredItemsArePurgedWithTheirFiles() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Old")
            let expired = try library.photo(in: folder)
            let recent = try library.photo(in: folder)
            let expiredFile = expired.fileName

            model.trash([expired, recent], context: library.context)
            expired.deletedAt = Date.now.addingTimeInterval(-31 * 86_400)
            try library.context.save()

            let removed = model.purgeExpiredTrash(context: library.context)

            #expect(removed == 1)
            #expect(LaqtaStore.items(withIDs: [expired.id, recent.id], context: library.context).map(\.id) == [recent.id])
            #expect(!library.fileExists(expiredFile))
            #expect(library.fileExists(recent.fileName))
        }

        @Test func expiredFolderGoesOnlyWhenEmpty() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Gone")
            let item = try library.photo(in: folder)

            model.trash(folder: folder, context: library.context)
            folder.deletedAt = Date.now.addingTimeInterval(-40 * 86_400)
            item.deletedAt = Date.now.addingTimeInterval(-40 * 86_400)
            try library.context.save()

            model.purgeExpiredTrash(context: library.context)

            #expect(LaqtaStore.folder(with: folder.id, context: library.context) == nil)
        }

        @Test func emptyTrashRemovesEverythingDeleted() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let keep = library.folder("Keep")
            let drop = library.folder("Drop")
            let live = try library.photo(in: keep)
            _ = try library.photo(in: drop)
            let loose = try library.photo(in: keep)

            model.trash([loose], context: library.context)
            model.trash(folder: drop, context: library.context)
            model.emptyTrash(context: library.context)

            #expect(model.trashCount(context: library.context) == 0)
            #expect(LaqtaStore.folder(with: drop.id, context: library.context) == nil)
            #expect(LaqtaStore.items(in: keep.id, context: library.context).map(\.id) == [live.id])
        }

        @Test func notesUpdateTheSearchIndex() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Ideas")
            let item = try library.photo(in: folder)

            model.setNote("  Blue sofa from the showroom  ", for: item, context: library.context)

            #expect(item.note == "Blue sofa from the showroom")
            #expect(item.noteUpdatedAt != nil)
            #expect(item.tags.contains(.note))
            #expect(item.searchText?.localizedCaseInsensitiveContains("sofa") == true)

            model.setNote("", for: item, context: library.context)
            #expect(!item.tags.contains(.note))
        }

        @Test func folderSortIsStored() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let folder = library.folder("Sorted")
            #expect(folder.sort == .newest)
            #expect(folder.sortRaw == nil)

            model.setSort(.title, for: folder, context: library.context)
            #expect(folder.sort == .title)

            model.setSort(.newest, for: folder, context: library.context)
            #expect(folder.sortRaw == nil)
        }
    }
}
