//
//  ReminderCenter.swift
//  Laqta
//
//  The nudge before the thing. You choose how early once — the day before, two
//  days before, or the morning of — and it arrives as one line on the lock
//  screen with the shot itself attached.
//
//  Everything here is local. A reminder is a UNNotificationRequest on this phone;
//  nothing is registered with a server and nothing is sent anywhere.
//

import Foundation
import Observation
import SwiftUI
import UserNotifications

// MARK: - How early

nonisolated enum ReminderLead: Int, CaseIterable, Identifiable, Sendable {
    case morningOf = 0
    case dayBefore = 1
    case twoDays = 2

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .morningOf: "The morning of"
        case .dayBefore: "The day before"
        case .twoDays: "Two days before"
        }
    }

    /// The same choice in a couple of words, for a settings row that has one line.
    var short: LocalizedStringKey {
        switch self {
        case .morningOf: "Morning of"
        case .dayBefore: "Day before"
        case .twoDays: "Two days"
        }
    }

    /// The hour it lands. The morning of is earlier, because the day has started.
    var hour: Int { self == .morningOf ? 7 : 9 }

    /// When a reminder for `event` would fire, or nil if that moment has passed.
    func fireDate(for event: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: event)
        guard let shifted = calendar.date(byAdding: .day, value: -rawValue, to: day),
              let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shifted) else { return nil }
        return fire > now ? fire : nil
    }

    /// The soonest lead that has not already gone by — so a flight two days out
    /// still gets told about, even when "two days before" is the saved default.
    static func usable(from preferred: ReminderLead, for event: Date, now: Date = .now, calendar: Calendar = .current) -> ReminderLead? {
        let ladder = allCases.filter { $0.rawValue <= preferred.rawValue }.sorted { $0.rawValue > $1.rawValue }
        return ladder.first { $0.fireDate(for: event, now: now, calendar: calendar) != nil }
    }
}

// MARK: - The centre

@Observable
@MainActor
final class ReminderCenter {
    /// Set once in Settings, overridden per item from the shot itself.
    var defaultLead: ReminderLead {
        get { ReminderLead(rawValue: AppGroup.defaults.integer(forKey: SettingsKey.reminderLeadDays)) ?? .dayBefore }
        set {
            AppGroup.defaults.set(newValue.rawValue, forKey: SettingsKey.reminderLeadDays)
            version &+= 1
        }
    }

    /// Bumped on every change so views redraw. Views read it; nothing else should.
    private(set) var version = 0

    /// True once iOS has been asked and said yes.
    private(set) var isAllowed = false
    private(set) var didAsk = false

    private var overrides: [String: Int] {
        get { AppGroup.defaults.dictionary(forKey: SettingsKey.reminderOverrides) as? [String: Int] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: SettingsKey.reminderOverrides) }
    }

    private var scheduled: Set<String> {
        get { Set(AppGroup.defaults.stringArray(forKey: SettingsKey.reminderScheduled) ?? []) }
        set { AppGroup.defaults.set(Array(newValue), forKey: SettingsKey.reminderScheduled) }
    }

    // MARK: Choices

    /// What this one item is set to — its own choice, or the default.
    func lead(for itemID: UUID) -> ReminderLead {
        guard let raw = overrides[itemID.uuidString], let lead = ReminderLead(rawValue: raw) else { return defaultLead }
        return lead
    }

    func hasOwnChoice(_ itemID: UUID) -> Bool {
        overrides[itemID.uuidString] != nil
    }

    func setLead(_ lead: ReminderLead, for itemID: UUID) {
        var current = overrides
        current[itemID.uuidString] = lead.rawValue
        overrides = current
        version &+= 1
    }

    func clearLead(for itemID: UUID) {
        var current = overrides
        current.removeValue(forKey: itemID.uuidString)
        overrides = current
        version &+= 1
    }

    func isScheduled(_ itemID: UUID) -> Bool {
        scheduled.contains(itemID.uuidString)
    }

    // MARK: Permission

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        didAsk = settings.authorizationStatus != .notDetermined
        isAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Asks the first time a reminder is actually wanted, never on launch.
    @discardableResult
    func requestPermission() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        didAsk = true
        isAllowed = granted
        return granted
    }

    // MARK: Scheduling

    static func identifier(for itemID: UUID) -> String { "laqta.reminder.\(itemID.uuidString)" }

    // MARK: The tap

    /// The shot a tapped reminder asked for, until a screen takes it. `RootView`
    /// watches this and clears it.
    private(set) var tappedItemID: UUID?

    /// Held here because `UNUserNotificationCenter.delegate` is a weak reference.
    private var router: ReminderRouter?

    /// Starts listening for taps. Apple requires the delegate to be set before the
    /// app finishes launching, so this is called from `LaqtaApp.init`.
    func startRouting() {
        guard router == nil else { return }
        let router = ReminderRouter(reminders: self)
        self.router = router
        UNUserNotificationCenter.current().delegate = router
    }

    func noteTapped(_ itemID: UUID) { tappedItemID = itemID }

    func clearTapped() { tappedItemID = nil }

    /// Puts one reminder on the lock screen. Returns false when there is no
    /// moment left to fire at, or iOS said no.
    @discardableResult
    func schedule(_ dated: DatedShot, lead: ReminderLead? = nil, thumbnailURL: URL? = nil, now: Date = .now) async -> Bool {
        let wanted = lead ?? self.lead(for: dated.itemID)
        guard let usable = ReminderLead.usable(from: wanted, for: dated.date, now: now),
              let fire = usable.fireDate(for: dated.date, now: now) else { return false }
        await refreshPermission()
        if !isAllowed {
            guard await requestPermission() else { return false }
        }

        let content = UNMutableNotificationContent()
        content.title = Self.headline(for: dated, firing: fire)
        content.body = Self.body(for: dated)
        content.sound = .default
        content.userInfo = ["itemID": dated.itemID.uuidString]
        if let attachment = Self.attachment(for: dated, thumbnailURL: thumbnailURL) {
            content.attachments = [attachment]
        }

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: dated.itemID),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            var current = scheduled
            current.insert(dated.itemID.uuidString)
            scheduled = current
            version &+= 1
            return true
        } catch {
            return false
        }
    }

    func cancel(itemID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.identifier(for: itemID)]
        )
        var current = scheduled
        current.remove(itemID.uuidString)
        scheduled = current
        version &+= 1
    }

    /// Drops reminders for shots that are gone or whose day has passed, so the
    /// bookkeeping does not grow forever.
    func prune(keeping live: Set<UUID>) async {
        let centre = UNUserNotificationCenter.current()
        let alive = Set(await centre.pendingNotificationRequests().map(\.identifier))
        var kept: Set<String> = []
        for stored in scheduled {
            guard let id = UUID(uuidString: stored) else { continue }
            let identifier = Self.identifier(for: id)
            guard live.contains(id) else {
                // The shot was deleted, or its day has been and gone.
                centre.removePendingNotificationRequests(withIdentifiers: [identifier])
                continue
            }
            // iOS drops a request once it has fired; that is not one we still hold.
            if alive.contains(identifier) { kept.insert(stored) }
        }
        scheduled = kept
        version &+= 1
    }

    // MARK: Wording

    /// "Kuwait → Dubai is tomorrow"
    static func headline(for dated: DatedShot, firing: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: firing),
            to: calendar.startOfDay(for: dated.date)
        ).day ?? 0
        switch days {
        case 0: return "\(dated.title) is today"
        case 1: return "\(dated.title) is tomorrow"
        default: return "\(dated.title) is in \(days) days"
        }
    }

    static func body(for dated: DatedShot) -> String {
        let when = LaqtaFormat.eventDate(dated.date, allDay: dated.allDay)
        guard let detail = dated.detail, !detail.isEmpty else { return when }
        return "\(detail) · \(when)"
    }

    /// The shot rides along with the notification.
    ///
    /// iOS *moves* an attachment into its own store, so the library's own
    /// thumbnail is copied to a throwaway file first — handing over the real one
    /// would delete it from Laqta.
    private static func attachment(for dated: DatedShot, thumbnailURL: URL?) -> UNNotificationAttachment? {
        guard let source = thumbnailURL, FileManager.default.fileExists(atPath: source.path) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Reminders", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: "\(dated.itemID.uuidString)-\(UUID().uuidString).jpg")
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            return try UNNotificationAttachment(identifier: dated.itemID.uuidString, url: copy, options: nil)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            return nil
        }
    }
}
