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

    init() {
        AppGroup.registerDefaults()
        open()
        if !AppEnvironment.isRunningTests {
            Task.detached(priority: .utility) {
                _ = await CloudContainer.resolve()
            }
        }
    }

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

    /// Closes the library and opens it again with the current iCloud setting.
    @discardableResult
    func reopen() async -> Bool {
        guard !isReopening else { return false }
        isReopening = true
        container?.mainContext.processPendingChanges()
        do {
            try container?.mainContext.save()
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
