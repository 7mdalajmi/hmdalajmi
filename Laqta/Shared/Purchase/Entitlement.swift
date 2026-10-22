//
//  Entitlement.swift
//  Laqta — Shared (App + Share Extension)
//
//  Laqta is free for thirty days. After that it keeps every shot, folder and backup
//  exactly where it is — browsing, search and export carry on — but it stops taking
//  anything new until the app is bought, once, for good.
//
//  The app works the answer out from the App Store and leaves it here; the Share
//  Extension only reads it, because an extension has a second to draw and no business
//  talking to the store.
//

import Foundation

/// The two things Laqta sells: a free stamp that starts the clock, and the app itself.
nonisolated enum LaqtaProduct {
    /// Free. Bought silently the first time Laqta opens, so the thirty days survive
    /// a reinstall and a new phone — the App Store remembers the date, not the device.
    static let trial = "Hmdalajmi.Laqta.trial30"
    /// One payment. No subscription, no second charge, every future update included.
    static let unlock = "Hmdalajmi.Laqta.unlock"

    static let all: [String] = [trial, unlock]
}

/// What Laqta may do right now.
nonisolated enum LibraryAccess: Equatable, Sendable {
    /// The thirty days are running.
    case trial(daysLeft: Int)
    /// They ran out. Everything stays; nothing new comes in.
    case expired
    /// Bought.
    case bought

    var isBought: Bool { self == .bought }
    var isExpired: Bool { self == .expired }

    /// Saving, importing and new folders — the only things the trial's end takes away.
    var canAddThings: Bool { !isExpired }

    var daysLeft: Int? {
        if case let .trial(days) = self { return days }
        return nil
    }

    /// The last few days, when the banner should be harder to miss.
    var isRunningOut: Bool {
        guard let daysLeft else { return false }
        return daysLeft <= 5
    }
}

nonisolated enum Entitlement {
    /// Thirty days, counted from the moment the App Store recorded the free trial.
    static let trialDays = 30

    // MARK: The answer

    /// Worked out from stored dates only — no store, no network, safe in the extension.
    static var current: LibraryAccess {
        access(startedAt: trialStartedAt, isBought: isBought)
    }

    static var canAddThings: Bool { current.canAddThings }

    /// The whole rule, in one pure function the tests can drive.
    static func access(
        startedAt: Date?,
        isBought: Bool,
        now: Date = .now,
        days: Int = trialDays
    ) -> LibraryAccess {
        if isBought { return .bought }
        // Nothing recorded yet: the first launch hasn't finished. Laqta stays open.
        guard let startedAt else { return .trial(daysLeft: days) }
        let ends = startedAt.addingTimeInterval(Double(days) * 86_400)
        let remaining = ends.timeIntervalSince(now)
        if remaining <= 0 { return .expired }
        // A clock turned back can't buy extra days.
        let left = min(days, Int(ceil(remaining / 86_400)))
        return .trial(daysLeft: max(1, left))
    }

    // MARK: What's stored

    /// When the thirty days began. The earliest date anything has claimed wins, so
    /// deleting the app and installing it again doesn't hand out a second month.
    static var trialStartedAt: Date? {
        let stamp = AppGroup.defaults.double(forKey: SettingsKey.trialStartedAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    static func noteTrialStart(_ date: Date) {
        let stamp = date.timeIntervalSince1970
        guard stamp > 0 else { return }
        if let existing = trialStartedAt, existing.timeIntervalSince1970 <= stamp { return }
        AppGroup.defaults.set(stamp, forKey: SettingsKey.trialStartedAt)
        DebugLog.write("trial: begins \(LaqtaFormat.shortDate(date))")
    }

    /// Used while the App Store is still answering on a first launch, so the clock
    /// starts even with no signal. A real receipt overwrites it with its own date.
    static func beginTrialIfNeeded(_ date: Date = .now) {
        guard trialStartedAt == nil else { return }
        noteTrialStart(date)
    }

    static var isBought: Bool {
        get { AppGroup.defaults.bool(forKey: SettingsKey.boughtLaqta) }
        set {
            guard newValue != isBought else { return }
            AppGroup.defaults.set(newValue, forKey: SettingsKey.boughtLaqta)
            DebugLog.write("purchase: unlocked = \(newValue)")
        }
    }

    /// Only for tests and the "reset" the debug build offers.
    static func forget() {
        AppGroup.defaults.removeObject(forKey: SettingsKey.trialStartedAt)
        AppGroup.defaults.removeObject(forKey: SettingsKey.boughtLaqta)
    }
}
