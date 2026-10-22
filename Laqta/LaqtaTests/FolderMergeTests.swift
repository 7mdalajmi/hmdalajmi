//
//  FolderMergeTests.swift
//  LaqtaTests
//

import Foundation
import SwiftData
import Testing
@testable import Laqta

extension LibraryTests {
    @Suite("Folder merge")
    @MainActor
    struct FolderMergeTests {
        @Test func onlyExactNamesPairUp() throws {
            let library = try TestLibrary()
            library.folder("Travel")
            library.folder("Travel ")
            library.folder("travel")
            library.folder("Cities")

            let pairs = FolderMerge.pairs(context: library.context)

            // A stray space is invisible to the reader; different letters are not the same name.
            #expect(pairs.count == 1)
            #expect(pairs.first?.name.trimmingCharacters(in: .whitespaces) == "Travel")
        }

        @Test func anEmptySideMergesWithoutAsking() throws {
            let library = try TestLibrary()
            let kept = library.folder("Travel")
            let arrived = library.folder("Travel")
            try library.photo(in: kept)
            try library.photo(in: kept)

            let pairs = FolderMerge.pairs(context: library.context)
            #expect(pairs.count == 1)
            #expect(FolderMerge.needingAnswer(pairs).isEmpty)

            #expect(FolderMerge.mergeEmptySided(context: library.context) == 1)

            #expect(LaqtaStore.folder(with: arrived.id, context: library.context) == nil)
            #expect(LaqtaStore.itemCount(in: kept.id, context: library.context) == 2)
            #expect(FolderMerge.pairs(context: library.context).isEmpty)
        }

        @Test func twoFullFoldersWaitForAnAnswer() throws {
            let library = try TestLibrary()
            let bigger = library.folder("Travel")
            let smaller = library.folder("Travel")
            try library.photo(in: bigger)
            try library.photo(in: bigger)
            try library.photo(in: smaller)

            let pairs = FolderMerge.needingAnswer(FolderMerge.pairs(context: library.context))
            let pair = try #require(pairs.first)

            // Nothing moves on its own.
            #expect(FolderMerge.mergeEmptySided(context: library.context) == 0)
            // The fuller folder stays, so the fewest items move.
            #expect(pair.keepID == bigger.id)
            #expect(pair.keepCount == 2)
            #expect(pair.mergeCount == 1)
            #expect(pair.total == 3)
        }

        @Test func mergingMovesEverythingIntoOneFolder() throws {
            let library = try TestLibrary()
            let kept = library.folder("Travel")
            let arrived = library.folder("Travel", locked: true)
            try library.photo(in: kept)
            try library.photo(in: kept)
            let moving = try library.photo(in: arrived)
            let trashed = try library.photo(in: arrived)
            LibraryModel().trash([trashed], context: library.context)

            let pair = try #require(FolderMerge.pairs(context: library.context).first)
            FolderMerge.merge(pair, context: library.context)

            #expect(LaqtaStore.folder(with: arrived.id, context: library.context) == nil)
            #expect(LaqtaStore.itemCount(in: kept.id, context: library.context) == 3)
            #expect(LaqtaStore.item(with: moving.id, context: library.context)?.folderID == kept.id)
            // An item in Recently Deleted still has a folder to go back to.
            #expect(LaqtaStore.item(with: trashed.id, context: library.context)?.folderID == kept.id)
            // The lock travels with it, so nothing becomes more visible than it was.
            #expect(LaqtaStore.folder(with: kept.id, context: library.context)?.isLocked == true)
        }

        @Test func keepingBothIsNotAskedAgain() throws {
            let library = try TestLibrary()
            let first = library.folder("Travel")
            let second = library.folder("Travel")
            try library.photo(in: first)
            try library.photo(in: second)

            let pair = try #require(FolderMerge.needingAnswer(FolderMerge.pairs(context: library.context)).first)
            FolderMerge.decline(pair)

            #expect(FolderMerge.isDeclined(pair))
            #expect(FolderMerge.needingAnswer(FolderMerge.pairs(context: library.context)).isEmpty)
            // Both folders are still there, and the offer stays reachable from the folder's menu.
            #expect(FolderMerge.pairs(context: library.context).count == 1)
            #expect(FolderMerge.twin(of: second.id, folders: folders(library), counts: counts(library)) != nil)

            // A refusal also holds when one side is emptied later.
            LibraryModel().trash(LaqtaStore.items(in: second.id, context: library.context), context: library.context)
            #expect(FolderMerge.mergeEmptySided(context: library.context) == 0)
        }

        @Test func threeOfTheSameNameFoldIntoOne() throws {
            let library = try TestLibrary()
            let kept = library.folder("Travel")
            library.folder("Travel")
            library.folder("Travel")
            try library.photo(in: kept)

            #expect(FolderMerge.mergeEmptySided(context: library.context) == 2)

            let left = try library.context.fetch(FetchDescriptor<Folder>())
            #expect(left.count == 1)
            #expect(left.first?.id == kept.id)
        }

        @Test func mergingClearsTheRememberedRefusal() throws {
            let library = try TestLibrary()
            let first = library.folder("Travel")
            let second = library.folder("Travel")
            try library.photo(in: first)
            try library.photo(in: second)

            let pair = try #require(FolderMerge.pairs(context: library.context).first)
            FolderMerge.decline(pair)
            FolderMerge.merge(pair, context: library.context)

            #expect(!FolderMerge.isDeclined(pair))
            #expect(LaqtaStore.folder(with: second.id, context: library.context) == nil)
        }

        // MARK: Helpers

        private func folders(_ library: TestLibrary) -> [Folder] {
            (try? library.context.fetch(FetchDescriptor<Folder>())) ?? []
        }

        private func counts(_ library: TestLibrary) -> [UUID: Int] {
            var result: [UUID: Int] = [:]
            for folder in folders(library) {
                result[folder.id] = LaqtaStore.itemCount(in: folder.id, context: library.context)
            }
            return result
        }
    }
}
