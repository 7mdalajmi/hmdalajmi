//
//  LibrarySave.swift
//  Laqta — Shared (App + Share Extension)
//
//  Every change the library makes is saved here and nowhere else.
//
//  `try? context.save()` was the bug: a save that failed was dropped on the floor.
//  The change stayed on screen, the library never had it, and the next launch showed
//  it gone — a moved item back in its old folder, a note empty, an emptied trash full
//  again. `commit` puts the change back (so what is on screen and what is stored agree
//  again), says so once, and offers to do the same work over.
//

import Foundation
import Observation
import SwiftData
import SwiftUI

/// What the library was saving. It names the failure and reaches the log.
nonisolated enum SaveOperation: String, Sendable {
    case change
    case newFolder
    case folderEdit
    case move
    case note
    case favorite
    case sort
    case trash
    case restore
    case delete
    case emptyTrash
    case purge
    case photoCleanup
    case analysis
    case transcript
    case linkDetails
    case merge
    case deduplicate
    case cloudMove
    case restoreBackup
    case backupRecord
    case setUp

    /// Completes "Laqta couldn't …".
    var detail: String {
        switch self {
        case .change: String(localized: "save that change")
        case .newFolder: String(localized: "make that folder")
        case .folderEdit: String(localized: "save the folder")
        case .move: String(localized: "move those items")
        case .note: String(localized: "save that note")
        case .favorite: String(localized: "save that favorite")
        case .sort: String(localized: "save how this folder is sorted")
        case .trash: String(localized: "move that to Recently Deleted")
        case .restore: String(localized: "put that back")
        case .delete: String(localized: "delete that for good")
        case .emptyTrash: String(localized: "empty Recently Deleted")
        case .purge: String(localized: "clear out Recently Deleted")
        case .photoCleanup: String(localized: "record what happened in Photos")
        case .analysis: String(localized: "save what it read")
        case .transcript: String(localized: "save the speech it read")
        case .linkDetails: String(localized: "save the link's details")
        case .merge: String(localized: "merge those folders")
        case .deduplicate: String(localized: "tidy up the copies iCloud sent")
        case .cloudMove: String(localized: "move your files to iCloud")
        case .restoreBackup: String(localized: "restore that backup")
        case .backupRecord: String(localized: "record the backup")
        case .setUp: String(localized: "set up your library")
        }
    }
}

/// The one place a failed save is remembered, so every screen shows the same bar.
@MainActor
@Observable
final class SaveFailureCenter {
    static let shared = SaveFailureCenter()

    nonisolated struct Failure: Identifiable, Equatable, Sendable {
        let id: UUID
        let operation: SaveOperation
        /// What the store said, for the sheet and for a support mail.
        let reason: String
        /// How many times this same work has failed in a row.
        var attempts: Int
        var canRetry: Bool
        var at: Date

        /// "Laqta couldn't save that change."
        var message: String {
            String(localized: "Laqta couldn't \(operation.detail).")
        }
    }

    private(set) var failure: Failure?
    private(set) var isRetrying = false

    /// The same work again, for the Try Again button. It saves through `commit`, so a
    /// second failure reports itself.
    @ObservationIgnored private var work: (@MainActor () -> Void)?
    /// Carried across a retry, so the sheet can say "three times".
    @ObservationIgnored private var carriedAttempts = 0

    /// A save failed. The change has already been put back by `commit`.
    func record(_ error: any Error, operation: SaveOperation, retry: (@MainActor () -> Void)?) {
        DebugLog.write("save: \(operation.rawValue) failed — \(error)")
        work = retry
        let failed = Failure(
            id: UUID(),
            operation: operation,
            reason: (error as NSError).localizedDescription,
            attempts: carriedAttempts + 1,
            canRetry: retry != nil,
            at: .now
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            failure = failed
        }
        AccessibilityNotification.Announcement(failed.message).post()
    }

    /// Does the same work again. A failure on the way through records itself, so the
    /// bar stays; silence means it went in.
    func retry() {
        guard !isRetrying, let work, failure != nil else { return }
        isRetrying = true
        carriedAttempts = failure?.attempts ?? 0
        withAnimation(.easeOut(duration: 0.2)) { failure = nil }
        self.work = nil
        work()
        carriedAttempts = 0
        isRetrying = false
    }

    func dismiss() {
        work = nil
        carriedAttempts = 0
        withAnimation(.easeOut(duration: 0.25)) { failure = nil }
    }

    /// Only for tests.
    func reset() {
        work = nil
        carriedAttempts = 0
        failure = nil
        isRetrying = false
    }
}

extension ModelContext {
    /// Saves the library, or puts the change back and throws.
    ///
    /// Rolling back is the point: a half-applied change that only exists in memory
    /// is worse than no change, because every screen believes it and the next launch
    /// doesn't.
    nonisolated func commit() throws {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }

    /// Saves the library and, when that fails, shows the bar that says so.
    ///
    /// `retry` is the same work again, from the top: after the rollback the objects
    /// hold what the store holds, so the work has to re-apply its change before it
    /// saves. Leave it out where the work can't be repeated safely.
    @discardableResult
    func commit(_ operation: SaveOperation, retry: (@MainActor () -> Void)? = nil) -> Bool {
        do {
            try commit()
            return true
        } catch {
            SaveFailureCenter.shared.record(error, operation: operation, retry: retry)
            return false
        }
    }
}
