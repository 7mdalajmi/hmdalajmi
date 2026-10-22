//
//  LibraryStore.swift
//  Laqta
//
//  Opens the library, with or without iCloud sync, and reopens it when sync is switched.
//

import Foundation
import Observation
import SwiftData

@Observable
final class LibraryStore {
    private(set) var container: ModelContainer?
    private(set) var launchError: String?
    /// The library is closing to reopen with a different iCloud setting.
    private(set) var isReopening = false
    /// CloudKit mirroring is on for the open library.
    private(set) var isSyncActive = false
    /// A damaged library is being moved aside.
    private(set) var isRecovering = false

    init() {
        AppGroup.registerDefaults()
        open()
        if !AppEnvironment.isRunningTests {
            Task.detached(priority: .utility) {
                _ = await CloudContainer.resolve()
            }
        }
    }

    /// A library that opens nothing, for a view that is somehow evaluated without the
    /// app's own (see AppObject). Opening the store a second time would put two
    /// writers on one file; a screen that sees no library does nothing instead.
    init(standIn: Bool) {}

    private func open() {
        let inMemory = AppEnvironment.isRunningTests
        let wantsSync = !inMemory && CloudConfig.isSyncEnabled && CloudConfig.isAccountAvailable
        #if DEBUG
        if wantsSync {
            CloudSchema.initializeIfNeeded()
        }
        #endif
        do {
            let container = try LaqtaStore.makeContainer(cloudSync: wantsSync, inMemory: inMemory)
            if !inMemory {
                LaqtaStore.seedIfNeeded(container.mainContext)
            }
            self.container = container
            isSyncActive = wantsSync
            launchError = nil
        } catch {
            DebugLog.write("store: open failed sync=\(wantsSync) \(error)")
            guard wantsSync else {
                container = nil
                isSyncActive = false
                launchError = error.localizedDescription
                return
            }
            // Keep the library usable on this device if iCloud can't be set up.
            do {
                let container = try LaqtaStore.makeContainer(cloudSync: false)
                LaqtaStore.seedIfNeeded(container.mainContext)
                self.container = container
                isSyncActive = false
                launchError = nil
                AppGroup.defaults.set(error.localizedDescription, forKey: SettingsKey.lastSyncError)
            } catch {
                container = nil
                isSyncActive = false
                launchError = error.localizedDescription
            }
        }
    }

    /// Opens the library again, in place, after a failure that may have passed
    /// (an iCloud account that has signed in, a device that has room again).
    @discardableResult
    func tryAgain() -> Bool {
        guard container == nil, !isRecovering else { return false }
        open()
        return container != nil
    }

    /// Moves the library that won't open aside and opens a new, empty one in its place.
    ///
    /// The old files are kept under `Damaged/`: they are the only copy of whatever the
    /// last backup doesn't have, and the alternative — an app that cannot start — is
    /// not a choice anyone would make.
    @discardableResult
    func recoverFromDamagedLibrary() -> Bool {
        guard container == nil, !isRecovering else { return false }
        isRecovering = true
        defer { isRecovering = false }
        do {
            let folder = try LaqtaStore.setDamagedLibraryAside()
            DebugLog.write("store: damaged library moved to \(folder.lastPathComponent)")
        } catch {
            DebugLog.write("store: couldn't move the damaged library — \(error)")
            launchError = error.localizedDescription
            return false
        }
        open()
        guard container != nil else { return false }
        // The flag outlives this launch on purpose: if the app is closed before the
        // restore starts, the next launch still puts the backup back.
        AppGroup.defaults.set(true, forKey: SettingsKey.needsBackupAfterRecovery)
        return true
    }

    /// Closes the library and opens it again with the current iCloud setting.
    @discardableResult
    func reopen() async -> Bool {
        guard !isReopening else { return false }
        isReopening = true
        container?.mainContext.processPendingChanges()
        do {
            try container?.mainContext.commit()
        } catch {
            isReopening = false
            AppGroup.defaults.set(error.localizedDescription, forKey: SettingsKey.lastSyncError)
            return false
        }
        container = nil
        // Let the views that used the old container go away first.
        try? await Task.sleep(for: .milliseconds(450))
        open()
        isReopening = false
        return container != nil
    }
}
