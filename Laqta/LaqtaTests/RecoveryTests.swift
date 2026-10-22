//
//  RecoveryTests.swift
//  LaqtaTests
//
//  What happens when the library can't be saved, and when it can't be opened at all.
//

import Foundation
import SwiftData
import Testing
@testable import Laqta

extension LibraryTests {
    @Suite("Saving and recovery")
    @MainActor
    struct SaveRecoveryTests {
        @Test func aFailedSaveIsRememberedUntilItIsAnswered() {
            let center = SaveFailureCenter.shared
            center.reset()
            defer { center.reset() }

            var runs = 0
            center.record(CocoaError(.fileWriteOutOfSpace), operation: .move, retry: { runs += 1 })
            #expect(center.failure?.operation == .move)
            #expect(center.failure?.canRetry == true)
            #expect(center.failure?.attempts == 1)
            #expect(!(center.failure?.message.isEmpty ?? true))

            center.retry()
            #expect(runs == 1)
            // The work records its own failure if it fails again, so silence means
            // it went in.
            #expect(center.failure == nil)

            center.record(CocoaError(.fileWriteUnknown), operation: .analysis, retry: nil)
            #expect(center.failure?.canRetry == false)
            center.retry()
            #expect(center.failure != nil, "Nothing to retry, so the bar stays")
            center.dismiss()
            #expect(center.failure == nil)
        }

        @Test func theSameWorkFailingAgainCountsUp() {
            let center = SaveFailureCenter.shared
            center.reset()
            defer { center.reset() }

            center.record(CocoaError(.fileWriteUnknown), operation: .trash, retry: {
                SaveFailureCenter.shared.record(CocoaError(.fileWriteUnknown), operation: .trash, retry: nil)
            })
            #expect(center.failure?.attempts == 1)
            center.retry()
            #expect(center.failure?.attempts == 2, "Three times in a row is worth saying")
        }

        @Test func aLibraryThatWontOpenIsMovedAsideAndKept() throws {
            let library = try TestLibrary()
            _ = library
            let manager = FileManager.default
            let files = LaqtaStore.libraryFileURLs
            try Data("store".utf8).write(to: files[0])
            try Data("wal".utf8).write(to: files[1])

            let moved = try LaqtaStore.setDamagedLibraryAside()

            #expect(!manager.fileExists(atPath: files[0].path(percentEncoded: false)))
            #expect(!manager.fileExists(atPath: files[1].path(percentEncoded: false)))
            // Kept, not deleted: it is the only copy of whatever the last backup missed.
            #expect(try Data(contentsOf: moved.appending(path: files[0].lastPathComponent)) == Data("store".utf8))
            #expect(try Data(contentsOf: moved.appending(path: files[1].lastPathComponent)) == Data("wal".utf8))
            #expect(moved.path(percentEncoded: false).hasPrefix(LaqtaStore.damagedURL.path(percentEncoded: false)))

            // Nothing left to move: a missing library isn't a damaged one.
            #expect(throws: (any Error).self) {
                try LaqtaStore.setDamagedLibraryAside()
            }
        }
    }
}
