//
//  LockManager.swift
//  Laqta
//
//  Opens private folders with Face ID or the device passcode.
//

import Foundation
import LocalAuthentication
import Observation
import SwiftData

@Observable
final class LockManager {
    private(set) var unlockedFolderIDs: Set<UUID> = []
    /// Recently Deleted can hold items from private folders.
    private(set) var trashUnlocked = false

    var locksEnabled: Bool {
        AppGroup.bool(SettingsKey.lockPrivateFolders)
    }

    func isUnlocked(_ folderID: UUID) -> Bool {
        !locksEnabled || unlockedFolderIDs.contains(folderID)
    }

    /// True when the folder's contents may be shown right now.
    func canShow(_ folder: Folder) -> Bool {
        guard locksEnabled else { return true }
        if unlockedFolderIDs.contains(folder.id) { return true }
        guard let context = folder.modelContext,
              let folders = try? context.fetch(FetchDescriptor<Folder>()) else {
            return !folder.isLocked && folder.parentID == nil
        }
        return LaqtaStore.path(to: folder.id, in: folders).allSatisfy {
            !$0.isLocked || unlockedFolderIDs.contains($0.id)
        }
    }

    func unlock(_ folderID: UUID) async -> Bool {
        if isUnlocked(folderID) { return true }
        let success = await authenticate(reason: "Open your private folder")
        if success { unlockedFolderIDs.insert(folderID) }
        return success
    }

    func unlockTrash() async -> Bool {
        if !locksEnabled || trashUnlocked { return true }
        let success = await authenticate(reason: "Open Recently Deleted")
        if success { trashUnlocked = true }
        return success
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    func lock(_ folderID: UUID) {
        unlockedFolderIDs.remove(folderID)
    }

    func lockAll() {
        unlockedFolderIDs.removeAll()
        trashUnlocked = false
    }
}
