//
//  CloudSyncModel.swift
//  Laqta
//
//  iCloud sync: turning it on and off, what's happening now, moving media into iCloud,
//  and merging records that arrive twice.
//

import CoreData
import Foundation
import Observation
import SwiftData

@Observable
final class CloudSyncModel {
    enum Status: Equatable {
        /// Sync is off on this device.
        case off
        /// No iCloud account, or iCloud Drive is off for Laqta.
        case unavailable
        case syncing
        case uploading(Int)
        case upToDate(Date?)
        case failed(String)
    }

    enum Switching: Equatable {
        case none
        case turningOn
        case downloading(done: Int, total: Int)
        case turningOff
    }

    private(set) var status: Status = .off
    private(set) var switching: Switching = .none
    private(set) var lastSync: Date?
    private(set) var pendingUploads = 0

    var isEnabled: Bool { AppGroup.bool(SettingsKey.cloudSync) }
    var isAccountAvailable: Bool { CloudConfig.isAccountAvailable }

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    @ObservationIgnored private var remoteChangeTask: Task<Void, Never>?
    @ObservationIgnored private var cancelSwitch = false
    @ObservationIgnored private weak var store: LibraryStore?
    @ObservationIgnored private weak var library: LibraryModel?
    @ObservationIgnored private var runningEvents: Set<UUID> = []

    // MARK: Lifecycle

    func start(store: LibraryStore, library: LibraryModel) {
        guard observers.isEmpty else { return }
        self.store = store
        self.library = library
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
            let snapshot = event.map { EventSnapshot($0) }
            MainActor.assumeIsolated {
                if let snapshot { self?.handle(snapshot) }
            }
        })
        observers.append(center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRemoteChangeWork()
            }
        })
        observers.append(center.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.accountChanged()
            }
        })
        refreshStatus()
    }

    func refreshStatus() {
        guard isEnabled else {
            status = .off
            return
        }
        guard isAccountAvailable else {
            status = .unavailable
            return
        }
        guard store?.isSyncActive == true else {
            if let message = AppGroup.defaults.string(forKey: SettingsKey.lastSyncError) {
                status = .failed(message)
            } else {
                status = .unavailable
            }
            return
        }
        if pendingUploads > 0 {
            status = .uploading(pendingUploads)
        } else if !runningEvents.isEmpty {
            status = .syncing
        } else if case .failed = status {
            return
        } else {
            status = .upToDate(lastSync)
        }
    }

    /// When the app becomes active: find the iCloud container, then upload new media.
    func appDidBecomeActive(context: ModelContext) {
        refreshStatus()
        guard isEnabled, store?.isSyncActive == true else { return }
        Task {
            if !CloudContainer.isResolved {
                _ = await CloudContainer.resolve()
            }
            await uploadPendingMedia(context: context)
        }
    }

    private func accountChanged() {
        CloudContainer.reset()
        Task.detached(priority: .utility) {
            _ = await CloudContainer.resolve()
        }
        refreshStatus()
    }

    // MARK: Events

    /// The parts of a CloudKit event Laqta shows.
    nonisolated private struct EventSnapshot: Sendable {
        let id: UUID
        let isFinished: Bool
        let succeeded: Bool
        let endDate: Date?
        let errorMessage: String?
        let isSetup: Bool

        init(_ event: NSPersistentCloudKitContainer.Event) {
            id = event.identifier
            isFinished = event.endDate != nil
            succeeded = event.succeeded
            endDate = event.endDate
            isSetup = event.type == .setup
            errorMessage = event.error.map(CloudSyncModel.message(for:))
        }
    }

    private func handle(_ event: EventSnapshot) {
        if event.isFinished {
            runningEvents.remove(event.id)
            if event.succeeded {
                lastSync = event.endDate ?? .now
                AppGroup.defaults.removeObject(forKey: SettingsKey.lastSyncError)
                if case .failed = status { status = .syncing }
            } else if let message = event.errorMessage {
                DebugLog.write("cloud: event failed \(message)")
                status = .failed(message)
                return
            }
        } else {
            runningEvents.insert(event.id)
        }
        refreshStatus()
    }

    nonisolated static func message(for error: any Error) -> String {
        let nsError = error as NSError
        // CKError codes: 9 notAuthenticated, 25 quotaExceeded, 3/4 network, 36 managedAccountRestricted.
        if nsError.domain == "CKErrorDomain" {
            switch nsError.code {
            case 9: return "Sign in to iCloud to sync."
            case 25: return "Your iCloud storage is full."
            case 3, 4: return "Waiting for a network connection."
            case 36: return "iCloud is restricted on this device."
            default: break
            }
        }
        return nsError.localizedDescription
    }

    private func scheduleRemoteChangeWork() {
        remoteChangeTask?.cancel()
        remoteChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let context = self.store?.container?.mainContext else { return }
            var changed = LibraryDeduplicator.run(context: context) > 0
            // A folder that arrived under a name already here, with nothing in it, folds in quietly.
            changed = FolderMerge.mergeEmptySided(context: context) > 0 || changed
            if changed {
                self.library?.refresh()
            }
            await self.uploadPendingMedia(context: context)
        }
    }

    // MARK: Turning sync on and off

    /// Media bytes this device would upload.
    func uploadSize(context: ModelContext) -> Int64 {
        let items = (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.fileName != "" }))) ?? []
        return items.filter { $0.mediaInCloud != true && !$0.isYouTube }.reduce(0) { $0 + Int64($1.byteCount) }
    }

    func turnOn() async {
        guard !isEnabled, switching == .none else { return }
        guard isAccountAvailable else {
            status = .unavailable
            return
        }
        switching = .turningOn
        _ = await CloudContainer.resolve()
        AppGroup.defaults.set(true, forKey: SettingsKey.cloudSync)
        AppGroup.defaults.removeObject(forKey: SettingsKey.lastSyncError)
        guard await store?.reopen() == true else {
            AppGroup.defaults.set(false, forKey: SettingsKey.cloudSync)
            switching = .none
            status = .failed(AppGroup.defaults.string(forKey: SettingsKey.lastSyncError) ?? "The library couldn't be reopened. Try again.")
            return
        }
        switching = .none
        refreshStatus()
        if let context = store?.container?.mainContext {
            LibraryDeduplicator.run(context: context)
            FolderMerge.mergeEmptySided(context: context)
            await uploadPendingMedia(context: context)
        }
    }

    /// Brings every media file back to this device, then stops syncing here.
    /// Returns false when stopped before everything was downloaded.
    @discardableResult
    func turnOff() async -> Bool {
        guard isEnabled, switching == .none, let context = store?.container?.mainContext else { return false }
        cancelSwitch = false
        uploadTask?.cancel()
        if let uploadTask { await uploadTask.value }
        uploadTask = nil
        let items = (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.fileName != "" }))) ?? []
        let names = items.filter { !$0.isYouTube }.map(\.fileName).filter(CloudMediaMover.isOnlyInCloud(fileName:))
        switching = .downloading(done: 0, total: names.count)
        var failed = 0
        for (index, name) in names.enumerated() {
            if cancelSwitch {
                switching = .none
                return false
            }
            if !(await CloudMediaMover.download(fileName: name)) {
                failed += 1
            }
            switching = .downloading(done: index + 1, total: names.count)
        }
        if failed > 0 {
            DebugLog.write("cloud: \(failed) files stayed in iCloud")
            switching = .none
            status = .failed("Some files couldn't be downloaded. iCloud sync stays on so your items remain available. Try again when you have a connection and enough storage.")
            return false
        }
        guard !cancelSwitch, !Task.isCancelled else {
            switching = .none
            return false
        }
        switching = .turningOff
        AppGroup.defaults.set(false, forKey: SettingsKey.cloudSync)
        guard await store?.reopen() == true else {
            AppGroup.defaults.set(true, forKey: SettingsKey.cloudSync)
            switching = .none
            status = .failed(AppGroup.defaults.string(forKey: SettingsKey.lastSyncError) ?? "The library couldn't be reopened. Try again.")
            return false
        }
        pendingUploads = 0
        runningEvents.removeAll()
        switching = .none
        refreshStatus()
        return failed == 0
    }

    func cancelSwitching() {
        cancelSwitch = true
    }

    // MARK: Media

    /// Moves media that is only on this device into iCloud.
    func uploadPendingMedia(context: ModelContext) async {
        guard isEnabled, store?.isSyncActive == true, uploadTask == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            let items = (try? context.fetch(FetchDescriptor<Shot>(predicate: #Predicate<Shot> { $0.fileName != "" }))) ?? []
            let pending = items.filter { $0.mediaInCloud != true && !$0.isYouTube }
            self.pendingUploads = pending.count
            self.refreshStatus()
            var changed = 0
            for item in pending {
                if Task.isCancelled { break }
                let outcome = await CloudMediaMover.upload(fileName: item.fileName, thumbnailName: item.thumbnailName)
                switch outcome {
                case .moved, .alreadyInCloud:
                    item.mediaInCloud = true
                    changed += 1
                case .missing, .failed:
                    break
                }
                self.pendingUploads = max(0, self.pendingUploads - 1)
                if changed > 0, changed % 20 == 0 {
                    try? context.save()
                }
                self.refreshStatus()
            }
            if changed > 0 {
                try? context.save()
            }
            self.pendingUploads = 0
            self.refreshStatus()
        }
        uploadTask = task
        await task.value
        uploadTask = nil
    }

    var statusText: String {
        switch status {
        case .off:
            return "Off"
        case .unavailable:
            return isAccountAvailable ? "Waiting for iCloud" : "Sign in to iCloud and turn on iCloud Drive"
        case .syncing:
            return "Syncing…"
        case let .uploading(count):
            return count == 1 ? "Uploading 1 item…" : "Uploading \(LaqtaFormat.number(count)) items…"
        case let .upToDate(date):
            guard let date else { return "On" }
            return "Up to date · \(LaqtaFormat.relative(date))"
        case let .failed(message):
            return message
        }
    }
}
