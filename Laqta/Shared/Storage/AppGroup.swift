//
//  AppGroup.swift
//  Laqta — Shared (App + Share Extension)
//
//  Storage shared by the app and the Share Extension (App Group).
//

import Foundation
import Synchronization

/// Paths and shared settings that live inside the App Group container,
/// so the app and the Share Extension read and write the same library.
nonisolated enum AppGroup {
    /// Comes from the `LaqtaAppGroupID` Info.plist key (build setting `APP_GROUP_ID`).
    static let identifier: String = {
        (Bundle.main.object(forInfoDictionaryKey: "LaqtaAppGroupID") as? String)
            ?? "group.Hmdalajmi.Laqta"
    }()

    /// Tests point the library at a temporary folder.
    private static let testRoot = Mutex<URL?>(nil)

    static func useTestRoot(_ url: URL?) {
        testRoot.withLock { $0 = url }
    }

    private static var testRootURL: URL? {
        testRoot.withLock { $0 }
    }

    /// Local Mac distributions stay separate; signed builds require the App Group entitlement.
    static var sharedContainerURL: URL? {
        #if os(macOS)
        if Bundle.main.object(forInfoDictionaryKey: "LaqtaLocalDistribution") as? String == "YES" { return nil }
        #endif
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isConfigured: Bool { sharedContainerURL != nil }

    static var isRunningInExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    static var containerURL: URL {
        sharedContainerURL ?? URL.applicationSupportDirectory
    }

    static var rootURL: URL {
        if let testRootURL { return testRootURL }
        #if os(macOS)
        // A development build without App Group signing still gets its own safe library.
        guard let shared = sharedContainerURL else {
            return URL.applicationSupportDirectory.appending(path: "LaqtaMac", directoryHint: .isDirectory)
        }
        return shared.appending(path: "Library/Application Support/Laqta", directoryHint: .isDirectory)
        #else
        return containerURL.appending(path: "Library/Application Support/Laqta", directoryHint: .isDirectory)
        #endif
    }

    static var mediaURL: URL { rootURL.appending(path: "Media", directoryHint: .isDirectory) }
    static var thumbnailsURL: URL { rootURL.appending(path: "Thumbnails", directoryHint: .isDirectory) }
    static var stagingURL: URL { rootURL.appending(path: "Staging", directoryHint: .isDirectory) }
    static var cacheURL: URL { rootURL.appending(path: "Cache", directoryHint: .isDirectory) }
    static var storeURL: URL { rootURL.appending(path: "Laqta.store") }

    static var defaults: UserDefaults {
        if testRootURL != nil {
            return UserDefaults(suiteName: "Hmdalajmi.Laqta.tests") ?? .standard
        }
        #if os(macOS)
        if Bundle.main.object(forInfoDictionaryKey: "LaqtaLocalDistribution") as? String == "YES" { return .standard }
        #endif
        return UserDefaults(suiteName: identifier) ?? .standard
    }

    static func prepareDirectories() throws {
        let manager = FileManager.default
        for url in [rootURL, mediaURL, thumbnailsURL, stagingURL, cacheURL] {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Lets the app know that the Share Extension changed the library while it was in the background.
    static func markExternalChange() {
        defaults.set(Date.now.timeIntervalSince1970, forKey: SettingsKey.lastExternalChange)
    }

    static var lastExternalChange: Double {
        defaults.double(forKey: SettingsKey.lastExternalChange)
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.appearance: AppearanceMode.noir.rawValue,
            SettingsKey.autoDeleteFromPhotos: false,
            SettingsKey.analyzeShots: true,
            SettingsKey.recognizePlaces: true,
            SettingsKey.readText: true,
            SettingsKey.findSource: true,
            SettingsKey.transcribeVideos: true,
            SettingsKey.lockPrivateFolders: true,
            SettingsKey.hideInAppSwitcher: true,
            SettingsKey.extractLinks: true,
            SettingsKey.skipDuplicates: true,
            SettingsKey.cloudSync: false,
            SettingsKey.backupFrequency: BackupFrequency.weekly.rawValue,
            SettingsKey.backupsToKeep: 3,
            SettingsKey.offerClipboard: true,
            SettingsKey.showComingUp: true,
            // The day before: two days is far enough away to be forgotten again.
            SettingsKey.reminderLeadDays: 1
        ])
    }

    static func bool(_ key: String) -> Bool {
        defaults.bool(forKey: key)
    }
}

nonisolated enum SettingsKey {
    /// Delete the original from Photos after saving (default for the switch in Save to Laqta).
    static let autoDeleteFromPhotos = "autoDeleteFromPhotos"
    static let lastExternalChange = "lastExternalChange"
    static let didSeedFolders = "didSeedFolders"
    static let didUpgradeTo2 = "didUpgradeTo2"
    static let didUpgradeTo21 = "didUpgradeTo21"
    static let didCheckModelPlaces = "didCheckModelPlaces"
    static let newestFirst = "newestFirst"
    /// "noir", "ivory" or "system"
    static let appearance = "appearance"
    static let analyzeShots = "intelligenceAnalyze"
    static let recognizePlaces = "intelligencePlaces"
    static let readText = "intelligenceText"
    static let findSource = "intelligenceSource"
    static let transcribeVideos = "intelligenceTranscribe"
    static let lockPrivateFolders = "privacyLockPrivateFolders"
    static let hideInAppSwitcher = "privacyHideInAppSwitcher"
    /// Default for "Extract everything inside" when saving links.
    static let extractLinks = "linksExtractEverything"
    static let lastUsedFolderID = "lastUsedFolderID"
    /// Skip items that are already in Laqta (Save to Laqta).
    static let skipDuplicates = "saveSkipDuplicates"
    // iCloud
    static let cloudSync = "cloudSyncEnabled"
    static let backupFrequency = "backupFrequency"
    static let backupsToKeep = "backupsToKeep"
    static let lastBackupAt = "backupLastDate"
    static let lastBackupSize = "backupLastSize"
    static let lastBackupError = "backupLastError"
    static let lastSyncError = "cloudLastSyncError"
    /// Same-name folders the user chose to keep apart, so the offer isn't made twice.
    static let declinedFolderMerges = "cloudDeclinedFolderMerges"
    static let lastLibraryChange = "libraryLastChange"
    /// A damaged library was set aside: the app puts the newest backup into the new one.
    static let needsBackupAfterRecovery = "libraryNeedsBackupAfterRecovery"
    /// When the Share Extension first had to save without iCloud mirroring, so the app
    /// can make sure those items reach iCloud.
    static let savedWithoutSyncSince = "cloudSavedWithoutSyncSince"
    static let lastPurgeAt = "trashLastPurge"
    static let lastYouTubeRefresh = "youTubeLastRefresh"
    // Trial and purchase
    /// When the thirty free days began, as the App Store recorded it.
    static let trialStartedAt = "purchaseTrialStartedAt"
    static let boughtLaqta = "purchaseUnlocked"
    /// The last time the app asked the App Store, so a long silence can be noticed.
    static let purchaseCheckedAt = "purchaseCheckedAt"
    /// The welcome card that starts the thirty days is shown once.
    static let didShowWelcome = "purchaseDidShowWelcome"

    // 2.3
    /// The clipboard change count we last offered to keep, so one answer is enough.
    static let clipboardAnsweredAt = "clipboardAnsweredAt"
    /// Offer to keep a link sitting in the clipboard when Laqta opens.
    static let offerClipboard = "offerClipboard"
    /// How early a reminder lands: 2 = two days, 1 = the day before, 0 = the morning of.
    static let reminderLeadDays = "reminderLeadDays"
    /// Per-item overrides of the lead time, keyed by item UUID.
    static let reminderOverrides = "reminderOverrides"
    /// Which items already have a notification scheduled, keyed by item UUID.
    static let reminderScheduled = "reminderScheduled"
    /// Show what is coming up above the folders.
    static let showComingUp = "showComingUp"
}

/// Keys the app checks to know it runs under tests.
nonisolated enum AppEnvironment {
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()
}
