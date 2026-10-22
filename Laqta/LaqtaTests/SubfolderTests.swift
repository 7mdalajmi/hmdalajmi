//
//  SubfolderTests.swift
//  LaqtaTests
//

import Foundation
import SwiftData
import Testing
@testable import Laqta

extension LibraryTests {
    @Suite("Subfolders")
    @MainActor
    struct SubfolderTests {
        @Test func privateParentsProtectEveryDescendant() throws {
            let library = try TestLibrary()
            let parent = library.folder("Private", locked: true)
            let child = library.child("Receipts", of: parent)
            let nested = library.child("Older", of: child)
            let publicFolder = library.folder("Public")
            let lock = LockManager()

            #expect(parent.isPrivate)
            #expect(child.isPrivate)
            #expect(nested.isPrivate)
            #expect(!lock.canShow(parent))
            #expect(!lock.canShow(child))
            #expect(!lock.canShow(nested))
            #expect(lock.canShow(publicFolder))
            #expect(LibraryWriter.snapshots(library.context).filter { $0.isLocked }.count == 3)
            AppGroup.defaults.set(false, forKey: SettingsKey.lockPrivateFolders)
            #expect(lock.canShow(nested))
        }

        @Test func cancellingBeforePreparationCannotStartOrSave() async throws {
            let library = try TestLibrary()
            let folder = library.folder("Trips")
            var cancelled = 0
            var finished = 0
            let session = SaveSession(inputs: [], onFinish: { finished += 1 }, onCancel: { cancelled += 1 })
            session.cancel()
            session.cancel()
            await session.start(context: library.context)
            await session.save(to: folder, context: library.context)
            #expect(cancelled == 1)
            #expect(finished == 0)
            #expect(session.phase == .preparing)
            #expect(LaqtaStore.items(in: folder.id, context: library.context).isEmpty)
        }

        @Test func homeShowsTheTopLevelOnly() throws {
            let library = try TestLibrary()
            let travel = library.folder("Travel")
            let child = library.child("Flights", of: travel)
            library.folder("Cities")

            let top = LaqtaStore.folders(inside: nil, context: library.context)
            #expect(top.map(\.name).sorted() == ["Cities", "Travel"])
            #expect(LaqtaStore.folders(inside: travel.id, context: library.context).map(\.id) == [child.id])
            #expect(LaqtaStore.subfolderCounts(library.everyFolder())[travel.id] == 1)
        }

        @Test func descendantsReachEveryDepth() throws {
            let library = try TestLibrary()
            let travel = library.folder("Travel")
            let flights = library.child("Flights", of: travel)
            let stubs = library.child("Boarding passes", of: flights)
            library.folder("Cities")

            let names = LaqtaStore.descendants(of: travel.id, in: library.everyFolder()).map(\.name)
            #expect(Set(names) == ["Flights", "Boarding passes"])
            #expect(LaqtaStore.path(to: stubs.id, in: library.everyFolder()).map(\.name) == ["Travel", "Flights", "Boarding passes"])
        }

        @Test func aFolderCannotBeMovedIntoItself() throws {
            let library = try TestLibrary()
            let travel = library.folder("Travel")
            let flights = library.child("Flights", of: travel)
            let cities = library.folder("Cities")
            let all = library.everyFolder()

            #expect(LaqtaStore.wouldLoop(moving: travel.id, into: travel.id, folders: all))
            #expect(LaqtaStore.wouldLoop(moving: travel.id, into: flights.id, folders: all))
            #expect(!LaqtaStore.wouldLoop(moving: flights.id, into: cities.id, folders: all))
            #expect(!LaqtaStore.wouldLoop(moving: travel.id, into: nil, folders: all))
        }

        @Test func deletingAFolderTakesWhatIsInsideIt() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let travel = library.folder("Travel")
            let flights = library.child("Flights", of: travel)
            let outside = library.folder("Cities")
            let inner = try library.photo(in: flights)
            let untouched = try library.photo(in: outside)

            model.trash(folder: travel, context: library.context)

            #expect(travel.isInTrash)
            #expect(flights.isInTrash)
            #expect(inner.isInTrash)
            #expect(!untouched.isInTrash)
            #expect(LaqtaStore.folders(inside: nil, context: library.context).map(\.name) == ["Cities"])
        }

        @Test func restoringAFolderBringsItsFoldersBack() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let travel = library.folder("Travel")
            let flights = library.child("Flights", of: travel)
            let inner = try library.photo(in: flights)

            model.trash(folder: travel, context: library.context)
            model.restore(folder: travel, context: library.context)

            #expect(!travel.isInTrash)
            #expect(!flights.isInTrash)
            #expect(!inner.isInTrash)
            #expect(LaqtaStore.folders(inside: travel.id, context: library.context).map(\.id) == [flights.id])
        }

        @Test func aFolderWhoseParentIsGoneComesBackToHome() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let travel = library.folder("Travel")
            let flights = library.child("Flights", of: travel)

            model.trash(folder: flights, context: library.context)
            model.deletePermanently(folder: travel, context: library.context)
            model.restore(folder: flights, context: library.context)

            #expect(flights.parentID == nil)
            #expect(LaqtaStore.folders(inside: nil, context: library.context).map(\.name) == ["Flights"])
        }

        @Test func deletingForGoodTakesTheWholeBranch() throws {
            let library = try TestLibrary()
            let model = LibraryModel()
            let travel = library.folder("Travel")
            let flights = library.child("Flights", of: travel)
            let item = try library.photo(in: flights)
            let fileName = item.fileName

            model.trash(folder: travel, context: library.context)
            model.deletePermanently(folder: travel, context: library.context)

            #expect(library.everyFolder().isEmpty)
            #expect(try library.context.fetch(FetchDescriptor<Shot>()).isEmpty)
            #expect(!library.fileExists(fileName))
        }

        @Test func sameNameInDifferentFoldersIsNotADuplicate() throws {
            let library = try TestLibrary()
            let travel = library.folder("Travel")
            let work = library.folder("Work")
            let a = library.child("Receipts", of: travel)
            let b = library.child("Receipts", of: work)
            try library.photo(in: a)
            try library.photo(in: b)

            // Two folders called "Receipts" in different places are two different folders.
            #expect(FolderMerge.pairs(context: library.context).isEmpty)

            let alsoInTravel = library.child("Receipts", of: travel)
            try library.photo(in: alsoInTravel)
            let pairs = FolderMerge.pairs(context: library.context)
            #expect(pairs.count == 1)
            #expect(Set([pairs[0].keepID, pairs[0].mergeID]) == Set([a.id, alsoInTravel.id]))
        }

        @Test func mergingCarriesTheFoldersInside() throws {
            let library = try TestLibrary()
            let keep = library.folder("Travel")
            let arrived = library.folder("Travel")
            let inside = library.child("Flights", of: arrived)
            try library.photo(in: keep)

            #expect(FolderMerge.mergeEmptySided(context: library.context) == 1)

            #expect(LaqtaStore.folder(with: arrived.id, context: library.context) == nil)
            #expect(LaqtaStore.folder(with: inside.id, context: library.context)?.parentID == keep.id)
        }

        @Test func backupsKeepTheNesting() throws {
            let library = try TestLibrary()
            let travel = library.folder("Travel")
            let flights = library.child("Flights", of: travel)

            let record = LibrarySnapshotter.record(for: flights)
            #expect(record.parentID == travel.id)
            #expect(LibrarySnapshotter.record(for: travel).parentID == nil)
        }
    }
}
