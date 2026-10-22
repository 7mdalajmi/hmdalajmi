//
//  ShareSessionModel.swift
//  لقطة — Share Extension
//
//  يجهّز الصور المشتركة، يحفظها في المجلد المختار، ثم يحذف الأصل من ألبوم الصور (إن كان الخيار مفعّلًا).
//

import Foundation
import Observation
import Photos
import SwiftData
import UIKit

@Observable
final class ShareSessionModel {
    nonisolated enum RemovalOutcome: Equatable, Sendable {
        case notRequested
        case removed(Int)
        case waitingForApp
        case declined
    }

    nonisolated enum Phase: Equatable, Sendable {
        case preparing
        case ready
        case saving
        case removingOriginals
        case done(folderName: String, count: Int, removal: RemovalOutcome)
        case failed(String)
    }

    private(set) var phase: Phase = .preparing
    private(set) var staged: [StagedImage] = []
    private(set) var previews: [UUID: UIImage] = [:]
    private(set) var failedCount = 0
    private(set) var queuedFolderID: UUID?

    private let providers: [ProviderBox]
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    @ObservationIgnored private var didPrepare = false

    init(providers: [NSItemProvider], onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.providers = providers.map(ProviderBox.init(provider:))
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var incomingCount: Int { providers.count }

    var isBusy: Bool {
        switch phase {
        case .saving, .removingOriginals, .done: true
        default: false
        }
    }

    // MARK: Preparing

    func prepare(context: ModelContext) async {
        guard !didPrepare else { return }
        didPrepare = true

        for box in providers {
            do {
                let item = try await ItemProviderLoader.stage(box)
                staged.append(item)
                if let thumbnailURL = item.thumbnailURL,
                   let preview = await ImageLoader.image(at: thumbnailURL, maxPixelSize: 360) {
                    previews[item.id] = preview.image
                }
            } catch {
                failedCount += 1
            }
        }

        guard !staged.isEmpty else {
            phase = .failed(providers.isEmpty ? "لا توجد صور لحفظها." : "تعذّر قراءة الصورة المشتركة.")
            return
        }
        phase = .ready

        if let queuedFolderID, let folder = folder(with: queuedFolderID, context: context) {
            await save(to: folder, context: context)
        }
    }

    // MARK: Saving

    func choose(_ folder: Folder, context: ModelContext) async {
        switch phase {
        case .preparing:
            queuedFolderID = folder.id
        case .ready:
            await save(to: folder, context: context)
        default:
            break
        }
    }

    private func save(to folder: Folder, context: ModelContext) async {
        phase = .saving
        let autoDelete = AppGroup.defaults.bool(forKey: SettingsKey.autoDeleteFromPhotos)

        var shots: [Shot] = []
        for item in staged {
            do {
                let files = try MediaStore.commit(item)
                let shot = Shot(staged: item, files: files, folderID: folder.id)
                shot.libraryStatus = autoDelete ? .pendingDeletion : .untouched
                context.insert(shot)
                shots.append(shot)
            } catch {
                MediaStore.discard(item)
                failedCount += 1
            }
        }
        staged.removeAll()

        do {
            try context.save()
        } catch {
            phase = .failed("تعذّر الحفظ: \(error.localizedDescription)")
            return
        }
        AppGroup.markExternalChange()

        var removal: RemovalOutcome = .notRequested
        if autoDelete, !shots.isEmpty {
            removal = await removeOriginals(of: shots, context: context)
        }

        phase = .done(folderName: folder.name, count: shots.count, removal: removal)
        let delay: Double = removal == .notRequested ? 0.9 : 1.8
        try? await Task.sleep(for: .seconds(delay))
        onFinish()
    }

    private func removeOriginals(of shots: [Shot], context: ModelContext) async -> RemovalOutcome {
        guard PhotoLibraryService.canModifyLibrary else {
            DebugLog.write("extension: Photos status \(PhotoLibraryService.authorizationStatus.rawValue), deferring to app")
            return .waitingForApp
        }
        phase = .removingOriginals

        let matches = await PhotoLibraryService.resolve(shots.map(\.fingerprint))
        let identifiers = Array(Set(matches.values))
        guard !identifiers.isEmpty else { return .waitingForApp }

        let outcome: RemovalOutcome
        do {
            try await PhotoLibraryService.deleteAssets(withIdentifiers: identifiers)
            for shot in shots where matches[shot.id] != nil {
                shot.libraryStatus = .deleted
            }
            outcome = .removed(identifiers.count)
        } catch {
            DebugLog.write("extension: delete failed \(error)")
            guard PhotoLibraryService.isUserCancellation(error) else { return .waitingForApp }
            for shot in shots where matches[shot.id] != nil {
                shot.libraryStatus = .declined
            }
            outcome = .declined
        }
        try? context.save()
        AppGroup.markExternalChange()
        return outcome
    }

    // MARK: Leaving

    func cancel() {
        for item in staged {
            MediaStore.discard(item)
        }
        staged.removeAll()
        onCancel()
    }

    func close() {
        switch phase {
        case .done, .removingOriginals:
            onFinish()
        default:
            cancel()
        }
    }

    private func folder(with id: UUID, context: ModelContext) -> Folder? {
        let target = id
        var descriptor = FetchDescriptor<Folder>(predicate: #Predicate<Folder> { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
