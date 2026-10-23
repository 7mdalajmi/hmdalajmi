//
//  BackgroundWork.swift
//  Laqta
//
//  Work that runs when Laqta isn't on screen: a maintenance task iOS runs when the
//  device is idle (analysis, uploads, backups, YouTube details, Recently Deleted), and
//  user-started work (backups, exports, restores) that keeps going after leaving the app.
//

import BackgroundTasks
import Foundation
import Observation
import SwiftData
import UIKit

nonisolated enum BackgroundWork {
    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Hmdalajmi.Laqta"
    }

    static var maintenanceIdentifier: String { "\(bundleID).maintenance" }
    static var continuedPrefix: String { "\(bundleID).continued." }

    /// Asks iOS for time later to finish the work that's left.
    static func scheduleMaintenance(pendingAnalysis: Int, needsNetwork: Bool) {
        guard !AppEnvironment.isRunningTests else { return }
        let request = BGProcessingTaskRequest(identifier: maintenanceIdentifier)
        request.requiresNetworkConnectivity = needsNetwork
        // Large batches wait for the charger, so analysis never drains the battery.
        request.requiresExternalPower = pendingAnalysis > 40
        request.earliestBeginDate = Date.now.addingTimeInterval(10 * 60)
        BGTaskScheduler.shared.submitTaskRequest(request) { @Sendable error in
            if let error {
                DebugLog.write("bg: maintenance not scheduled \(error)")
            }
        }
    }
}

/// Keeps a `BGTask` crossing into the main actor; its methods are safe to call from any thread.
nonisolated struct BackgroundTaskBox: @unchecked Sendable {
    let task: BGTask
}

/// Progress for user-started work, shown in the app and in the system's background notice.
@MainActor
final class WorkReporter {
    var onChange: ((Double, String) -> Void)?

    func report(_ fraction: Double, _ detail: String) {
        onChange?(fraction, detail)
    }
}

@MainActor
final class ContinuedWork {
    static let shared = ContinuedWork()

    private final class CancellationRelay {
        private var cancelled = false
        private var job: Task<Void, Never>?

        func install(_ job: Task<Void, Never>) {
            self.job = job
            if cancelled { job.cancel() }
        }

        func cancel() {
            cancelled = true
            job?.cancel()
        }
    }

    private final class Gate {
        private(set) var claimed = false

        func claim() -> Bool {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }

    /// Runs `work`. When iOS allows it, the work runs as a continued processing task, so it
    /// keeps going with a progress notice after the user leaves Laqta.
    func perform(
        title: String,
        subtitle: String,
        reporter: WorkReporter,
        work: @escaping @MainActor @Sendable () async -> Void
    ) async {
        guard !AppEnvironment.isRunningTests else {
            await work()
            return
        }
        let identifier = BackgroundWork.continuedPrefix + UUID().uuidString
        let gate = Gate()
        let cancellation = CancellationRelay()
        await withTaskCancellationHandler {
          await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
                let box = BackgroundTaskBox(task: task)
                MainActor.assumeIsolated {
                    guard gate.claim() else {
                        box.task.setTaskCompleted(success: true)
                        return
                    }
                    self.run(box, title: title, reporter: reporter, cancellation: cancellation, work: work) {
                        continuation.resume()
                    }
                }
            }
            guard registered else {
                _ = gate.claim()
                Task { @MainActor in
                    await self.runInForeground(title: title, cancellation: cancellation, work: work)
                    continuation.resume()
                }
                return
            }
            let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
            request.strategy = .fail
            BGTaskScheduler.shared.submitTaskRequest(request) { @Sendable error in
                guard let error else { return }
                DebugLog.write("bg: continued task not started \(error)")
                Task { @MainActor in
                    guard gate.claim() else { return }
                    await self.runInForeground(title: title, cancellation: cancellation, work: work)
                    continuation.resume()
                }
            }
            // If iOS neither starts the task nor reports an error, don't keep the user waiting.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard gate.claim() else { return }
                await self.runInForeground(title: title, cancellation: cancellation, work: work)
                continuation.resume()
            }
          }
        } onCancel: {
            Task { @MainActor in cancellation.cancel() }
        }
    }

    private func run(
        _ box: BackgroundTaskBox,
        title: String,
        reporter: WorkReporter,
        cancellation: CancellationRelay,
        work: @escaping @MainActor @Sendable () async -> Void,
        done: @escaping @MainActor () -> Void
    ) {
        guard let task = box.task as? BGContinuedProcessingTask else {
            box.task.setTaskCompleted(success: false)
            Task { @MainActor in
                await self.runInForeground(title: title, cancellation: cancellation, work: work)
                done()
            }
            return
        }
        task.progress.totalUnitCount = 1_000
        reporter.onChange = { fraction, detail in
            task.progress.completedUnitCount = Int64(max(0, min(1, fraction)) * 1_000)
            task.updateTitle(title, subtitle: detail)
        }
        let job = Task { @MainActor in
            if !Task.isCancelled { await work() }
            reporter.onChange = nil
            task.setTaskCompleted(success: !Task.isCancelled)
            done()
        }
        cancellation.install(job)
        task.expirationHandler = {
            job.cancel()
        }
    }

    private final class Token {
        var identifier = UIBackgroundTaskIdentifier.invalid

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }

    /// Runs in the app, with the extra time iOS gives after leaving it.
    private func runInForeground(title: String, cancellation: CancellationRelay, work: @escaping @MainActor @Sendable () async -> Void) async {
        let token = Token()
        let job = Task { @MainActor in
            if !Task.isCancelled { await work() }
        }
        cancellation.install(job)
        token.identifier = UIApplication.shared.beginBackgroundTask(withName: title) {
            MainActor.assumeIsolated {
                job.cancel()
                token.end()
            }
        }
        await job.value
        token.end()
    }
}

/// Everything Laqta catches up on when iOS gives it time.
@Observable
final class Maintenance {
    let store: LibraryStore
    let library: LibraryModel
    let intelligence: IntelligenceCenter
    let cloud: CloudSyncModel
    let backups: BackupCenter

    init(store: LibraryStore, library: LibraryModel, intelligence: IntelligenceCenter, cloud: CloudSyncModel, backups: BackupCenter) {
        self.store = store
        self.library = library
        self.intelligence = intelligence
        self.cloud = cloud
        self.backups = backups
    }

    /// The system's maintenance task.
    func runInBackground() async {
        guard let context = store.container?.mainContext else { return }
        DebugLog.write("bg: maintenance started")
        library.purgeExpiredTrash(context: context)
        await MediaStore.purgeStaging()
        guard !Task.isCancelled else { return scheduleIfNeeded(context: context) }
        await YouTubeRefresher.refreshMissing(context: context)
        guard !Task.isCancelled else { return scheduleIfNeeded(context: context) }
        await cloud.uploadPendingMedia(context: context)
        guard !Task.isCancelled else { return scheduleIfNeeded(context: context) }
        await backups.runIfDue()
        guard !Task.isCancelled else { return scheduleIfNeeded(context: context) }
        await intelligence.runInBackground(context: context)
        scheduleIfNeeded(context: context)
        DebugLog.write("bg: maintenance finished cancelled=\(Task.isCancelled)")
    }

    /// When the app goes to the background.
    func appDidEnterBackground() {
        guard let context = store.container?.mainContext else { return }
        scheduleIfNeeded(context: context)
    }

    func scheduleIfNeeded(context: ModelContext) {
        let pending = AppGroup.bool(SettingsKey.analyzeShots) ? intelligence.pendingCount(context: context) : 0
        let backupDue = backups.isDue
        let uploads = cloud.isEnabled && cloud.pendingUploads > 0
        let youTube = YouTubeRefresher.links(context: context).contains(where: YouTubeRefresher.needsDetails)
        guard pending > 0 || backupDue || uploads || youTube else { return }
        BackgroundWork.scheduleMaintenance(pendingAnalysis: pending, needsNetwork: backupDue || uploads || youTube)
    }
}
