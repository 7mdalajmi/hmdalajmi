//
//  Formatting.swift
//  Laqta — Shared
//
//  English copy with Western digits: counts, relative dates, durations.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The device Laqta runs on, for copy such as "Analyzing on this iPad…".
enum LaqtaDevice {
    static var name: String {
        #if os(macOS)
        return "Mac"
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac" }
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

nonisolated enum LaqtaFormat {
    static var locale: Locale { LaqtaLocale.current }

    // MARK: Counts

    /// "1 item", "7 items" — and in Arabic the one noun that works after any number.
    ///
    /// The two words are catalog keys, not text: they are looked up, so a counted
    /// phrase reads in the reader's language instead of staying English inside an
    /// otherwise translated sentence. `localizedWord` is where the lookup happens.
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(number(value)) \(localizedWord(value == 1 ? singular : plural))"
    }

    /// A noun the catalog knows, looked up at run time.
    ///
    /// Xcode can't see through this to extract the key, so every word passed to
    /// `count` is in Localizable.xcstrings by hand. A word that isn't comes back as
    /// itself, which is exactly what it used to do everywhere.
    static func localizedWord(_ word: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: word))
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// "4 shots · 1 link", "1 link", "Empty".
    static func contents(shots: Int, links: Int) -> String {
        var stats = FolderStats()
        stats.photos = shots
        stats.links = links
        return contents(stats)
    }

    /// "12 shots · 2 videos · 1 PDF", with at most three parts ("… · 4 more").
    static func contents(_ stats: FolderStats) -> String {
        var parts: [(count: Int, text: String)] = []
        if stats.photos > 0 { parts.append((stats.photos, count(stats.photos, "shot", "shots"))) }
        if stats.videos > 0 { parts.append((stats.videos, count(stats.videos, "video", "videos"))) }
        if stats.documents > 0 { parts.append((stats.documents, count(stats.documents, "PDF", "PDFs"))) }
        if stats.links > 0 { parts.append((stats.links, count(stats.links, "link", "links"))) }
        guard !parts.isEmpty else { return localizedWord("Empty") }
        if parts.count <= 3 {
            return parts.map(\.text).joined(separator: " · ")
        }
        let rest = parts.dropFirst(2).reduce(0) { $0 + $1.count }
        return (parts.prefix(2).map(\.text) + ["\(number(rest)) \(localizedWord("more"))"]).joined(separator: " · ")
    }

    /// "184K"
    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).locale(locale))
    }

    static func bytes(_ value: Int64) -> String {
        // The system spells zero out ("Zero KB").
        guard value > 0 else { return "0 KB" }

        return value.formatted(.byteCount(style: .file).locale(locale))
    }

    // MARK: Dates

    /// "just now", "12m ago", "3h ago", "yesterday", "Sep 3", "Sep 3, 2025".
    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        let calendar = Calendar.current
        if seconds < 60 { return String(localized: "just now") }
        if seconds < 3600 { return String(localized: "\(number(Int(seconds / 60)))m ago") }
        if seconds < 24 * 3600, calendar.isDate(date, inSameDayAs: now) || seconds < 6 * 3600 {
            return String(localized: "\(number(Int(seconds / 3600)))h ago")
        }
        if calendar.isDateInYesterday(date) { return String(localized: "yesterday") }
        return shortDate(date, now: now)
    }

    static func updated(_ date: Date, now: Date = .now) -> String {
        String(localized: "Updated \(relative(date, now: now))")
    }

    /// "Sep 12" (adds the year when it is not this year).
    static func shortDate(_ date: Date, now: Date = .now) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        let style: Date.FormatStyle = sameYear
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        return date.formatted(style.locale(locale))
    }

    /// "Sep 10, 9:14 PM"
    static func dateTime(_ date: Date, now: Date = .now) -> String {
        "\(shortDate(date, now: now)), \(time(date))"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// "Today, 9:14 PM", "Yesterday, 5:48 PM", "Sep 11, 6:20 PM"
    static func viewerDate(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today, \(time(date))") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday, \(time(date))") }
        return dateTime(date, now: now)
    }

    /// "Fri 2 Oct, 8:05 PM"
    static func eventDate(_ date: Date, allDay: Bool = false) -> String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        return allDay ? day : "\(day), \(time(date))"
    }

    /// "in 16 days", "tomorrow", "today"
    static func dueIn(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        switch days {
        case ..<0: return String(localized: "passed")
        case 0: return String(localized: "today")
        case 1: return String(localized: "tomorrow")
        default: return String(localized: "in \(number(days)) days")
        }
    }

    // MARK: Durations

    /// Seconds as a whole number `Int` can actually hold.
    ///
    /// A duration can arrive from a web page's own metadata (`og:video:duration`), which
    /// is a string anyone can write. `Double("inf")` and `Double("nan")` both parse, and
    /// `Int(_:)` **traps** on either — so the clamp has to happen before the conversion,
    /// not after it in a `max(0, ...)`.
    private static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 86_400 * 365).rounded())
    }

    /// "12:48", "1:02:03"
    static func duration(_ seconds: Double) -> String {
        let total = wholeSeconds(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", locale: Locale(identifier: "en_US_POSIX"), hours, minutes, secs)
        }
        return String(format: "%d:%02d", locale: Locale(identifier: "en_US_POSIX"), minutes, secs)
    }

    /// "12 minutes 48 seconds" (VoiceOver).
    static func spokenDuration(_ seconds: Double) -> String {
        let total = wholeSeconds(seconds)
        var components = DateComponents()
        components.hour = total / 3600
        components.minute = (total % 3600) / 60
        components.second = total % 60
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = total >= 3600 ? [.hour, .minute] : [.minute, .second]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: components) ?? duration(seconds)
    }

    /// "9 min", "1 hr 5 min"
    static func travelTime(_ seconds: Double) -> String {
        let minutes = max(1, (wholeSeconds(seconds) + 30) / 60)
        if minutes < 60 { return String(localized: "\(number(minutes)) min") }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0
            ? String(localized: "\(number(hours)) hr")
            : String(localized: "\(number(hours)) hr \(number(rest)) min")
    }

    /// "5.2 km"
    static func distance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road).locale(locale))
    }
}
