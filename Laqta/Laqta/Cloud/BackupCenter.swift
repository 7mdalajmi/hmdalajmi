//
//  BackupCenter.swift
//  Laqta
//
//  Backups for the UI: automatic iCloud backups, Back Up Now, the list of backups,
//  exporting a backup file and restoring from either.
//

import CoreTransferable
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// A finished backup file, ready for Save to Files.
nonisolated struct BackupFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .laqtaBackup) { file in
            SentTransferredFile(file.url)
        }
        .suggestedFileName { $0.url.lastPathComponent }
    }
}

@Observable
final class BackupCenter {
    enum Activity: Equatable {
        case idle
        case backingUp
        case exporting
        case restoring
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let text: String
    }

    private(set) var activity: Activity = .idle
    private(set) var progress: Double = 0
    private(set) var detail = ""
    private(set) var backups: [BackupInfo] = []
    private(set) var waitingBackups = 0
    private(set) var isLoading = false
    private(set) var iCloudBytes: Int64?
    private(set) var lastBackupAt: Date?
    private(set) var lastError: String?
    /// Shown as an alert.
    var notice: Notice?

    var frequency: BackupFrequency {
        didSet { AppGroup.defaults.set(frequency.rawValue, forKey: SettingsKey.backupFrequency) }
    }

    var keepCount: Int {
        didSet { AppGroup.defaults.set(keepCount, forKey: SettingsKey.backupsToKeep) }
    }

    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private let reporter = WorkReporter()
    @ObservationIgnored private weak var store: LibraryStore?
    @ObservationIgnored private weak var library: LibraryModel?
    @ObservationIgnored private weak var intelligence: IntelligenceCenter?

    private var context: ModelContext? { store?.container?.mainContext }

    private final class Box<Value> {
        var value: Value?
    }

    init() {
        let defaults = AppGroup.defaults
        frequency = BackupFrequency(rawValue: defaults.string(forKey: SettingsKey.backupFrequency) ?? "") ?? .weekly
        let keep = defaults.integer(forKey: SettingsKey.backupsToKeep)
        keepCount = keep > 0 ? keep : 3
        let last = defaults.double(forKey: SettingsKey.lastBackupAt)
        lastBackupAt = last > 0 ? Date(timeIntervalSince1970: last) : nil
        lastError = defaults.string(forKey: SettingsKey.lastBackupError)
    }

    func configure(store: LibraryStore, library: LibraryModel, intelligence: IntelligenceCenter) {
        self.store = store
        self.library = library
        self.intelligence = intelligence
    }

    var isBusy: Bool { activity != .idle }
    var isICloudAvailable: Bool { CloudConfig.isAccountAvailable }

    /// An automatic backup is waiting to run.
    var isDue: Bool {
        guard let interval = frequency.interval, isICloudAvailable, !isBusy else { return false }
        let lastChange = AppGroup.defaults.double(forKey: SettingsKey.lastLibraryChange)
        guard let lastBackupAt else { return lastChange > 0 }
        guard lastChange > lastBackupAt.timeIntervalSince1970 else { return false }
        return Date.now.timeIntervalSince(lastBackupAt) >= interval
    }

    var summary: String {
        if activity == .backingUp { return "Backing up…" }
        guard isICloudAvailable else { return "iCloud is off" }
        guard let lastBackupAt else { return frequency == .off ? "Off" : "Not backed up yet" }
        return LaqtaFormat.relative(lastBackupAt)
    }

    // MARK: iCloud backups

    /// Runs the automatic backup when it's due (quietly).
    func runIfDue() async {
        guard isDue else { return }
        if !CloudContainer.isResolved {
            _ = await CloudContainer.resolve()
        }
        guard CloudContainer.rootURL != nil else { return }
        await backUp(userInitiated: false)
    }

    func backUpNow() {
        guard !isBusy else { return }
        job = Task {
            await ContinuedWork.shared.perform(title: "Backing up Laqta", subtitle: "Preparing…", reporter: reporter) {
                await self.backUp(userInitiated: true)
            }
            self.job = nil
        }
    }

    private func backUp(userInitiated: Bool) async {
        guard !isBusy, let context else { return }
        activity = .backingUp
        progress = 0
        detail = "Preparing…"
        defer {
            activity = .idle
        }
        if !CloudContainer.isResolved {
            _ = await CloudContainer.resolve()
        }
        let snapshot = LibrarySnapshotter.snapshot(context: context)
        let info = makeInfo()
        do {
            let finished = try await BackupEngine.backUp(snapshot, info: info, keep: keepCount, progress: progressHandler())
            lastBackupAt = finished.createdAt
            lastError = nil
            AppGroup.defaults.set(finished.createdAt.timeIntervalSince1970, forKey: SettingsKey.lastBackupAt)
            AppGroup.defaults.set(finished.mediaBytes, forKey: SettingsKey.lastBackupSize)
            AppGroup.defaults.removeObject(forKey: SettingsKey.lastBackupError)
            DebugLog.write("backup: done \(finished.itemCount) items")
            if userInitiated {
                await loadBackups()
            }
        } catch is CancellationError {
            detail = ""
        } catch BackupError.cancelled {
            detail = ""
        } catch {
            let message = error.localizedDescription
            lastError = message
            AppGroup.defaults.set(message, forKey: SettingsKey.lastBackupError)
            DebugLog.write("backup: failed \(error)")
            if userInitiated {
                notice = Notice(title: "Backup didn't finish", text: message)
            }
        }
    }

    func loadBackups() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if !CloudContainer.isResolved {
            _ = await CloudContainer.resolve()
        }
        let result = await BackupEngine.list()
        backups = result.backups
        waitingBackups = result.waiting
        iCloudBytes = await BackupEngine.iCloudUsage()
    }

    func delete(_ info: BackupInfo) async {
        backups.removeAll { $0.id == info.id }
        await BackupEngine.delete(id: info.id)
        await loadBackups()
    }

    func cancel() {
        job?.cancel()
    }

    // MARK: Files

    /// Makes a single-file backup. Returns nil when it didn't finish.
    func exportBackup() async -> BackupFile? {
        guard !isBusy else { return nil }
        let box = Box<BackupFile>()
        let task = Task {
            await ContinuedWork.shared.perform(title: "Preparing a Laqta backup", subtitle: "Preparing…", reporter: reporter) {
                box.value = await self.export()
            }
        }
        job = task
        await task.value
        job = nil
        return box.value
    }

    private func export() async -> BackupFile? {
        guard let context else { return nil }
        activity = .exporting
        progress = 0
        detail = "Preparing…"
        defer { activity = .idle }
        let snapshot = LibrarySnapshotter.snapshot(context: context)
        do {
            let url = try await BackupEngine.export(snapshot, info: makeInfo(), progress: progressHandler())
            return BackupFile(url: url)
        } catch is CancellationError {
            return nil
        } catch BackupError.cancelled {
            return nil
        } catch {
            notice = Notice(title: "The backup file wasn't made", text: error.localizedDescription)
            return nil
        }
    }

    func finishExport(_ result: Result<URL, any Error>?) {
        BackupEngine.cleanUpExports()
        guard let result else { return }
        switch result {
        case .success:
            notice = Notice(title: "Backup saved", text: "Keep the file somewhere safe. To restore it, open Backups and choose Restore from a File.")
        case let .failure(error):
            notice = Notice(title: "The backup wasn't saved", text: error.localizedDescription)
        }
    }

    // MARK: Restore

    func restore(_ info: BackupInfo) {
        runRestore {
            try await BackupEngine.prepareRestore(fromICloud: info)
        }
    }

    /// Puts the newest iCloud backup back into a library that was just started from
    /// nothing, without asking: there is nothing in it to lose, and the alternative is
    /// an empty app with the user's shots still sitting in iCloud.
    func restoreNewestAfterRecovery() async {
        guard !isBusy, context != nil else { return }
        await loadBackups()
        guard let newest = backups.max(by: { $0.createdAt < $1.createdAt }) else {
            notice = Notice(
                title: String(localized: "Nothing to put back"),
                text: waitingBackups > 0
                    ? String(localized: "Laqta started a new library. Its backups haven't finished downloading from iCloud — open Backups in Settings once they have.")
                    : String(localized: "Laqta started a new library. There is no backup of the old one in iCloud, so there is nothing to put back.")
            )
            return
        }
        DebugLog.write("store: restoring \(newest.id) into the new library")
        restore(newest)
    }

    func restore(fileAt url: URL) {
        let handler = progressHandler()
        runRestore {
            try await BackupEngine.prepareRestore(fromFile: url, progress: handler)
        }
    }

    private func runRestore(prepare: @escaping @Sendable () async throws -> PreparedRestore) {
        guard !isBusy else { return }
        job = Task {
            await ContinuedWork.shared.perform(title: "Restoring Laqta", subtitle: "Preparing…", reporter: reporter) {
                guard let context = self.context else { return }
                self.activity = .restoring
                self.progress = 0
                self.detail = "Reading the backup…"
                defer { self.activity = .idle }
                do {
                    let prepared = try await prepare()
                    let summary = try await BackupRestorer.restore(prepared, context: context) { fraction, text in
                        self.update(fraction, text)
                    }
                    self.library?.refresh()
                    self.intelligence?.processPending(context: context)
                    await YouTubeRefresher.refreshMissing(context: context)
                    self.notice = Notice(title: "Restore finished", text: summary.message)
                } catch is CancellationError {
                    self.notice = Notice(title: "Restore stopped", text: "What was restored so far stays in Laqta.")
                } catch BackupError.cancelled {
                    self.notice = Notice(title: "Restore stopped", text: "What was restored so far stays in Laqta.")
                } catch {
                    self.notice = Notice(title: "Couldn't restore", text: error.localizedDescription)
                }
            }
            self.job = nil
        }
    }

    // MARK: Helpers

    private func makeInfo() -> BackupInfo {
        let device = BackupDevice.current
        let now = Date.now
        return BackupInfo(
            id: BackupInfo.makeID(date: now),
            format: BackupInfo.currentFormat,
            createdAt: now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            deviceName: device.name,
            deviceID: device.id,
            folderCount: 0,
            itemCount: 0,
            mediaBytes: 0
        )
    }

    private func progressHandler() -> BackupEngine.Progress {
        { [weak self] fraction, text in
            Task { @MainActor in
                self?.update(fraction, text)
            }
        }
    }

    private func update(_ fraction: Double, _ text: String) {
        progress = fraction
        detail = text
        reporter.report(fraction, text)
    }
}
