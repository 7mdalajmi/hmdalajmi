//
//  CloudConfig.swift
//  Laqta — Shared
//
//  iCloud identifiers and the location of Laqta's iCloud container.
//

import Foundation
import Synchronization

nonisolated enum CloudConfig {
    /// CloudKit database and iCloud Drive container shared by all of the user's devices.
    static let containerIdentifier = "iCloud.Hmdalajmi.Laqta"

    static var isSyncEnabled: Bool {
        AppGroup.bool(SettingsKey.cloudSync)
    }

    /// Signed in to iCloud with iCloud Drive on (fast; doesn't touch the container).
    static var isAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}

nonisolated enum BackupFrequency: String, CaseIterable, Sendable, Identifiable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .daily: 20 * 3600
        case .weekly: 6.5 * 86_400
        }
    }
}

/// Laqta's iCloud container. The first lookup can block, so the app resolves it
/// off the main thread at launch and the rest of the code reads the cached value.
nonisolated enum CloudContainer {
    private enum State: Sendable {
        case unknown
        case resolved(URL?)
    }

    private static let state = Mutex<State>(.unknown)

    /// `nil` until resolved, or when iCloud Drive is unavailable.
    static var rootURL: URL? {
        state.withLock { current in
            if case let .resolved(url) = current { return url }
            return nil
        }
    }

    static var isResolved: Bool {
        state.withLock { current in
            if case .resolved = current { return true }
            return false
        }
    }

    /// Looks up the container (never call this on the main thread).
    @concurrent
    static func resolve() async -> URL? {
        guard !AppGroup.isRunningInExtension else { return nil }
        let url = FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerIdentifier)
        state.withLock { $0 = .resolved(url) }
        return url
    }

    /// Forgets the cached container (the iCloud account changed).
    static func reset() {
        state.withLock { $0 = .unknown }
    }

    /// Hidden folders that sync but don't show in the Files app.
    static var mediaURL: URL? { rootURL?.appending(path: "Media", directoryHint: .isDirectory) }
    static var thumbnailsURL: URL? { rootURL?.appending(path: "Thumbnails", directoryHint: .isDirectory) }
    /// iCloud backups (not shown in the Files app; exported backups are).
    static var backupsURL: URL? { rootURL?.appending(path: "Backups", directoryHint: .isDirectory) }
}

nonisolated enum CloudMedia {
    /// Where a media file lives in iCloud. Files moved there while sync was on stay
    /// readable after sync is turned off, as long as iCloud Drive is on.
    static func mediaURL(for fileName: String) -> URL? {
        guard !fileName.isEmpty, let folder = CloudContainer.mediaURL else { return nil }
        return folder.appending(path: fileName)
    }

    static func thumbnailURL(for fileName: String) -> URL? {
        guard !fileName.isEmpty, let folder = CloudContainer.thumbnailsURL else { return nil }
        return folder.appending(path: fileName)
    }
}
